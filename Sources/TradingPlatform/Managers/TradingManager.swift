import Foundation
import Combine
import UserNotifications

class TradingManager: ObservableObject {
    @Published var positions: [Position] = []
    @Published var portfolioSummary: PortfolioSummary?
    @Published var performanceData: [PerformanceData] = []
    @Published var watchlist: [Stock] = []  // Will contain ONLY gappers
    @Published var recentOrders: [Order] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Real-time price updates
    @Published var currentPrices: [String: Double] = [:]
    
    private let apiService = APIService.shared
    private let webSocketService = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    init() {
        setupWebSocketSubscriptions()
        startPeriodicRefresh()
        requestNotificationPermission()
        // Load gappers immediately
        loadGappers()
    }
    
    private func requestNotificationPermission() {
        // Only request notifications if running as a proper app bundle
        // Skip when running via 'swift run' to prevent crashes
        guard Bundle.main.bundleIdentifier != nil else {
            print("Running in development mode - notifications disabled")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    // MARK: - Initial Data Loading
    func loadInitialData() {
        loadPositions()
        loadPortfolioSummary()
        loadPerformanceData()
        loadGappers()  // Load gappers, NOT all stocks
    }
    
    // MARK: - WebSocket Subscriptions
    private func setupWebSocketSubscriptions() {
        
        // Subscribe to real-time position updates
        webSocketService.positionUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedPositions in
                self?.positions = updatedPositions
                self?.updatePortfolioSummary()
            }
            .store(in: &cancellables)
        
        // Subscribe to real-time price updates for GAPPERS ONLY
        webSocketService.priceUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] priceUpdates in
                self?.currentPrices.merge(priceUpdates) { _, new in new }
                self?.updatePositionsWithCurrentPrices()
            }
            .store(in: &cancellables)
        
        // Subscribe to real-time gapper updates via WebSocket
        SocketIOManager.shared.gappersUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gappersData in
                guard let self = self else { return }
                
