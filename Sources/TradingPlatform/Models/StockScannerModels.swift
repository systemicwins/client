import Foundation
import SwiftUI

// MARK: - Stock Scanner Models

struct MarketStatus: Codable {
    let status: String  // "closed", "premarket", "open", "afterhours"
    let isOpen: Bool  // Is market open today (trading day)
    let isPremarket: Bool
    let isRegularHours: Bool
    let isAfterhours: Bool
    let marketOpen: String?  // "09:30"
    let marketClose: String?  // "16:00" or "13:00" for early close
    let sessionEnd: String?  // When current session ends
    let currentTimeET: String?  // Current time in ET
    let scannerActive: Bool  // Is scanner running (4AM-9:30AM ET)
    let scannerMessage: String?
    let reason: String?  // If closed, why (weekend/holiday)
    let nextOpen: String?  // Next market open datetime
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case isOpen = "is_open"
        case isPremarket = "is_premarket"
        case isRegularHours = "is_regular_hours"
        case isAfterhours = "is_afterhours"
        case marketOpen = "market_open"
        case marketClose = "market_close"
        case sessionEnd = "session_end"
        case currentTimeET = "current_time_et"
        case scannerActive = "scanner_active"
        case scannerMessage = "scanner_message"
        case reason
        case nextOpen = "next_open"
        case timestamp
    }
    
    var sessionDescription: String {
        switch status {
        case "premarket":
            return "Pre-Market"
        case "open":
            return "Market Open"
        case "afterhours":
            return "After-Hours"
        case "closed":
            return isOpen ? "Closed" : (reason ?? "Market Closed")
        default:
            return status.capitalized
        }
    }
    
    var isMarketOpenToday: Bool {
        return isOpen
    }
    
    var marketHoursDescription: String {
        guard let open = marketOpen, let close = marketClose else {
            return isOpen ? "Market Hours Unknown" : "Market Closed Today"
        }
        return "\(open) - \(close) ET"
    }
}

struct FilteredStock: Identifiable, Codable, Equatable {
    let id = UUID()
    let symbol: String
    let name: String
    let exchange: String
    let previousClose: Double
    let previousVolume: Int
    let previousVWAP: Double?
    let float: Double?
    
    // Real-time data (optional, updated via WebSocket)
    var currentPrice: Double?
    var currentVolume: Int?
    var bid: Double?
    var ask: Double?
    var lastUpdate: Date?
    
    var changePercent: Double {
        guard let current = currentPrice else { return 0 }
        return ((current - previousClose) / previousClose) * 100
    }
    
    var changeAmount: Double {
        guard let current = currentPrice else { return 0 }
        return current - previousClose
    }
    
    var isPositive: Bool {
        return changeAmount >= 0
    }
    
    var formattedFloat: String {
        guard let float = float else { return "N/A" }
        return String(format: "%.2fM", float / 1_000_000)
    }
    
    var spreadPercent: Double? {
        guard let bid = bid, let ask = ask, bid > 0 else { return nil }
        return ((ask - bid) / bid) * 100
    }
    
    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange
        case previousClose, previousVolume, previousVWAP
        case float
        case currentPrice, currentVolume
        case bid, ask, lastUpdate
    }
    
    init(symbol: String, name: String, exchange: String, previousClose: Double, previousVolume: Int, previousVWAP: Double?, float: Double?, currentPrice: Double? = nil, currentVolume: Int? = nil, bid: Double? = nil, ask: Double? = nil, lastUpdate: Date? = nil) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.previousClose = previousClose
        self.previousVolume = previousVolume
        self.previousVWAP = previousVWAP
        self.float = float
        self.currentPrice = currentPrice
        self.currentVolume = currentVolume
        self.bid = bid
        self.ask = ask
        self.lastUpdate = lastUpdate
    }
    
    init(from stock: Stock) {
        self.symbol = stock.symbol
        self.name = stock.name ?? stock.symbol
        self.exchange = stock.exchange ?? "NASDAQ"
        self.previousClose = stock.previousClose ?? stock.price ?? 0
        self.previousVolume = stock.volume ?? 0
        self.previousVWAP = stock.vwap
        self.float = stock.float.map(Double.init)
        self.currentPrice = stock.price
        self.currentVolume = stock.volume
        self.bid = nil
        self.ask = nil
        self.lastUpdate = nil
    }
}

