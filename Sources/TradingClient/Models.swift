import Foundation

// MARK: - Authentication Models
struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct LoginResponse: Codable {
    let success: Bool
    let token: String?
    let message: String?
    let user: User?
}

struct User: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, email
        case createdAt = "created_at"
    }
}

// MARK: - Trading Models
struct Position: Codable, Identifiable {
    let id: String
    let symbol: String
    let quantity: Double
    let averagePrice: Double
    let currentPrice: Double
    let marketValue: Double
    let unrealizedPnL: Double
    let unrealizedPnLPercent: Double
    let side: String
    
    enum CodingKeys: String, CodingKey {
        case id = "asset_id"
        case symbol, quantity
        case averagePrice = "avg_entry_price"
        case currentPrice = "current_price"
        case marketValue = "market_value"
        case unrealizedPnL = "unrealized_pl"
        case unrealizedPnLPercent = "unrealized_plpc"
        case side
    }
}

struct Order: Codable, Identifiable {
    let id: String
    let symbol: String
    let quantity: Double
    let filledQuantity: Double
    let orderType: String
    let side: String
    let timeInForce: String
    let status: String
    let submittedAt: String
    let limitPrice: Double?
    let stopPrice: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, symbol
        case quantity = "qty"
        case filledQuantity = "filled_qty"
        case orderType = "order_type"
        case side
        case timeInForce = "time_in_force"
        case status
        case submittedAt = "submitted_at"
        case limitPrice = "limit_price"
        case stopPrice = "stop_price"
    }
}

struct GapOpportunity: Codable, Identifiable {
    let id = UUID()
    let symbol: String
    let gapPercent: Double
    let volume: Int
    let price: Double
    let direction: String
    let confidence: Double
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case gapPercent = "gap_percent"
        case volume, price, direction, confidence, timestamp
    }
}

struct AccountInfo: Codable {
    let accountNumber: String
    let buyingPower: Double
    let cash: Double
    let portfolioValue: Double
    let equity: Double
    let dayTradeCount: Int
    
    enum CodingKeys: String, CodingKey {
        case accountNumber = "account_number"
        case buyingPower = "buying_power"
        case cash
        case portfolioValue = "portfolio_value"
        case equity
        case dayTradeCount = "daytrade_count"
    }
}

struct Trade: Codable, Identifiable {
    let id: String
    let symbol: String
    let quantity: Double
    let price: Double
    let side: String
    let timestamp: String
    let commission: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, symbol
        case quantity = "qty"
        case price, side, timestamp, commission
    }
}

// MARK: - API Response Models
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
    let error: String?
}

struct ErrorResponse: Codable {
    let success: Bool
    let error: String
    let message: String?
}