                // Parse gappers from WebSocket update
                if let gappers = gappersData["gappers"] as? [[String: Any]] {
                    print("Received \(gappers.count) gappers via WebSocket")
                    
                    // Convert to Stock objects
                    let stocks = gappers.compactMap { gapperDict -> Stock? in
                        guard let ticker = gapperDict["ticker"] as? String ?? gapperDict["symbol"] as? String,
                              let price = gapperDict["price"] as? Double,
                              let gapPercent = gapperDict["gap_percent"] as? Double ?? gapperDict["gapPercent"] as? Double,
                              let prevClose = gapperDict["prev_close"] as? Double ?? gapperDict["prevClose"] as? Double else {
                            return nil
                        }
                        
                        let name = gapperDict["name"] as? String
                        let changeAmount = price - prevClose
                        
                        return Stock(
                            symbol: ticker,
                            name: name ?? ticker,
                            price: price,
                            changePercent: gapPercent,
                            changeAmount: changeAmount
                        )
                    }
                    
                    // Check for new gappers before updating
                    let previousSymbols = Set(self.watchlist.map { $0.symbol })
                    let newStocks = stocks.filter { !previousSymbols.contains($0.symbol) }
                    
                    // Update watchlist with WebSocket data (already sorted by gap %)
                    self.watchlist = stocks.sorted { $0.changePercent ?? 0 > $1.changePercent ?? 0 }
                    print("Updated watchlist with \(self.watchlist.count) gappers from WebSocket")
                    
                    // Send notification for new gappers
                    if !newStocks.isEmpty {
                        self.sendNewGapperNotification(newStocks)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading Methods
    func loadPositions() {
        apiService.getPositions()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load positions: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] positions in
                    self?.positions = positions
                    self?.updatePortfolioSummary()
                    self?.errorMessage = nil
                }
            )
            .store(in: &cancellables)
    }
    
    
    private func loadPortfolioSummary() {
        // Calculate portfolio summary from positions
        updatePortfolioSummary()
    }
    
    func loadPerformanceData() {
        // Load performance data from API
        // For now, keeping empty until API endpoint is ready
        performanceData = []
    }
    
    // MARK: - Trading Actions
    func executeTrade(symbol: String, side: String, quantity: Double) {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        apiService.executeTrade(symbol: symbol, side: side, quantity: quantity)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to execute trade: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    print("Trade executed successfully: \(response)")
                    // Refresh positions after successful trade
                    self?.loadPositions()
                    self?.errorMessage = nil
                }
            )
            .store(in: &cancellables)
    }
    
    func closePosition(_ position: Position) {
        let oppositeSide = position.side == "long" ? "sell" : "buy"
        executeTrade(symbol: position.symbol, side: oppositeSide, quantity: abs(position.quantity))
    }
    
    // MARK: - Market Data
    func getCandlestickData(for symbol: String, timeframe: String = "5Min") -> AnyPublisher<[CandlestickData], Never> {
        return apiService.getCandlestickData(symbol: symbol, timeframe: timeframe)
            .catch { error -> Just<[CandlestickData]> in
                print("Failed to load candlestick data: \(error)")
                return Just([])
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helper Methods
    private func updatePortfolioSummary() {
        let totalValue = positions.reduce(0) { $0 + $1.totalValue }
        let totalPnL = positions.reduce(0) { $0 + $1.unrealizedPnL }
        let totalCost = positions.reduce(0) { $0 + ($1.quantity * $1.entryPrice) }
        let totalPnLPercent = totalCost > 0 ? (totalPnL / totalCost) * 100 : 0
        
        portfolioSummary = PortfolioSummary(
            totalValue: totalValue,
            dailyPnL: totalPnL, // This would be calculated differently in a real app
            dailyPnLPercent: totalPnLPercent,
            totalPnL: totalPnL,
            totalPnLPercent: totalPnLPercent,
            buyingPower: 100000, // This would come from the API
            cash: 50000, // This would come from the API
            positionsCount: positions.count
        )
    }
    
    private func updatePositionsWithCurrentPrices() {
        positions = positions.map { position in
            var updatedPosition = position
            if let currentPrice = currentPrices[position.symbol] {
                updatedPosition.currentPrice = currentPrice
            }
            return updatedPosition
        }
    }
    
    // MARK: - Periodic Refresh
    private func startPeriodicRefresh() {
        // Refresh gappers every 30 seconds during market hours
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }
    
    private func refreshData() {
        // Refresh gappers and positions
        loadGappers()
        
        // Only refresh positions if we have any
        if !positions.isEmpty {
            loadPositions()
        }
    }
    
    // MARK: - Computed Properties
    var totalPortfolioValue: Double {
        return portfolioSummary?.totalValue ?? 0
    }
    
    var totalUnrealizedPnL: Double {
        return portfolioSummary?.totalPnL ?? 0
    }
    
    var totalUnrealizedPnLPercent: Double {
        return portfolioSummary?.totalPnLPercent ?? 0
    }
    
    
    var profitablePositions: [Position] {
        return positions.filter { $0.isProfit }
    }
    
    var losingPositions: [Position] {
        return positions.filter { !$0.isProfit }
    }
    
    // MARK: - GAPPERS ONLY - No All Stocks Streaming!
    func loadGappers() {
        loadWatchlist()
    }
    
    func loadWatchlist() {
        // ONLY load gappers from the API - NO streaming all stocks!
        
        // Temporary: Use direct Cloud Run URL until DNS is updated
        guard let url = URL(string: "https://relentless-market-api-1008761209426.us-east1.run.app/gappers") else {
            print("Invalid gappers URL")
            return
        }
        
        isLoading = true
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Failed to load gappers: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let gapperResponse = try JSONDecoder().decode(GapperResponse.self, from: data)
                    
                    // Convert gappers to Stock format
                    let stocks = gapperResponse.gappers
                        .sorted { $0.gapPercent > $1.gapPercent }  // Sort by gap % descending
                        .map { gapper in
                            Stock(
                                symbol: gapper.ticker,
                                name: gapper.name ?? gapper.ticker,
                                price: gapper.price,
                                changePercent: gapper.gapPercent,
                                changeAmount: gapper.price - gapper.prevClose
                            )
                        }
                    // Check for new gappers before updating
                    let previousSymbols = Set(self?.watchlist.map { $0.symbol } ?? [])
                    let newStocks = stocks.filter { !previousSymbols.contains($0.symbol) }
                    
                    self?.watchlist = stocks
                    self?.errorMessage = nil
                    
                    print("Loaded \(stocks.count) gappers (sorted by gap %)")
                    
                    // Send notification for new gappers (only if we had previous data)
                    if !previousSymbols.isEmpty && !newStocks.isEmpty {
                        self?.sendNewGapperNotification(newStocks)
                    }
                    
                } catch {
                    self?.errorMessage = "Failed to decode gappers: \(error.localizedDescription)"
                    
                    // If API is not available, show empty list (NOT sample data!)
                    self?.watchlist = []
                }
            }
        }.resume()
    }
    
    // MARK: - Trading Methods
    func placeMarketOrder(symbol: String, side: String, quantity: Int) async throws {
        // Implementation for market order
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Create order
        let order = Order(
            id: UUID().uuidString,
            symbol: symbol,
            side: side,
            quantity: quantity,  // Already an Int
            type: "market",
            status: "filled",
            price: currentPrices[symbol] ?? 0,  // Use 'price' instead of 'filledPrice'
            stopPrice: nil,
            filledAt: Date()  // Use 'filledAt' instead of 'timestamp'
        )
        
        await MainActor.run {
            self.recentOrders.insert(order, at: 0)
            if self.recentOrders.count > 10 {
                self.recentOrders.removeLast()
            }
            
            // Refresh positions
            self.loadPositions()
        }
    }
    
    func placeLimitOrder(symbol: String, side: String, quantity: Int, limitPrice: Double) async throws {
        // Implementation for limit order
        print("Placing limit order: \(symbol) \(side) \(quantity) @ $\(limitPrice)")
    }
    
    func placeStopOrder(symbol: String, side: String, quantity: Int, stopPrice: Double) async throws {
        // Implementation for stop order
        print("Placing stop order: \(symbol) \(side) \(quantity) @ $\(stopPrice)")
    }
    
    func placeStopLimitOrder(symbol: String, side: String, quantity: Int, stopPrice: Double, limitPrice: Double) async throws {
        // Implementation for stop limit order
        print("Placing stop limit order: \(symbol) \(side) \(quantity) stop @ $\(stopPrice) limit @ $\(limitPrice)")
    }
    
    // MARK: - Notifications
    private func sendNewGapperNotification(_ newGappers: [Stock]) {
        // Only send notifications if running as a proper app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Dev mode: Would send notification for \(newGappers.count) new gapper(s)")
            return
        }
        
        let content = UNMutableNotificationContent()
        
        if newGappers.count == 1, let gapper = newGappers.first {
            // Single gapper notification
            content.title = "New Gapper Alert! 🚀"
            content.body = "\(gapper.symbol): +\(String(format: "%.1f", gapper.changePercent ?? 0))% @ $\(String(format: "%.2f", gapper.price ?? 0))"
            content.sound = .default
        } else {
            // Multiple gappers notification
            content.title = "\(newGappers.count) New Gappers Found! 🚀"
            let topGapper = newGappers.max(by: { ($0.changePercent ?? 0) < ($1.changePercent ?? 0) })
            if let topGapper = topGapper {
                content.body = "Top: \(topGapper.symbol) +\(String(format: "%.1f", topGapper.changePercent ?? 0))%"
            } else {
                content.body = "Check the app for details"
            }
            content.sound = .default
            content.badge = NSNumber(value: newGappers.count)
        }
        
        // Create a unique identifier for this notification
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        // Send the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            } else {
                print("Notification sent for \(newGappers.count) new gapper(s)")
            }
        }
    }
}

// MARK: - Response Models
struct GapperResponse: Codable {
    let success: Bool
    let count: Int
    let gappers: [Gapper]
    let lastScan: String?
    let dataMode: String?
    
    enum CodingKeys: String, CodingKey {
        case success, count, gappers
        case lastScan = "last_scan"
        case dataMode = "data_mode"
    }
}

struct Gapper: Codable {
    let ticker: String
    let name: String?
    let price: Double
    let prevClose: Double
    let gapPercent: Double
    let volume: Double
    let avgVolume30d: Double?
    let relativeVolume: Double
    let floatShares: Double?
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case ticker, name, price, volume, timestamp
        case prevClose = "prev_close"
        case gapPercent = "gap_percent"
        case avgVolume30d = "avg_volume_30d"
        case relativeVolume = "relative_volume"
        case floatShares = "float_shares"
    }
}

// Update Stock model to include gapper-specific fields