struct ScannerSummary: Codable {
    let totalFiltered: Int
    let priceRange: PriceRange
    let maxFloat: Int
    let topMovers: [StockMover]
    let mostActive: [StockMover]
    let marketStatus: MarketStatus?
    
    struct PriceRange: Codable {
        let min: Double
        let max: Double
    }
}

struct StockMover: Identifiable, Codable {
    let id = UUID()
    let symbol: String
    let name: String?
    let previousClose: Double
    let currentPrice: Double
    let changePercent: Double
    let volume: Int
    
    var changeAmount: Double {
        return currentPrice - previousClose
    }
    
    var isPositive: Bool {
        return changePercent >= 0
    }
    
    var formattedVolume: String {
        if volume >= 1_000_000 {
            return String(format: "%.2fM", Double(volume) / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.1fK", Double(volume) / 1_000)
        }
        return "\(volume)"
    }
    
    enum CodingKeys: String, CodingKey {
        case symbol, name
        case previousClose, currentPrice
        case changePercent, volume
    }
}

// MARK: - API Response Models

struct ProcessingStatus: Codable {
    var phase: String
    var message: String
    var isProcessing: Bool
    var progress: Int?
    var lastUpdate: Date?
    
    enum CodingKeys: String, CodingKey {
        case phase, message, isProcessing, progress, lastUpdate
    }
}

struct FilteredStocksResponse: Codable {
    let success: Bool
    let count: Int
    let data: [FilteredStock]
    let status: ProcessingStatus?
}

// Response format for /scanner/filtered endpoint
struct ScannerFilteredResponse: Codable {
    let count: Int
    let stocks: [FilteredStock]
    let criteria: ScannerCriteria?
    let timestamp: String?
    let status: String?  // "populating", "empty", "error", or nil for normal
    let message: String?  // User-friendly message about the status
}

struct ScannerCriteria: Codable {
    let max_float: String?
    let min_gain: String?
    let price_range: String?
}

struct ScannerSummaryResponse: Codable {
    let success: Bool
    let data: ScannerSummary
}

struct ScannerSummaryWithStatus: Codable {
    let totalFiltered: Int
    let priceRange: ScannerSummary.PriceRange
    let maxFloat: Int
    let topMovers: [StockMover]
    let mostActive: [StockMover]
    let status: ProcessingStatus
    let marketStatus: MarketStatus?
}

struct RefreshResponse: Codable {
    let success: Bool
    let message: String
    let status: String
    let timestamp: Date?
}

struct MarketStatusResponse: Codable {
    let status: String
    let isOpen: Bool
    let isPremarket: Bool
    let isRegularHours: Bool
    let isAfterhours: Bool
    let marketOpen: String?
    let marketClose: String?
    let sessionEnd: String?
    let currentTimeET: String?
    let scannerActive: Bool
    let scannerMessage: String?
    let reason: String?
    let nextOpen: String?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case isOpen = "is_open"
        case isPremarket = "is_premarket"
        case isRegularHours = "is_regular_hours"
        case isAfterhours = "is_afterhours"
        case marketOpen = "market_open"
        case marketClose = "market_close"
        case sessionEnd = "session_end"
        case currentTimeET = "current_time_et"
        case scannerActive = "scanner_active"
        case scannerMessage = "scanner_message"
        case reason
        case nextOpen = "next_open"
        case timestamp
    }
}

// MARK: - Basic Stock Model for API

