import Foundation

// MARK: - Authentication Models
struct User: Codable, Identifiable {
    let id: Int
    let email: String
    let name: String
    let createdAt: Date?
    let roleId: Int?
    let roleName: String?
    let accountType: String?

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case createdAt = "created_at"
        case roleId = "role_id"
        case roleName = "role_name"
        case accountType = "account_type"
    }

    var isRetail: Bool {
        return accountType?.lowercased() == "retail" || roleName?.lowercased() == "retail"
    }

    var isPro: Bool {
        return accountType?.lowercased() == "pro" || roleName?.lowercased() == "pro"
    }
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct LoginResponse: Codable {
    let token: String
    let user: User
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String
}

// MARK: - Trading Models
struct Position: Codable, Identifiable {
    let id: String
    let symbol: String
    let quantity: Double
    let entryPrice: Double
    var currentPrice: Double  // Made mutable for price updates
    let unrealizedPnL: Double
    let unrealizedPnLPercent: Double
    let side: String // "long" or "short"
    let marketValue: Double
    
    enum CodingKeys: String, CodingKey {
        case id, symbol, quantity, side
        case entryPrice = "entry_price"
        case currentPrice = "current_price"
        case unrealizedPnL = "unrealized_pl"
        case unrealizedPnLPercent = "unrealized_plpc"
        case marketValue = "market_value"
    }
    
    var isProfit: Bool {
        return unrealizedPnL >= 0
    }
    
    var totalValue: Double {
        return quantity * currentPrice
    }
}

struct Trade: Codable, Identifiable {
    let id: String
    let symbol: String
    let side: String
    let quantity: Double
    let price: Double
    let timestamp: Date
    let orderId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, symbol, side, quantity, price, timestamp
        case orderId = "order_id"
    }
}

struct TradeRequest: Codable {
    let symbol: String
    let side: String // "buy" or "sell"
    let quantity: Double
}

struct TradeResponse: Codable {
    let orderId: String
    let symbol: String
    let side: String
    let quantity: Double
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case symbol, side, quantity, status
        case orderId = "order_id"
    }
}


// MARK: - Market Data Models
struct CandlestickData: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int64
    
    enum CodingKeys: String, CodingKey {
        case timestamp, open, high, low, close, volume
    }
}

struct MarketDataRequest: Codable {
    let symbol: String
    let timeframe: String
    let limit: Int
}

// MARK: - Portfolio & Performance Models
struct PortfolioSummary: Codable {
    let totalValue: Double
    let dailyPnL: Double
    let dailyPnLPercent: Double
    let totalPnL: Double
    let totalPnLPercent: Double
    let buyingPower: Double
    let cash: Double
    let positionsCount: Int
    
    enum CodingKeys: String, CodingKey {
        case totalValue = "total_value"
        case dailyPnL = "daily_pnl"
        case dailyPnLPercent = "daily_pnl_percent"
        case totalPnL = "total_pnl"
        case totalPnLPercent = "total_pnl_percent"
        case buyingPower = "buying_power"
        case cash, positionsCount = "positions_count"
    }
}

struct PerformanceData: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let portfolioValue: Double
    let dailyPnL: Double
    let cumulativePnL: Double
    
    enum CodingKeys: String, CodingKey {
        case date
        case portfolioValue = "portfolio_value"
        case dailyPnL = "daily_pnl"
        case cumulativePnL = "cumulative_pnl"
    }
}

// MARK: - API Response Wrappers
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
    let error: String?
}

struct APIError: Codable, Error {
    let message: String
    let code: Int?
    
    var localizedDescription: String {
        return message
    }
}

// MARK: - WebSocket Models
struct WebSocketMessage: Codable {
    let type: String
    let data: [String: Any]
    
    enum MessageType: String {
        case positionUpdate = "position_update"
        case priceUpdate = "price_update"
        case tradeExecution = "trade_execution"
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        
        // Handle [String: Any] manually
        let dataContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
        var dataDict: [String: Any] = [:]
        
        for key in dataContainer.allKeys {
            if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                dataDict[key.stringValue] = stringValue
            } else if let doubleValue = try? dataContainer.decode(Double.self, forKey: key) {
                dataDict[key.stringValue] = doubleValue
            } else if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                dataDict[key.stringValue] = intValue
            } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                dataDict[key.stringValue] = boolValue
            }
        }
        
        data = dataDict
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        // Note: Encoding [String: Any] is complex and may need custom implementation
    }
}

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Scanner Models
struct ScanInfoResponse: Codable {
    let totalGroups: Int
    let totalStocks: Int
    let groupSize: Int
    let source: String
    let status: String
    let error: String?
    let premarketHours: Bool
    let canScan: Bool
    let scanReason: String
    let nextScan: String?
    let lastScan: String?
    let cacheValid: Bool
    
    enum CodingKeys: String, CodingKey {
        case totalGroups = "total_groups"
        case totalStocks = "total_stocks"
        case groupSize = "group_size"
        case source, status, error
        case premarketHours = "premarket_hours"
        case canScan = "can_scan"
        case scanReason = "scan_reason"
        case nextScan = "next_scan"
        case lastScan = "last_scan"
        case cacheValid = "cache_valid"
    }
}


// MARK: - Configuration Models
struct AppConfiguration {
    static let apiBaseURL: String = {
        // Check for explicit API_BASE_URL override first
        if let url = ProcessInfo.processInfo.environment["API_BASE_URL"] {
            return url
        }
        
        // Default to production API (api.relentless.market)
        // Can override with TRADER_ENV=development for local testing
        let env = ProcessInfo.processInfo.environment["TRADER_ENV"] ?? "production"
        switch env {
        case "production":
            return "https://api.relentless.market"
        case "development":
            return "http://localhost:8888"
        default:
            return "https://api.relentless.market"
        }
    }()
    
    static let wsBaseURL: String = {
        // Check for explicit WS_BASE_URL override first
        if let url = ProcessInfo.processInfo.environment["WS_BASE_URL"] {
            return url
        }
        
        // Default to production WebSocket (wss://api.relentless.market)
        // Can override with TRADER_ENV=development for local testing
        let env = ProcessInfo.processInfo.environment["TRADER_ENV"] ?? "production"
        switch env {
        case "production":
            return "wss://api.relentless.market"
        case "development":
            return "ws://localhost:8888"
        default:
            return "wss://api.relentless.market"
        }
    }()
    
    static let polygonAPIKey = ProcessInfo.processInfo.environment["POLYGON_API_KEY"] ?? "wlfIHBXoky_8R07M8SgVtxqQLEN3T5So"
    static let polygonWSURL = "wss://socket.polygon.io"
    static let refreshInterval: TimeInterval = 30.0 // seconds
    static let chartUpdateInterval: TimeInterval = 5.0 // seconds
}