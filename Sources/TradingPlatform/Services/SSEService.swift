import Foundation
import Combine

/// Service for handling Server-Sent Events (SSE) as an alternative to WebSockets
/// This is more compatible with Cloud Run's infrastructure
class SSEService: ObservableObject {
    static let shared = SSEService()
    
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastError: String?
    @Published var scannerData: [GapperStock] = []
    @Published var priceUpdates: [String: Double] = [:]
    
    enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting..."
        case connected = "Connected"
        case error = "Error"
        
        var isConnected: Bool {
            return self == .connected
        }
    }
    
    private var eventSource: URLSessionDataTask?
    private var session: URLSession?
    private var connectionId: String?
    private var subscribedSymbols = Set<String>()
    private var subscribedRooms = Set<String>()
    private let baseURL: String
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    // Publishers for different event types
    let scannerUpdates = PassthroughSubject<[GapperStock], Never>()
    let priceUpdatePublisher = PassthroughSubject<PriceUpdate, Never>()
    let marketStatusPublisher = PassthroughSubject<MarketStatus, Never>()
    
    struct PriceUpdate {
        let symbol: String
        let price: Double
        let volume: Int?
        let timestamp: Date
    }
    
    struct MarketStatus {
        let status: String
        let timestamp: Date
    }
    
    private init() {
        // Always use production API for now since SSE needs to be deployed
        self.baseURL = "https://api.relentless.market/api/sse"
        
        // Configure URLSession for SSE
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }
    
    // MARK: - Public Methods
    
    func connect() {
        guard connectionStatus != .connected && connectionStatus != .connecting else {
            print("SSE: Already connected or connecting")
            return
        }
        
        connectionStatus = .connecting
        lastError = nil
        
        guard let url = URL(string: "\(baseURL)/stream") else {
            handleError("Invalid SSE URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 300
        
        print("SSE: Connecting to \(url)")
        
        // Set up stream handler directly (don't create two tasks)
        setupStreamHandler()
    }
    
    func disconnect() {
        eventSource?.cancel()
        eventSource = nil
        connectionId = nil
        connectionStatus = .disconnected
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        print("SSE: Disconnected")
    }
    
    func subscribe(symbols: [String]? = nil, rooms: [String]? = nil) {
        guard let connectionId = connectionId else {
            print("SSE: No connection ID available")
            return
        }
        
        if let symbols = symbols {
            subscribedSymbols.formUnion(symbols)
        }
        if let rooms = rooms {
            subscribedRooms.formUnion(rooms)
        }
        
        // Send subscription request
        Task {
            await sendSubscriptionRequest(
                connectionId: connectionId,
                symbols: symbols,
                rooms: rooms,
                isSubscribe: true
            )
        }
    }
    
    func unsubscribe(symbols: [String]? = nil, rooms: [String]? = nil) {
        guard let connectionId = connectionId else {
            print("SSE: No connection ID available")
            return
        }
        
        if let symbols = symbols {
            subscribedSymbols.subtract(symbols)
        }
        if let rooms = rooms {
            subscribedRooms.subtract(rooms)
        }
        
        // Send unsubscription request
        Task {
            await sendSubscriptionRequest(
                connectionId: connectionId,
                symbols: symbols,
                rooms: rooms,
                isSubscribe: false
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func setupStreamHandler() {
        // Use URLSession streaming to handle SSE
        guard let url = URL(string: "\(baseURL)/stream") else { 
            handleError("Invalid SSE URL")
            return 
        }
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 300
        
        // Use URLSession delegate to handle streaming data
        let streamDelegate = SSEStreamDelegate { [weak self] event, data in
            self?.handleSSEEvent(event: event, data: data)
        }
        
        let streamConfig = URLSessionConfiguration.default
        streamConfig.timeoutIntervalForRequest = 300
        streamConfig.timeoutIntervalForResource = 300
        streamConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let streamSession = URLSession(
            configuration: streamConfig,
            delegate: streamDelegate,
            delegateQueue: .main
        )
        
        eventSource = streamSession.dataTask(with: request)
        eventSource?.resume()
        
        // Connection will be established via delegate callbacks
        print("SSE: Stream handler started")
    }
    
    private func handleSSEEvent(event: String?, data: String?) {
        guard let data = data else { return }
        
        // Handle different event types
        switch event {
        case "connected":
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let connId = json["connectionId"] as? String {
                self.connectionId = connId
                connectionStatus = .connected
                print("SSE: Connected with ID: \(connId)")
                
                // Re-subscribe to previous subscriptions
                if !subscribedSymbols.isEmpty || !subscribedRooms.isEmpty {
                    subscribe(
                        symbols: Array(subscribedSymbols),
                        rooms: Array(subscribedRooms)
                    )
                }
            }
            
        case "scanner:initial", "gappers:update":
            handleScannerUpdate(data: data)
            
        case "price:update":
            handlePriceUpdate(data: data)
            
        case "market:status":
            handleMarketStatus(data: data)
            
        default:
            break
        }
    }
    
    private func handleScannerUpdate(data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let stocks = json["stocks"] as? [[String: Any]] ?? json["gappers"] as? [[String: Any]] {
                    let gappers = stocks.compactMap { stockData -> GapperStock? in
                        guard let symbol = stockData["symbol"] as? String,
                              let price = stockData["price"] as? Double,
                              let changePercent = stockData["change_percent"] as? Double else {
                            return nil
                        }
                        
                        return GapperStock(
                            symbol: symbol,
                            price: price,
                            change_percent: changePercent,
                            volume: stockData["volume"] as? Int ?? 0,
                            float: stockData["float"] as? Int
                        )
                    }
                    
                    DispatchQueue.main.async {
                        self.scannerData = gappers
                        self.scannerUpdates.send(gappers)
                    }
                }
            }
        } catch {
            print("SSE: Error parsing scanner data: \(error)")
        }
    }
    
    private func handlePriceUpdate(data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let symbol = json["symbol"] as? String,
               let price = json["price"] as? Double {
                
                let update = PriceUpdate(
                    symbol: symbol,
                    price: price,
                    volume: json["volume"] as? Int,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.priceUpdates[symbol] = price
                    self.priceUpdatePublisher.send(update)
                }
            }
        } catch {
            print("SSE: Error parsing price update: \(error)")
        }
    }
    
    private func handleMarketStatus(data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let status = json["status"] as? String {
                
                let marketStatus = MarketStatus(
                    status: status,
                    timestamp: Date()
                )
                
                DispatchQueue.main.async {
                    self.marketStatusPublisher.send(marketStatus)
                }
            }
        } catch {
            print("SSE: Error parsing market status: \(error)")
        }
    }
    
    private func sendSubscriptionRequest(
        connectionId: String,
        symbols: [String]?,
        rooms: [String]?,
        isSubscribe: Bool
    ) async {
        let endpoint = isSubscribe ? "subscribe" : "unsubscribe"
        guard let url = URL(string: "\(baseURL)/stream/\(endpoint)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "connectionId": connectionId,
            "symbols": symbols ?? [],
            "rooms": rooms ?? []
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await session!.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("SSE: \(isSubscribe ? "Subscribed" : "Unsubscribed") successfully")
            }
        } catch {
            print("SSE: Error sending subscription request: \(error)")
        }
    }
    
    private func handleError(_ message: String) {
        lastError = message
        connectionStatus = .error
        print("SSE Error: \(message)")
    }
    
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            handleError("Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30 seconds
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            print("SSE: Attempting reconnection \(self?.reconnectAttempts ?? 0)/\(self?.maxReconnectAttempts ?? 5)")
            self?.connect()
        }
    }
}

