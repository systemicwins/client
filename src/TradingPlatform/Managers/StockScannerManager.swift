import Foundation
import Combine
import SocketIO
// import UserNotifications  // Removed - problematic
import SwiftUI

class StockScannerManager: ObservableObject {
    @Published var filteredStocks: [FilteredStock] = []
    @Published var scannerSummary: ScannerSummary?
    @Published var processingStatus: ProcessingStatus?
    @Published var isLoading = false
    @Published var isConnected = false
    @Published var lastUpdate = Date()
    @Published var errorMessage: String?
    @Published var streamProgress = 0
    @Published var totalExpectedStocks = 0
    @Published var useStreaming = true  // Toggle for streaming vs batch loading
    
    private let baseURL = "https://api.relentless.market"
    private let socketManager = SocketIOManager.shared
    private let streamService = StreamService.shared
    private let sseService = SSEService.shared  // Add SSE support
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var webSocketTask: URLSessionWebSocketTask?
    
    // Track previously seen gappers for notifications
    private var previousGapperSymbols = Set<String>()
    private var hasInitialLoad = false
    
    // Notification preferences
    @AppStorage("enableGapperNotifications") private var enableGapperNotifications = true
    @AppStorage("minGapPercentForNotification") private var minGapPercentForNotification = 5.0
    
    // Race condition prevention
    private var activeFilteredRequests = Set<UUID>()
    private var activeSummaryRequests = Set<UUID>()
    private var requestDebouncer: Timer?
    private let requestQueue = DispatchQueue(label: "com.relentless.scanner.requests", attributes: .concurrent)
    private var lastSuccessfulDataTime: Date?
    private var suppressErrorsUntil: Date?
    
    init() {
        setupSocketIO()
        setupStreamSubscriptions()
        setupSSE()  // Initialize SSE connection
        startAutoRefresh()
    }
    
    deinit {
        refreshTimer?.invalidate()
        socketManager.disconnect()
        streamService.stopStream()
        sseService.disconnect()  // Disconnect SSE
    }
    
    // MARK: - API Methods
    
