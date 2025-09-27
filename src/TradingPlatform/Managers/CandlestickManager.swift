import Foundation
import Combine
import SwiftUI
import Alamofire

class CandlestickManager: ObservableObject {
    @Published var chartData: CandlestickChartData
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentSymbol: String?
    @Published var marketStatus: MarketStatus = .closed
    
    enum MarketStatus {
        case premarket
        case open
        case afterhours
        case closed
        
        var description: String {
            switch self {
            case .premarket: return "Pre-Market (4:00 AM - 9:30 AM ET)"
            case .open: return "Market Open (9:30 AM - 4:00 PM ET)"
            case .afterhours: return "After-Hours (4:00 PM - 8:00 PM ET)"
            case .closed: return "Market Closed"
            }
        }
        
        var shouldConnectWebSocket: Bool {
            return self != .closed
        }
    }
    
    private let apiService = APIService.shared
    private let webSocketService = WebSocketService.shared
    private let socketManager = SocketIOManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    
    // Store chart data for each symbol
    private var symbolChartData: [String: CandlestickChartData] = [:]
    private var symbolSubscriptions: Set<String> = []
    private let maxTrackedSymbols = 10 // Limit to prevent memory issues
    
    init() {
        self.chartData = CandlestickChartData()
        setupWebSocketSubscriptions()
        setupSocketIOSubscriptions()
        
        // Ensure Socket.IO connection is established
        if !socketManager.isConnected {
            socketManager.connect()
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func loadCandlesticks(for symbol: String) {
        // Check if we already have data for this symbol
        if let existingData = symbolChartData[symbol] {
            // Use existing data
            self.chartData = existingData
            self.currentSymbol = symbol
            self.errorMessage = nil
            
            // If data is older than 5 minutes, refresh it
            if let lastCandle = existingData.candles.last,
               Date().timeIntervalSince(lastCandle.timestamp) > 300 {
                refreshCandlesticks(for: symbol)
            }
            return
        }
        
        // New symbol - load fresh data
        currentSymbol = symbol
        isLoading = true
        errorMessage = nil
        
        // Check if we've reached the max tracked symbols limit
        if symbolChartData.count >= maxTrackedSymbols {
            // Remove the oldest tracked symbol (first in dictionary)
            if let oldestSymbol = symbolChartData.keys.first {
                stopUpdatesForSymbol(oldestSymbol)
            }
        }
        
        // Create new chart data for this symbol
        let newChartData = CandlestickChartData()
        symbolChartData[symbol] = newChartData
        self.chartData = newChartData
        
        // Load historical candles from API
        loadHistoricalCandles(symbol: symbol)
        
        // Subscribe to real-time updates if not already subscribed
        if !symbolSubscriptions.contains(symbol) {
            subscribeToRealTimeUpdates(symbol: symbol)
            symbolSubscriptions.insert(symbol)
        }
    }
    
    private func refreshCandlesticks(for symbol: String) {
        isLoading = true
        loadHistoricalCandles(symbol: symbol)
    }
    
    func stopUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
        // Note: We intentionally don't unsubscribe from WebSocket here
        // to keep receiving updates for all tracked symbols
    }
    
    func stopUpdatesForSymbol(_ symbol: String) {
        // Remove from tracking
        symbolChartData.removeValue(forKey: symbol)
        symbolSubscriptions.remove(symbol)
        
        // Unsubscribe from Socket.IO
        socketManager.unsubscribe(symbols: [symbol], type: "candlesticks")
        
        print("Stopped updates for symbol: \(symbol)")
    }
    
    func clearAllData() {
        // Clear all tracked data
        symbolChartData.removeAll()
        symbolSubscriptions.removeAll()
        chartData = CandlestickChartData()
        currentSymbol = nil
        
        // Stop all timers
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func loadHistoricalCandles(symbol: String) {
        // Check market status first
        updateMarketStatus()
        
        // Fetch last 24 hours of 1-minute candles (or last trading day if weekend)
        let now = Date()
        let endDate = now
        let startDate = getStartDateForHistoricalData(from: now)
        
        print("Loading candlesticks for \(symbol) from \(startDate) to \(endDate)")
        print("Market status: \(marketStatus.description)")
        
        // Try Polygon API directly first
        loadPolygonHistoricalData(symbol: symbol, from: startDate, to: endDate) { [weak self] success in
            if !success {
                // Fallback to our API (which might use Alpaca)
                self?.loadFromOurAPI(symbol: symbol, from: startDate, to: endDate)
            }
        }
    }
    
    private func updateMarketStatus() {
        var calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let easternTime = TimeZone(identifier: "America/New_York")!
        calendar.timeZone = easternTime
        
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else {
            marketStatus = .closed
            return
        }
        
        // Check if weekend (Saturday = 7, Sunday = 1)
        if weekday == 1 || weekday == 7 {
            marketStatus = .closed
            return
        }
        
        let totalMinutes = hour * 60 + minute
        
        // Pre-market: 4:00 AM - 9:30 AM ET (240 - 570 minutes)
        if totalMinutes >= 240 && totalMinutes < 570 {
            marketStatus = .premarket
        }
        // Regular hours: 9:30 AM - 4:00 PM ET (570 - 960 minutes)
        else if totalMinutes >= 570 && totalMinutes < 960 {
            marketStatus = .open
        }
        // After-hours: 4:00 PM - 8:00 PM ET (960 - 1200 minutes)
        else if totalMinutes >= 960 && totalMinutes < 1200 {
            marketStatus = .afterhours
        }
        // Closed
        else {
            marketStatus = .closed
        }
    }
    
    private func getStartDateForHistoricalData(from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        let easternTime = TimeZone(identifier: "America/New_York")!
        calendar.timeZone = easternTime
        
        let components = calendar.dateComponents([.weekday], from: date)
        
        // If it's weekend, go back to Friday
        if let weekday = components.weekday {
            if weekday == 1 { // Sunday
                return date.addingTimeInterval(-2 * 24 * 60 * 60) // Go back to Friday
            } else if weekday == 7 { // Saturday
                return date.addingTimeInterval(-1 * 24 * 60 * 60) // Go back to Friday
            }
        }
        
        // Otherwise, just go back 24 hours
        return date.addingTimeInterval(-24 * 60 * 60)
    }
    
    private func loadPolygonHistoricalData(symbol: String, from startDate: Date, to endDate: Date, completion: @escaping (Bool) -> Void) {
        let apiKey = AppConfiguration.polygonAPIKey
        let fromTimestamp = Int(startDate.timeIntervalSince1970 * 1000)
        let toTimestamp = Int(endDate.timeIntervalSince1970 * 1000)
        
        // Polygon REST API endpoint for aggregates (candlesticks)
        let urlString = "https://api.polygon.io/v2/aggs/ticker/\(symbol)/range/1/minute/\(fromTimestamp)/\(toTimestamp)?adjusted=true&sort=asc&limit=50000&apiKey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid Polygon URL")
            completion(false)
            return
        }
        
        print("Fetching from Polygon: \(urlString)")
        
        AF.request(url)
            .validate()
            .responseDecodable(of: PolygonAggregatesResponse.self) { [weak self] response in
                switch response.result {
                case .success(let polygonResponse):
                    if polygonResponse.status == "OK", let results = polygonResponse.results, !results.isEmpty {
                        print("Polygon API: Loaded \(results.count) candles for \(symbol)")
                        
                        // Convert Polygon results to our Candle format
                        let candles = results.map { result in
                            Candle(
                                timestamp: Date(timeIntervalSince1970: Double(result.t) / 1000),
                                open: result.o,
                                high: result.h,
                                low: result.l,
                                close: result.c,
                                volume: result.v
                            )
                        }
                        
                        DispatchQueue.main.async {
                            // Update chart data
                            if let chartData = self?.symbolChartData[symbol] {
                                chartData.addHistoricalCandles(candles)
                                
                                if symbol == self?.currentSymbol {
                                    self?.chartData = chartData
                                }
                            }
                            
                            self?.isLoading = false
                            self?.errorMessage = nil
                        }
                        
                        completion(true)
                    } else {
                        print("Polygon API: No data or limited data for \(symbol)")
                        print("Response status: \(polygonResponse.status)")
                        print("Results count: \(polygonResponse.results?.count ?? 0)")
                        
                        // Try with a longer timeframe (5 days)
                        self?.tryLongerTimeframe(symbol: symbol, originalStart: startDate, originalEnd: endDate, completion: completion)
                    }
                    
                case .failure(let error):
                    print("Polygon API error: \(error)")
                    
                    // Check if it's a 404 or other specific error
                    if let httpResponse = response.response {
                        print("HTTP Status Code: \(httpResponse.statusCode)")
                    }
                    
                    completion(false)
                }
            }
    }
    