// MARK: - SSE Stream Delegate

class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private var eventBuffer = ""
    private var dataBuffer = ""
    private let eventHandler: (String?, String?) -> Void
    private var hasReceivedResponse = false
    
    init(eventHandler: @escaping (String?, String?) -> Void) {
        self.eventHandler = eventHandler
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Check if we got a valid SSE response
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200,
           httpResponse.allHeaderFields["Content-Type"] as? String == "text/event-stream" {
            hasReceivedResponse = true
            print("SSE: Valid response received, starting stream")
            completionHandler(.allow)
        } else {
            print("SSE: Invalid response received")
            completionHandler(.cancel)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Process SSE format
        let lines = string.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("event:") {
                eventBuffer = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataBuffer = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.isEmpty && !dataBuffer.isEmpty {
                // End of event, process it
                eventHandler(eventBuffer.isEmpty ? nil : eventBuffer, dataBuffer)
                eventBuffer = ""
                dataBuffer = ""
            } else if line.hasPrefix(":") {
                // Comment or heartbeat, ignore
                continue
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("SSE: Connection error: \(error.localizedDescription)")
        } else {
            print("SSE: Connection closed")
        }
    }
}

// MARK: - Models

struct GapperStock: Identifiable {
    let id = UUID()
    let symbol: String
    let price: Double
    let change_percent: Double
    let volume: Int
    let float: Int?
}