struct Stock: Identifiable, Decodable {
    let id = UUID()
    let symbol: String
    let name: String?
    let exchange: String?
    let price: Double?
    let previousClose: Double?
    let volume: Int?
    let float: Int?
    let vwap: Double?
    let changePercent: Double?
    let changeAmount: Double?
    
    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange, price, volume, float, vwap
        case previousClose = "previous_close"
        case changePercent = "change_percent"
        case changeAmount = "change_amount"
    }
    
    init(symbol: String, name: String? = nil, price: Double? = nil, changePercent: Double? = nil, changeAmount: Double? = nil) {
        self.symbol = symbol
        self.name = name
        self.exchange = nil
        self.price = price
        self.previousClose = nil
        self.volume = nil
        self.float = nil
        self.vwap = nil
        self.changePercent = changePercent
        self.changeAmount = changeAmount
    }
}

// MARK: - WebSocket Message Models

struct StockScannerWebSocketMessage: Codable {
    let type: MessageType
    let data: Data
    
    enum MessageType: String, Codable {
        case initial
        case aggregate
        case trade
        case quote
    }
    
    func decode<T: Codable>(_ type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}

struct AggregateData: Codable {
    let symbol: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
    let vwap: Double?
    let timestamp: TimeInterval
}

struct TradeData: Codable {
    let symbol: String
    let price: Double
    let size: Int
    let timestamp: TimeInterval
}

struct QuoteData: Codable {
    let symbol: String
    let bid: Double
    let bidSize: Int
    let ask: Double
    let askSize: Int
    let timestamp: TimeInterval
    let spreadPercent: Double?
}

// MARK: - Order Model

struct Order: Identifiable, Codable {
    let id: String
    let symbol: String
    let side: String  // "buy" or "sell"
    let quantity: Int
    let type: String  // "market", "limit", "stop", "stop_limit"
    let status: String  // "pending", "filled", "cancelled"
    let price: Double
    var stopPrice: Double?
    let filledAt: Date?
    
    var formattedType: String {
        switch type {
        case "market": return "Market"
        case "limit": return "Limit"
        case "stop": return "Stop Loss"
        case "stop_limit": return "Stop Limit"
        default: return type.capitalized
        }
    }
    
    var formattedStatus: String {
        switch status {
        case "pending": return "Pending"
        case "filled": return "Filled"
        case "cancelled": return "Cancelled"
        default: return status.capitalized
        }
    }
    
    var statusColor: Color {
        switch status {
        case "filled": return .green
        case "pending": return .orange
        case "cancelled": return .red
        default: return .secondary
        }
    }
}

// MARK: - Gapper Response Models (for /gappers endpoint)

struct GapperItem: Codable {
    let ticker: String
    let price: Double
    let prevClose: Double
    let gapPercent: Double
    let volume: Double
    let rvol: Double
    let rvolDisplay: String
    let floatShares: Double
    let hasNews: Bool
    let rank: Int?
    let avgVolume: Double?
    
    private enum CodingKeys: String, CodingKey {
        case ticker
        case price
        case prevClose = "prev_close"
        case gapPercent = "gap_percent"
        case volume
        case rvol
        case rvolDisplay = "rvol_display"
        case floatShares = "float_shares"
        case hasNews = "has_news"
        case rank
        case avgVolume = "avg_volume"
    }
    
    // Convert to FilteredStock for compatibility
    func toFilteredStock() -> FilteredStock {
        return FilteredStock(
            symbol: ticker,
            name: ticker, // We don't have company name in gapper response
            exchange: "NASDAQ", // Default exchange
            previousClose: prevClose,
            previousVolume: Int(avgVolume ?? 0),
            previousVWAP: nil,
            float: floatShares > 0 ? floatShares : nil,
            currentPrice: price,
            currentVolume: Int(volume),
            bid: nil,
            ask: nil,
            lastUpdate: Date()
        )
    }
}

struct GappersResponse: Codable {
    let count: Int
    let gappers: [GapperItem]
    let lastScan: String?
    let success: Bool?
    let message: String?
    
    private enum CodingKeys: String, CodingKey {
        case count
        case gappers
        case lastScan = "last_scan"
        case success
        case message
    }
}