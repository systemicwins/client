import Foundation
import Combine
import SocketIO

class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()
    
    @Published var isConnected = false
    @Published var positionUpdates = PassthroughSubject<[Position], Never>()
    @Published var priceUpdates = PassthroughSubject<[String: Double], Never>()
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private let baseURL: String
    private var cancellables = Set<AnyCancellable>()
    private var reconnectTimer: Timer?
    
    override init() {
        // Convert wss:// or ws:// to https:// or http:// for Socket.IO
        let wsURL = AppConfiguration.wsBaseURL
        
        // Handle localhost specially
        if wsURL.contains("localhost") || wsURL.contains("127.0.0.1") {
            self.baseURL = wsURL
                .replacingOccurrences(of: "ws://", with: "http://")
                .replacingOccurrences(of: "wss://", with: "http://")
        } else {
            self.baseURL = wsURL
                .replacingOccurrences(of: "wss://", with: "https://")
                .replacingOccurrences(of: "ws://", with: "http://")
        }
        
        super.init()
        setupSocketIO()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Socket.IO Setup
    private func setupSocketIO() {
        guard let url = URL(string: baseURL) else {
            print("Invalid Socket.IO URL: \(baseURL)")
            return
        }
        
        // Configure Socket.IO manager
        let config: SocketIOClientConfiguration = [
            .log(false), // Disable verbose logging
            .compress,
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(2), // Reduce initial wait time
            .reconnectWaitMax(10), // Reduce max wait time
            .forceWebsockets(true), // Force WebSocket transport
            .secure(url.scheme == "https"),
            .path("/socket.io/"), // Explicit Socket.IO path
            .connectParams(["timeout": "2000"]) // Add connection timeout
        ]
        
        manager = SocketManager(socketURL: url, config: config)
        socket = manager?.defaultSocket
        
        setupSocketHandlers()
    }
    
    // MARK: - Socket.IO Event Handlers
    private func setupSocketHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isConnected = true
                print("Socket.IO connected to server")
            }
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isConnected = false
                print("Socket.IO disconnected from server")
            }
        }
        
        socket?.on(clientEvent: .error) { _, ack in
            print("Socket.IO error: \(ack)")
        }
        
        // Handle custom events from server
        socket?.on("connected") { data, _ in
            print("Server acknowledged connection: \(data)")
        }
        
        socket?.on("positions_update") { [weak self] data, _ in
            guard let jsonData = data.first else { return }
            
            do {
                let jsonString = try JSONSerialization.data(withJSONObject: jsonData)
                let positions = try JSONDecoder().decode([Position].self, from: jsonString)
                
                DispatchQueue.main.async {
                    self?.positionUpdates.send(positions)
                }
            } catch {
                print("Failed to decode positions update: \(error)")
            }
        }
        
        socket?.on("price_update") { [weak self] data, _ in
            guard let prices = data.first as? [String: Double] else { return }
            
            DispatchQueue.main.async {
                self?.priceUpdates.send(prices)
            }
        }
    }
    
    // MARK: - Connection Management
    func connect() {
        socket?.connect()
    }
    
    func disconnect() {
        socket?.disconnect()
        isConnected = false
    }
    
    // MARK: - Public Methods
    func sendMessage<T: Codable>(_ event: String, _ message: T) {
        guard isConnected else {
            print("Socket.IO not connected, cannot send message")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(message)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                socket?.emit(event, json)
            }
        } catch {
            print("Failed to send Socket.IO message: \(error)")
        }
    }
    
    func emit(_ event: String, _ data: Any...) {
        guard isConnected else {
            print("Socket.IO not connected, cannot emit event")
            return
        }
        
        socket?.emit(event, data)
    }
    
    // MARK: - Connection Status
    var connectionStatus: String {
        if isConnected {
            return "Connected"
        } else if socket?.status == .connecting {
            return "Connecting..."
        } else {
            return "Disconnected"
        }
    }
}