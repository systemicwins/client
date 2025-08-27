import Foundation
import SocketIO
import Combine

class SocketIOManager: ObservableObject {
    static let shared = SocketIOManager()
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    
    // Publishers for different event types
    let scanStatusPublisher = PassthroughSubject<[String: Any], Never>()
    let scanProgressPublisher = PassthroughSubject<[String: Any], Never>()
    let scanCompletePublisher = PassthroughSubject<[String: Any], Never>()
    let scanErrorPublisher = PassthroughSubject<[String: Any], Never>()
    let priceUpdatePublisher = PassthroughSubject<[String: Any], Never>()
    let gappersUpdatePublisher = PassthroughSubject<[String: Any], Never>()
    let positionsUpdatePublisher = PassthroughSubject<[String: Any], Never>()
    
    private init() {
        setupSocket()
    }
    
    private func setupSocket() {
        // Determine the URL based on environment
        let baseURL: String
        if let url = ProcessInfo.processInfo.environment["WS_BASE_URL"] {
            baseURL = url
        } else {
            let env = ProcessInfo.processInfo.environment["TRADER_ENV"] ?? "development"
            switch env {
            case "production":
                baseURL = "https://api.relentless.market"
            case "development":
                baseURL = "http://localhost:8888"
            default:
                baseURL = "http://localhost:8888"
            }
        }
        
        guard let url = URL(string: baseURL) else {
            print("Invalid Socket.IO URL: \(baseURL)")
            return
        }
        
        // Configure Socket.IO manager
        manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectAttempts(5),
                .reconnectWait(5),
                .reconnectWaitMax(30),
                .forceWebsockets(true),
                .secure(baseURL.starts(with: "https"))
            ]
        )
        
        socket = manager?.defaultSocket
        
        setupEventHandlers()
    }
    
    private func setupEventHandlers() {
        guard let socket = socket else { return }
        
        // Connection events
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isConnected = true
                self?.connectionStatus = "Connected"
                print("Socket.IO connected")
                
                // Join the scanner room to receive gapper updates
                self?.socket?.emit("join", "scanner")
                print("Joined scanner room for real-time gapper updates")
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.connectionStatus = "Disconnected"
                print("Socket.IO disconnected")
            }
        }
        
        socket.on(clientEvent: .error) { data, _ in
            if let error = data[0] as? String {
                print("Socket.IO error: \(error)")
            } else {
                print("Socket.IO error: \(data)")
            }
        }
        
        socket.on(clientEvent: .reconnect) { _, _ in
            print("Socket.IO reconnecting...")
        }
        
        socket.on(clientEvent: .reconnectAttempt) { data, _ in
            if let attemptNumber = data[0] as? Int {
                print("Socket.IO reconnect attempt #\(attemptNumber)")
            }
        }
        
        // Custom events from server
        socket.on("connected") { data, _ in
            print("Server acknowledged connection: \(data)")
        }
        
        socket.on("scan_status") { [weak self] data, _ in
            if let statusData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.scanStatusPublisher.send(statusData)
                }
            }
        }
        
        socket.on("scan_progress") { [weak self] data, _ in
            if let progressData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.scanProgressPublisher.send(progressData)
                }
            }
        }
        
        socket.on("scan_complete") { [weak self] data, _ in
            if let completeData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.scanCompletePublisher.send(completeData)
                }
            }
        }
        
        socket.on("scan_error") { [weak self] data, _ in
            if let errorData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.scanErrorPublisher.send(errorData)
                }
            }
        }
        
        socket.on("scan_cancelled") { data, _ in
            print("Scan cancelled: \(data)")
        }
        
        socket.on("price_update") { [weak self] data, _ in
            if let priceData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.priceUpdatePublisher.send(priceData)
                }
            }
        }
        
        socket.on("gappers:update") { [weak self] data, _ in
            if let gappersData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.gappersUpdatePublisher.send(gappersData)
                }
            }
        }
        
        socket.on("positions_update") { [weak self] data, _ in
            if let positionsData = data[0] as? [String: Any] {
                DispatchQueue.main.async {
                    self?.positionsUpdatePublisher.send(positionsData)
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    func connect() {
        socket?.connect()
    }
    
    func disconnect() {
        socket?.disconnect()
    }
    
    func startGapScan(data: [String: Any] = [:]) {
        socket?.emit("start_gap_scan", data)
    }
    
    func cancelGapScan(data: [String: Any] = [:]) {
        socket?.emit("cancel_gap_scan", data)
    }
    
    func emit(_ event: String, _ data: Any...) {
        socket?.emit(event, data)
    }
    
    func on(_ event: String, callback: @escaping ([Any], SocketAckEmitter) -> Void) {
        socket?.on(event, callback: callback)
    }
    
    func off(_ event: String) {
        socket?.off(event)
    }
    
    func subscribe(symbols: [String], type: String = "trades") {
        socket?.emit("subscribe", ["symbols": symbols, "type": type])
    }
    
    func unsubscribe(symbols: [String], type: String = "trades") {
        socket?.emit("unsubscribe", ["symbols": symbols, "type": type])
    }
}