    func loadFilteredStocks() {
        // Debounce rapid requests
        requestDebouncer?.invalidate()
        requestDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performLoadFilteredStocks()
        }
    }
    
    private func performLoadFilteredStocks() {
        // Prevent concurrent identical requests
        let requestId = UUID()
        
        requestQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Check if we already have an active filtered stocks request
            if !self.activeFilteredRequests.isEmpty {
                print("Skipping duplicate filtered stocks request - already loading")
                return
            }
            
            self.activeFilteredRequests.insert(requestId)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            
            // Don't clear error immediately if we're within error suppression window
            if let suppressUntil = self?.suppressErrorsUntil, Date() < suppressUntil {
                // Keep existing error message during suppression window
            } else {
                self?.errorMessage = nil
            }
        }
        
        // Use the gappers endpoint for LIVE data only
        guard let url = URL(string: "\(baseURL)/gappers") else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Invalid URL"
                self?.isLoading = false
                self?.requestQueue.async(flags: .barrier) {
                    self?.activeFilteredRequests.remove(requestId)
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30 // 30 second timeout
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> ScannerFilteredResponse in
                // First check if we got HTML error page
                if let htmlString = String(data: data, encoding: .utf8),
                   htmlString.contains("<html") {
                    throw URLError(.badServerResponse)
                }
                
                let decoder = JSONDecoder()
                // Use custom date decoding that handles both ISO8601 formats
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    // Try ISO8601 with fractional seconds first
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                    
                    // Fall back to standard ISO8601
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                    
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
                }
                
                // Try to decode as GappersResponse first (for /gappers endpoint)
                do {
                    let gappersResponse = try decoder.decode(GappersResponse.self, from: data)
                    print("Successfully decoded GappersResponse with \(gappersResponse.count) gappers")
                    // Convert GappersResponse to ScannerFilteredResponse
                    let filteredStocks = gappersResponse.gappers.map { $0.toFilteredStock() }
                    print("Converted to \(filteredStocks.count) FilteredStock items")
                    if let first = filteredStocks.first {
                        print("First stock: \(first.symbol) at $\(first.currentPrice)")
                    }
                    return ScannerFilteredResponse(
                        count: gappersResponse.count,
                        stocks: filteredStocks,
                        criteria: nil,
                        timestamp: gappersResponse.lastScan,
                        status: nil,
                        message: gappersResponse.message
                    )
                } catch {
                    print("Failed to decode as GappersResponse: \(error)")
                    print("Trying ScannerFilteredResponse format...")
                }
                
                // Fall back to original ScannerFilteredResponse format
                return try decoder.decode(ScannerFilteredResponse.self, from: data)
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    
                    // Remove from active requests
                    self.requestQueue.async(flags: .barrier) {
                        self.activeFilteredRequests.remove(requestId)
                    }
                    
                    self.isLoading = false
                    
                    if case .failure(let error) = completion {
                        // Check if we should suppress this error
                        let shouldSuppressError = self.shouldSuppressError()
                        
                        if error is DecodingError {
                            if !shouldSuppressError {
                                // Only show error if not within suppression window
                                self.errorMessage = "Unable to parse scanner data"
                                print("Scanner data parsing error: \(error)")
                            } else {
                                print("Suppressing transient parsing error - data loaded successfully recently")
                            }
                        } else if (error as NSError).code == NSURLErrorTimedOut {
                            // Handle timeout specifically
                            self.errorMessage = nil
                            self.processingStatus = ProcessingStatus(
                                phase: "populating",
                                message: "Populating stocks cache, please try again in a moment.",
                                isProcessing: true,
                                progress: nil,
                                lastUpdate: Date()
                            )
                            // Retry after a delay (will be debounced)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                                self?.loadFilteredStocks()
                            }
                        } else {
                            if !shouldSuppressError {
                                self.errorMessage = "Failed to load stocks: \(error.localizedDescription)"
                            }
                        }
                        
                        if !shouldSuppressError {
                            print("Error loading filtered stocks: \(error)")
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    
                    // Remove from active requests
                    self.requestQueue.async(flags: .barrier) {
                        self.activeFilteredRequests.remove(requestId)
                    }
                    // Check for special status messages first
                    if let status = response.status, let message = response.message {
                        switch status {
                        case "populating", "loading":
                            // Cache is being populated or loaded - show friendly message
                            self.errorMessage = nil
                            self.processingStatus = ProcessingStatus(
                                phase: "populating",
                                message: message,
                                isProcessing: true,
                                progress: nil,
                                lastUpdate: Date()
                            )
                            // Retry after a delay (will be debounced)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                                self?.loadFilteredStocks()
                            }
                            return
                            
                        case "empty":
                            // Cache is empty - show informative message
                            self.errorMessage = nil
                            self.processingStatus = ProcessingStatus(
                                phase: "empty",
                                message: message,
                                isProcessing: false,
                                progress: nil,
                                lastUpdate: Date()
                            )
                            self.filteredStocks = []
                            return
                            
                        case "error":
                            // Service error - show error message
                            self.errorMessage = message
                            self.processingStatus = ProcessingStatus(
                                phase: "error",
                                message: message,
                                isProcessing: false,
                                progress: nil,
                                lastUpdate: Date()
                            )
                            self.filteredStocks = []
                            return
                            
                        default:
                            break
                        }
                    }
                    
                    // Normal response with stocks
                    print("Received response with \(response.count) stocks, actual array has \(response.stocks.count) items")
                    self.filteredStocks = response.stocks
                    self.lastUpdate = Date()
                    self.errorMessage = nil
                    print("Set filteredStocks to \(self.filteredStocks.count) items")
                    
                    // Check for new gappers and send notifications
                    self.checkForNewGappers()
                    
                    // Mark successful data load
                    self.lastSuccessfulDataTime = Date()
                    // Set error suppression window for 2 seconds after successful load
                    self.suppressErrorsUntil = Date().addingTimeInterval(2.0)
                    
                    // If no stocks found, show a helpful message
                    if response.count == 0 {
                        if let criteria = response.criteria {
                            let message = "No stocks match criteria: gain > \(criteria.min_gain ?? "N/A"), price \(criteria.price_range ?? "N/A"), float < \(criteria.max_float ?? "N/A")"
                            self.processingStatus = ProcessingStatus(
                                phase: "complete",
                                message: message,
                                isProcessing: false,
                                progress: nil,
                                lastUpdate: Date()
                            )
                        }
                    } else {
                        self.processingStatus = ProcessingStatus(
                            phase: "complete",
                            message: "Found \(response.count) stocks",
                            isProcessing: false,
                            progress: nil,
                            lastUpdate: Date()
                        )
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func loadScannerSummary() {
        // Prevent concurrent summary requests
        let requestId = UUID()
        
        requestQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Prevent duplicate summary requests
            if !self.activeSummaryRequests.isEmpty {
                print("Skipping duplicate summary request - already loading")
                return
            }
            
            self.activeSummaryRequests.insert(requestId)
        }
        
        guard let url = URL(string: "\(baseURL)/scanner/summary") else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Invalid URL"
                self?.requestQueue.async(flags: .barrier) {
                    self?.activeSummaryRequests.remove(requestId)
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> ScannerSummaryWithStatus in
                // Check for HTML error response
                if let htmlString = String(data: data, encoding: .utf8),
                   htmlString.contains("<html") {
                    throw URLError(.badServerResponse)
                }
                
                let decoder = JSONDecoder()
                // Use custom date decoding that handles both ISO8601 formats
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    
                    // Try ISO8601 with fractional seconds first
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                    
                    // Fall back to standard ISO8601
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                    
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
                }
                
                // Always use the standard format
                let response = try decoder.decode(ScannerSummaryResponse.self, from: data)
                return ScannerSummaryWithStatus(
                    totalFiltered: response.data.totalFiltered,
                    priceRange: response.data.priceRange,
                    maxFloat: response.data.maxFloat,
                    topMovers: response.data.topMovers,
                    mostActive: response.data.mostActive,
                    status: ProcessingStatus(
                        phase: "complete",
                        message: "Summary loaded",
                        isProcessing: false,
                        progress: nil,
                        lastUpdate: Date()
                    ),
                    marketStatus: response.data.marketStatus
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    
                    // Remove from active requests
                    self.requestQueue.async(flags: .barrier) {
                        self.activeSummaryRequests.remove(requestId)
                    }
                    
                    if case .failure(let error) = completion {
                        // Don't show summary errors if we're suppressing errors
                        if !self.shouldSuppressError() {
                            print("Error loading scanner summary: \(error)")
                        }
                    }
                },
                receiveValue: { [weak self] summaryWithStatus in
                    guard let self = self else { return }
                    
                    // Remove from active requests
                    self.requestQueue.async(flags: .barrier) {
                        self.activeSummaryRequests.remove(requestId)
                    }
                    self.scannerSummary = ScannerSummary(
                        totalFiltered: summaryWithStatus.totalFiltered,
                        priceRange: summaryWithStatus.priceRange,
                        maxFloat: summaryWithStatus.maxFloat,
                        topMovers: summaryWithStatus.topMovers,
                        mostActive: summaryWithStatus.mostActive,
                        marketStatus: summaryWithStatus.marketStatus
                    )
                    self.processingStatus = summaryWithStatus.status
                    self.lastUpdate = Date()
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshScanner() {
        // Clear any existing error suppression when user manually refreshes
        suppressErrorsUntil = nil
        errorMessage = nil
        
        // Load current data with debouncing
        loadFilteredStocks()
        
        // Load summary separately (not debounced since it's lightweight)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.loadScannerSummary()
        }
        
        // If connected to Socket.IO, trigger a gap scan
        if isConnected {
            startGapScan()
        }
    }
    
    private func startPollingForUpdates() {
        // Poll for updates every 5 seconds for 2 minutes after refresh
        var pollCount = 0
        let maxPolls = 24 // 2 minutes at 5-second intervals
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            pollCount += 1
            
            self?.loadFilteredStocks()
            
            // Stop polling if we have data or reached max polls
            if pollCount >= maxPolls || (self?.filteredStocks.count ?? 0) > 0 {
                timer.invalidate()
            }
        }
    }
    
    // MARK: - SSE Methods
    
    private func setupSSE() {
        // Connect to SSE service
        sseService.connect()
        
        // Subscribe to the scanner room for updates
        sseService.subscribe(rooms: ["scanner"])
        
        // Listen for SSE scanner updates
        sseService.scannerUpdates
            .sink { [weak self] gappers in
                guard let self = self else { return }
                
                // Convert SSE gapper format to FilteredStock format
                let stocks = gappers.compactMap { gapper -> FilteredStock? in
                    // Calculate previous close from current price and change percent
                    let previousClose = gapper.price / (1 + gapper.change_percent / 100)
                    
                    return FilteredStock(
                        symbol: gapper.symbol,
                        name: gapper.symbol, // Name not provided in SSE
                        exchange: "NASDAQ", // Default exchange
                        previousClose: previousClose,
                        previousVolume: 0, // Not provided in SSE
                        previousVWAP: nil,
                        float: gapper.float.map(Double.init),
                        currentPrice: gapper.price,
                        currentVolume: gapper.volume,
                        bid: nil,
                        ask: nil,
                        lastUpdate: Date()
                    )
                }
                
                // Update filtered stocks if we have data
                if !stocks.isEmpty {
                    self.filteredStocks = stocks
                    self.lastUpdate = Date()
                }
            }
            .store(in: &cancellables)
        
        // Listen for price updates
        sseService.priceUpdatePublisher
            .sink { [weak self] update in
                guard let self = self else { return }
                
                // Update price for specific stock
                if let index = self.filteredStocks.firstIndex(where: { $0.symbol == update.symbol }) {
                    var updatedStock = self.filteredStocks[index]
                    updatedStock.currentPrice = update.price
                    if let volume = update.volume {
                        updatedStock.currentVolume = volume
                    }
                    updatedStock.lastUpdate = update.timestamp
                    self.filteredStocks[index] = updatedStock
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Socket.IO Methods
    
    private func setupSocketIO() {
        // Try SSE first (Cloud Run compatible), fallback to Socket.IO
        sseService.$connectionStatus
            .map { status in status.isConnected }
            .combineLatest(socketManager.$isConnected)
            .map { sseConnected, socketConnected in
                // Connected if either SSE or Socket.IO is connected
                return sseConnected || socketConnected
            }
            .assign(to: &$isConnected)
        
        // Subscribe to scan events
        socketManager.scanStatusPublisher
            .sink { [weak self] data in
                self?.handleScanStatus(data)
            }
            .store(in: &cancellables)
        
        socketManager.scanProgressPublisher
            .sink { [weak self] data in
                self?.handleScanProgress(data)
            }
            .store(in: &cancellables)
        
        socketManager.scanCompletePublisher
            .sink { [weak self] data in
                self?.handleScanComplete(data)
            }
            .store(in: &cancellables)
        
        socketManager.scanErrorPublisher
            .sink { [weak self] data in
                self?.handleScanError(data)
            }
            .store(in: &cancellables)
        
        socketManager.priceUpdatePublisher
            .sink { [weak self] data in
                self?.handlePriceUpdate(data)
            }
            .store(in: &cancellables)
        
        socketManager.gappersUpdatePublisher
            .sink { [weak self] data in
                self?.handleGappersUpdate(data)
            }
            .store(in: &cancellables)
        
        // Connect to Socket.IO server
        socketManager.connect()
    }
    
    // Legacy WebSocket methods - no longer used
    
    private func updateStock(symbol: String, price: Double? = nil, volume: Int? = nil, bid: Double? = nil, ask: Double? = nil) {
        if let index = filteredStocks.firstIndex(where: { $0.symbol == symbol }) {
            var stock = filteredStocks[index]
            
            if let price = price {
                stock.currentPrice = price
            }
            if let volume = volume {
                stock.currentVolume = volume
            }
            if let bid = bid {
                stock.bid = bid
            }
            if let ask = ask {
                stock.ask = ask
            }
            
            stock.lastUpdate = Date()
            filteredStocks[index] = stock
        }
    }
    
    // MARK: - Socket.IO Event Handlers
    
    private func handleScanStatus(_ data: [String: Any]) {
        print("Scan status update: \(data)")
        
        if let phase = data["phase"] as? String,
           let message = data["message"] as? String,
           let isProcessing = data["isProcessing"] as? Bool {
            processingStatus = ProcessingStatus(
                phase: phase,
                message: message,
                isProcessing: isProcessing,
                progress: data["progress"] as? Int,
                lastUpdate: Date()
            )
        }
    }
    
    private func handleScanProgress(_ data: [String: Any]) {
        print("Scan progress: \(data)")
        
        if let progress = data["progress"] as? Int {
            processingStatus?.progress = progress
        }
        
        if let foundGappers = data["found_gappers"] as? Int {
            print("Found \(foundGappers) gappers so far")
        }
    }
    
    private func handleScanComplete(_ data: [String: Any]) {
        print("Scan complete: \(data)")
        
        if let gappers = data["gappers"] as? [[String: Any]] {
            // Update filtered stocks with gapper data
            filteredStocks = gappers.compactMap { dict in
                guard let symbol = dict["symbol"] as? String,
                      let price = dict["price"] as? Double else { return nil }
                
                return FilteredStock(
                    symbol: symbol,
                    name: dict["name"] as? String ?? symbol,
                    exchange: dict["exchange"] as? String ?? "UNKNOWN",
                    previousClose: dict["previous_close"] as? Double ?? price,
                    previousVolume: dict["volume"] as? Int ?? 0,
                    previousVWAP: dict["vwap"] as? Double,
                    float: dict["float"] as? Double,
                    currentPrice: price,
                    currentVolume: dict["volume"] as? Int,
                    bid: dict["bid"] as? Double,
                    ask: dict["ask"] as? Double,
                    lastUpdate: Date()
                )
            }
            lastUpdate = Date()
        }
        
        isLoading = false
    }
    
    private func handleScanError(_ data: [String: Any]) {
        print("Scan error: \(data)")
        
        if let error = data["error"] as? String {
            errorMessage = error
        }
        
        isLoading = false
    }
    
    // MARK: - Stream Methods
    
    private func setupStreamSubscriptions() {
        // Subscribe to stream progress updates
        streamService.$streamProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.streamProgress = progress
            }
            .store(in: &cancellables)
        
        // Subscribe to total stocks count
        streamService.$totalStocks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in
                self?.totalExpectedStocks = total
            }
            .store(in: &cancellables)
        
        // Subscribe to filtered stock matches
        streamService.filteredStockPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streamedStock in
                // Convert and add to filtered stocks immediately
                let filteredStock = FilteredStock(
                    symbol: streamedStock.symbol,
                    name: streamedStock.name ?? streamedStock.symbol,
                    exchange: streamedStock.exchange ?? "UNKNOWN",
                    previousClose: streamedStock.prevClose ?? 0,
                    previousVolume: 0,
                    previousVWAP: nil,
                    float: nil,
                    currentPrice: streamedStock.price ?? 0,
                    currentVolume: streamedStock.volume,
                    bid: nil,
                    ask: nil,
                    lastUpdate: Date()
                )
                
                self?.filteredStocks.append(filteredStock)
                self?.lastUpdate = Date()
            }
            .store(in: &cancellables)
        
        // Subscribe to stream completion
        streamService.streamCompletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] success in
                self?.isLoading = false
                if success {
                    self?.processingStatus = ProcessingStatus(
                        phase: "complete",
                        message: "Stream complete: \(self?.filteredStocks.count ?? 0) stocks found",
                        isProcessing: false,
                        progress: 100,
                        lastUpdate: Date()
                    )
                } else if let error = self?.streamService.lastError {
                    self?.errorMessage = error
                }
            }
            .store(in: &cancellables)
    }
    
    func loadFilteredStocksWithStream() {
        guard !streamService.isStreaming else { return }
        
        isLoading = true
        errorMessage = nil
        filteredStocks.removeAll()
        streamProgress = 0
        
        // Start streaming filtered stocks
        streamService.streamFilteredStocks(
            priceMin: 2.0,
            priceMax: 20.0,
            minGain: 10.0
        )
    }
    
    private func handlePriceUpdate(_ data: [String: Any]) {
        // Update prices for stocks in the filtered list
        if let prices = data["prices"] as? [String: [String: Any]] {
            for (symbol, priceData) in prices {
                if let index = filteredStocks.firstIndex(where: { $0.symbol == symbol }),
                   let price = priceData["price"] as? Double {
                    filteredStocks[index].currentPrice = price
                    filteredStocks[index].lastUpdate = Date()
                }
            }
        }
    }
    
    private func handleGappersUpdate(_ data: [String: Any]) {
        print("Gappers update received")
        // Could refresh the gapper list here if needed
    }
    
    // MARK: - Public Socket.IO Methods
    
    func startGapScan() {
        isLoading = true
        errorMessage = nil
        socketManager.startGapScan()
    }
    
    func cancelGapScan() {
        socketManager.cancelGapScan()
        isLoading = false
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        // Refresh summary every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadScannerSummary()
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldSuppressError() -> Bool {
        // Suppress errors if we've had successful data load within the suppression window
        if let suppressUntil = suppressErrorsUntil, Date() < suppressUntil {
            return true
        }
        
        // Also suppress if we have data and it was loaded recently (within last 5 seconds)
        if !filteredStocks.isEmpty, 
           let lastSuccess = lastSuccessfulDataTime,
           Date().timeIntervalSince(lastSuccess) < 5.0 {
            return true
        }
        
        return false
    }
    
    // MARK: - New Gapper Detection
    
    private func checkForNewGappers() {
        // NOTIFICATIONS DISABLED - was causing crashes
        return
        
        /* Original notification code commented out
        // Only proceed if notifications are enabled
        guard enableGapperNotifications else { return }
        
        // Get current top gainers that meet the minimum gap threshold
        let currentGappers = topGainers.filter { $0.changePercent >= minGapPercentForNotification }
        let currentGapperSymbols = Set(currentGappers.map { $0.symbol })
        
        // Only check for new gappers after initial load
        if hasInitialLoad {
            // Find new gappers that weren't in the previous set
            let newGapperSymbols = currentGapperSymbols.subtracting(previousGapperSymbols)
            
            // Send notification for each new gapper
            for symbol in newGapperSymbols {
                if let gapper = currentGappers.first(where: { $0.symbol == symbol }) {
                    sendGapperNotification(for: gapper)
                }
            }
        } else {
            // Mark that we've done the initial load
            hasInitialLoad = true
        }
        
        // Update the previous gapper symbols
        previousGapperSymbols = currentGapperSymbols
        */
    }
    
    // NOTIFICATIONS DISABLED - was causing crashes
    private func sendGapperNotification(for stock: FilteredStock) {
        // Disabled - was using UNUserNotificationCenter which causes crashes
        print("🚀 New Gapper (notifications disabled): \(stock.symbol) - Gap: \(String(format: "%.1f%%", stock.changePercent))")
    }
    
    // MARK: - Computed Properties
    
    var topGainers: [FilteredStock] {
        filteredStocks
            .filter { $0.changePercent > 0 }
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(10)
            .map { $0 }
    }
    
    var topLosers: [FilteredStock] {
        filteredStocks
            .filter { $0.changePercent < 0 }
            .sorted { $0.changePercent < $1.changePercent }
            .prefix(10)
            .map { $0 }
    }
    
    var mostActive: [FilteredStock] {
        filteredStocks
            .sorted { ($0.currentVolume ?? 0) > ($1.currentVolume ?? 0) }
            .prefix(10)
            .map { $0 }
    }
}