    private func tryLongerTimeframe(symbol: String, originalStart: Date, originalEnd: Date, completion: @escaping (Bool) -> Void) {
        print("Trying longer timeframe for \(symbol) (5 days)")
        
        // Try 5 days of data with 5-minute bars
        let extendedStart = originalEnd.addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let apiKey = AppConfiguration.polygonAPIKey
        let fromTimestamp = Int(extendedStart.timeIntervalSince1970 * 1000)
        let toTimestamp = Int(originalEnd.timeIntervalSince1970 * 1000)
        
        // Use 5-minute bars for stocks with limited data
        let urlString = "https://api.polygon.io/v2/aggs/ticker/\(symbol)/range/5/minute/\(fromTimestamp)/\(toTimestamp)?adjusted=true&sort=asc&limit=50000&apiKey=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }
        
        AF.request(url)
            .validate()
            .responseDecodable(of: PolygonAggregatesResponse.self) { [weak self] response in
                switch response.result {
                case .success(let polygonResponse):
                    if let results = polygonResponse.results, !results.isEmpty {
                        print("Extended timeframe: Loaded \(results.count) 5-minute candles for \(symbol)")
                        
                        let candles = results.map { result in
                            Candle(
                                timestamp: Date(timeIntervalSince1970: Double(result.t) / 1000),
                                open: result.o,
                                high: result.h,
                                low: result.l,
                                close: result.c,
                                volume: result.v
                            )
                        }
                        
                        DispatchQueue.main.async {
                            if let chartData = self?.symbolChartData[symbol] {
                                chartData.addHistoricalCandles(candles)
                                
                                if symbol == self?.currentSymbol {
                                    self?.chartData = chartData
                                }
                            }
                            
                            self?.isLoading = false
                            self?.errorMessage = nil
                        }
                        
                        completion(true)
                    } else {
                        print("No data available even with extended timeframe for \(symbol)")
                        
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            self?.errorMessage = "Limited trading data available for \(symbol)"
                        }
                        
                        completion(false)
                    }
                    
                case .failure(let error):
                    print("Extended timeframe error: \(error)")
                    completion(false)
                }
            }
    }
    
    private func loadFromOurAPI(symbol: String, from startDate: Date, to endDate: Date) {
        // Try our API endpoint (fallback)
        apiService.getCandlesticks(
            symbol: symbol,
            timeframe: "1Min",
            from: startDate,
            to: endDate
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    print("Our API error: \(error)")
                    // Try Alpaca as last resort
                    self?.loadAlpacaHistoricalData(symbol: symbol, from: startDate, to: endDate)
                }
            },
            receiveValue: { [weak self] candles in
                guard let self = self else { return }
                print("Our API: Loaded \(candles.count) historical candles for \(symbol)")
                
                // Update the correct chart data for this symbol
                if let chartData = self.symbolChartData[symbol] {
                    chartData.addHistoricalCandles(candles)
                    
                    if symbol == self.currentSymbol {
                        self.chartData = chartData
                    }
                }
                
                self.errorMessage = nil
                
                // After loading historical data, connect to WebSocket for real-time updates
                if !self.symbolSubscriptions.contains(symbol) {
                    self.connectToWebSocket(symbol: symbol)
                    self.symbolSubscriptions.insert(symbol)
                }
            }
        )
        .store(in: &cancellables)
    }
    
    private func loadAlpacaHistoricalData(symbol: String, from startDate: Date, to endDate: Date) {
        // We'll need to get Alpaca credentials from our API first
        print("Attempting to load from Alpaca...")
        
        // For now, just set an error message
        self.errorMessage = "Unable to load historical data. Please check your connection."
        
        // Still connect to WebSocket for potential real-time updates
        if !self.symbolSubscriptions.contains(symbol) {
            self.connectToWebSocket(symbol: symbol)
            self.symbolSubscriptions.insert(symbol)
        }
    }
    
    private func subscribeToRealTimeUpdates(symbol: String) {
        // Only connect to WebSocket if market is open (including extended hours)
        guard marketStatus.shouldConnectWebSocket else {
            print("Market closed - skipping WebSocket connection")
            return
        }
        
        // Subscribe via Socket.IO to receive Polygon data from API (backup)
        socketManager.subscribe(symbols: [symbol], type: "candlesticks")
        
        // Real-time data now comes through SSE from the API
        // No need for direct Polygon WebSocket connection
        
        // Start per-second update timer for UI updates
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processSecondAggregation()
        }
    }
    
    private func setupWebSocketSubscriptions() {
        // Listen to price updates from the existing WebSocketService
        webSocketService.priceUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] priceUpdates in
                guard let symbol = self?.currentSymbol,
                      let price = priceUpdates[symbol] else { return }
                
                // Update current price in chart data
                self?.chartData.currentPrice = price
                
                // Create or update current minute candle
                let now = Date()
                let trade = TradeUpdate(
                    symbol: symbol,
                    price: price,
                    size: 100, // Default size
                    timestamp: now
                )
                self?.chartData.updateFromTrade(trade)
            }
            .store(in: &cancellables)
        
        // Real-time updates now come through WebSocketService and SSE from the API
        // The API handles all Polygon connections on the backend
    }
    
    private func setupSocketIOSubscriptions() {
        // Listen for candlestick updates from API (which gets data from Polygon)
        socketManager.on("candlestick:update") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let symbol = dict["symbol"] as? String,
                  let candleData = dict["candle"] as? [String: Any] else { return }
            
            // Only process updates for symbols we're tracking
            guard let chartData = self.symbolChartData[symbol] else { return }
            
            // Create candle from update
            let candle = Candle(
                timestamp: Date(timeIntervalSince1970: Double(candleData["timestamp"] as? Int ?? 0) / 1000),
                open: candleData["open"] as? Double ?? 0,
                high: candleData["high"] as? Double ?? 0,
                low: candleData["low"] as? Double ?? 0,
                close: candleData["close"] as? Double ?? 0,
                volume: candleData["volume"] as? Int ?? 0
            )
            
            DispatchQueue.main.async {
                // Check if this is a new minute candle
                let isNewCandle = !chartData.candles.contains { existingCandle in
                    abs(existingCandle.timestamp.timeIntervalSince(candle.timestamp)) < 30
                }
                
                if isNewCandle {
                    // Add new candle with animation trigger
                    chartData.candles.append(candle)
                    chartData.candles.sort { $0.timestamp < $1.timestamp }
                } else {
                    // Update existing candle
                    chartData.updateCurrentCandle(candle)
                }
                
                // If this is the current symbol, update published data
                if symbol == self.currentSymbol {
                    self.chartData = chartData
                    self.objectWillChange.send()
                }
            }
        }
        
        // Listen for complete candles
        socketManager.on("candlestick:complete") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let symbol = dict["symbol"] as? String,
                  let candleData = dict["candle"] as? [String: Any] else { return }
            
            // Only process updates for symbols we're tracking
            guard let chartData = self.symbolChartData[symbol] else { return }
            
            let candle = Candle(
                timestamp: Date(timeIntervalSince1970: Double(candleData["timestamp"] as? Int ?? 0) / 1000),
                open: candleData["open"] as? Double ?? 0,
                high: candleData["high"] as? Double ?? 0,
                low: candleData["low"] as? Double ?? 0,
                close: candleData["close"] as? Double ?? 0,
                volume: candleData["volume"] as? Int ?? 0
            )
            
            DispatchQueue.main.async {
                // Add complete candle to history
                var candles = chartData.candles
                
                // Replace or add the candle
                if let index = candles.firstIndex(where: { 
                    abs($0.timestamp.timeIntervalSince(candle.timestamp)) < 30 
                }) {
                    candles[index] = candle
                } else {
                    candles.append(candle)
                    candles.sort { $0.timestamp < $1.timestamp }
                }
                
                chartData.candles = candles
                
                // If this is the current symbol, update published data
                if symbol == self.currentSymbol {
                    self.chartData = chartData
                    self.objectWillChange.send()
                }
            }
        }
        
        // Listen for trade updates
        socketManager.on("trade:update") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let symbol = dict["symbol"] as? String,
                  let price = dict["price"] as? Double else { return }
            
            // Update current price for tracked symbols
            if let chartData = self.symbolChartData[symbol] {
                DispatchQueue.main.async {
                    chartData.currentPrice = price
                    
                    if symbol == self.currentSymbol {
                        self.chartData = chartData
                        self.objectWillChange.send()
                    }
                }
            }
        }
        
        // Listen for quote updates
        socketManager.on("quote:update") { [weak self] data, _ in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let symbol = dict["symbol"] as? String,
                  let bid = dict["bid"] as? Double,
                  let ask = dict["ask"] as? Double else { return }
            
            // Update bid/ask for tracked symbols
            if let chartData = self.symbolChartData[symbol] {
                DispatchQueue.main.async {
                    chartData.bid = bid
                    chartData.ask = ask
                    chartData.spread = ask - bid
                    
                    if symbol == self.currentSymbol {
                        self.chartData = chartData
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    private func processSecondAggregation() {
        // This method would aggregate per-second data into the current minute candle
        // The actual aggregation happens in chartData.updateFromTrade/Quote/Aggregate
        // This timer ensures UI updates happen smoothly
        objectWillChange.send()
    }
    
    private func connectToWebSocket(symbol: String) {
        // Ensure Socket.IO is connected first
        if !socketManager.isConnected {
            socketManager.connect()
            
            // Wait a moment for connection to establish, then subscribe
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if self?.socketManager.isConnected == true {
                    self?.socketManager.subscribe(symbols: [symbol], type: "candlesticks")
                    print("Subscribed to real-time candlestick updates for: \(symbol)")
                } else {
                    print("Failed to connect to Socket.IO for candlestick updates")
                }
            }
        } else {
            // Already connected, subscribe immediately
            socketManager.subscribe(symbols: [symbol], type: "candlesticks")
            print("Subscribed to real-time candlestick updates for: \(symbol)")
        }
    }
    
}

// MARK: - Polygon Response Models

struct PolygonAggregatesResponse: Codable {
    let status: String
    let results: [PolygonAggregate]?
    let resultsCount: Int?
    let ticker: String?
    let queryCount: Int?
    let adjusted: Bool?
    
    enum CodingKeys: String, CodingKey {
        case status, results, ticker, adjusted
        case resultsCount = "resultsCount"
        case queryCount = "queryCount"
    }
}

struct PolygonAggregate: Codable {
    let v: Int    // Volume
    let vw: Double? // Volume weighted average price
    let o: Double  // Open
    let c: Double  // Close
    let h: Double  // High
    let l: Double  // Low
    let t: Int64   // Unix millisecond timestamp
    let n: Int?    // Number of transactions
}

// API Service extension removed - method is now in APIService directly

// Response model for API
struct CandlestickResponse: Codable {
    let success: Bool
    let candles: [CandleAPIData]
}

struct CandleAPIData: Codable {
    let timestamp: Int // milliseconds
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}