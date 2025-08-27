import Foundation
import SwiftUICharts

// MARK: - Data Update Types (from API/SSE)

struct TradeUpdate {
    let symbol: String
    let price: Double
    let size: Int
    let timestamp: Date
}

struct QuoteUpdate {
    let symbol: String
    let bidPrice: Double
    let askPrice: Double
    let bidSize: Int
    let askSize: Int
    let timestamp: Date
}

struct AggregateUpdate {
    let symbol: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
    let timestamp: Date
}

// MARK: - Candlestick Data Models

struct Candle: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Int
    
    static func == (lhs: Candle, rhs: Candle) -> Bool {
        return lhs.id == rhs.id
    }
    
    var isGreen: Bool {
        close >= open
    }
    
    var bodyHeight: Double {
        abs(close - open)
    }
    
    var wickHeight: Double {
        high - low
    }
    
    var upperWickHeight: Double {
        high - max(open, close)
    }
    
    var lowerWickHeight: Double {
        min(open, close) - low
    }
}

class CandlestickChartData: ObservableObject {
    @Published var candles: [Candle] = []
    @Published var currentPrice: Double = 0
    @Published var dayChange: Double = 0
    @Published var dayChangePercent: Double = 0
    @Published var dayVolume: Int = 0
    @Published var bid: Double = 0
    @Published var ask: Double = 0
    @Published var spread: Double = 0
    
    // MACD indicators
    @Published var macdLine: [Double] = []
    @Published var signalLine: [Double] = []
    @Published var histogram: [Double] = []
    
    private var currentMinuteCandle: Candle?
    private let maxCandles = 390 // Full trading day of 1-minute candles (6.5 hours)
    
    func addHistoricalCandles(_ newCandles: [Candle]) {
        candles = newCandles.sorted { $0.timestamp < $1.timestamp }
        
        // Keep only the most recent candles
        if candles.count > maxCandles {
            candles = Array(candles.suffix(maxCandles))
        }
        
        // Calculate MACD indicators
        calculateMACD()
    }
    
    func updateFromTrade(_ trade: TradeUpdate) {
        currentPrice = trade.price
        
        // Update or create current minute candle
        let currentMinute = Calendar.current.dateInterval(of: .minute, for: trade.timestamp)!
        
        if let index = candles.firstIndex(where: { 
            Calendar.current.dateInterval(of: .minute, for: $0.timestamp)?.start == currentMinute.start 
        }) {
            // Update existing candle
            candles[index].high = max(candles[index].high, trade.price)
            candles[index].low = min(candles[index].low, trade.price)
            candles[index].close = trade.price
            candles[index].volume += trade.size
        } else {
            // Create new candle
            let newCandle = Candle(
                timestamp: currentMinute.start,
                open: trade.price,
                high: trade.price,
                low: trade.price,
                close: trade.price,
                volume: trade.size
            )
            candles.append(newCandle)
            
            // Maintain max candles limit
            if candles.count > maxCandles {
                candles.removeFirst()
            }
            
            // Recalculate MACD with new candle
            calculateMACD()
        }
    }
    
    func updateFromQuote(_ quote: QuoteUpdate) {
        bid = quote.bidPrice
        ask = quote.askPrice
        spread = quote.askPrice - quote.bidPrice
    }
    
    func updateFromAggregate(_ aggregate: AggregateUpdate) {
        // Find or create candle for this timestamp
        let candleTime = Date(timeIntervalSince1970: aggregate.timestamp.timeIntervalSince1970.rounded(to: 60))
        
        if let index = candles.firstIndex(where: { abs($0.timestamp.timeIntervalSince(candleTime)) < 30 }) {
            // Update existing candle with aggregate data
            candles[index].high = max(candles[index].high, aggregate.high)
            candles[index].low = min(candles[index].low, aggregate.low)
            candles[index].close = aggregate.close
            candles[index].volume = aggregate.volume
        } else {
            // Add new candle from aggregate
            let newCandle = Candle(
                timestamp: candleTime,
                open: aggregate.open,
                high: aggregate.high,
                low: aggregate.low,
                close: aggregate.close,
                volume: aggregate.volume
            )
            candles.append(newCandle)
            candles.sort { $0.timestamp < $1.timestamp }
            
            // Maintain max candles limit
            if candles.count > maxCandles {
                candles.removeFirst()
            }
            
            // Recalculate MACD with new candle
            calculateMACD()
        }
        
        currentPrice = aggregate.close
        dayVolume += aggregate.volume
    }
    
    var priceRange: ClosedRange<Double> {
        guard !candles.isEmpty else { return 0...100 }
        let prices = candles.flatMap { [$0.high, $0.low] }
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 100
        let padding = (maxPrice - minPrice) * 0.1
        return (minPrice - padding)...(maxPrice + padding)
    }
    
    var volumeRange: ClosedRange<Int> {
        guard !candles.isEmpty else { return 0...1000000 }
        let maxVolume = candles.map { $0.volume }.max() ?? 1000000
        return 0...(maxVolume * 11 / 10) // Add 10% padding
    }
    
    func updateCurrentCandle(_ candle: Candle) {
        // Find and update the current minute's candle or add it if it doesn't exist
        let candleMinute = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candle.timestamp)) ?? candle.timestamp
        
        if let index = candles.firstIndex(where: { 
            let existingMinute = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0.timestamp)) ?? $0.timestamp
            return existingMinute == candleMinute
        }) {
            // Update existing candle
            candles[index] = candle
        } else {
            // Add new candle
            candles.append(candle)
            candles.sort { $0.timestamp < $1.timestamp }
            
            // Maintain max candles limit
            if candles.count > maxCandles {
                candles.removeFirst()
            }
            
            // Recalculate MACD with new candle
            calculateMACD()
        }
        
        // Update current price
        currentPrice = candle.close
    }
    
    // MARK: - MACD Calculation
    
    func calculateMACD() {
        guard candles.count >= 26 else {
            // Not enough data for MACD
            macdLine = []
            signalLine = []
            histogram = []
            return
        }
        
        let closes = candles.map { $0.close }
        
        // Calculate EMAs
        let ema12 = calculateEMA(values: closes, period: 12)
        let ema26 = calculateEMA(values: closes, period: 26)
        
        // Calculate MACD line (12-period EMA - 26-period EMA)
        var macdValues: [Double] = []
        for i in 0..<min(ema12.count, ema26.count) {
            macdValues.append(ema12[i] - ema26[i])
        }
        
        // Calculate Signal line (9-period EMA of MACD)
        let signal = calculateEMA(values: macdValues, period: 9)
        
        // Calculate Histogram (MACD - Signal)
        var histogramValues: [Double] = []
        for i in 0..<min(macdValues.count, signal.count) {
            histogramValues.append(macdValues[i] - signal[i])
        }
        
        // Update published values
        self.macdLine = macdValues
        self.signalLine = signal
        self.histogram = histogramValues
    }
    
    private func calculateEMA(values: [Double], period: Int) -> [Double] {
        guard values.count >= period else { return [] }
        
        var ema: [Double] = []
        let multiplier = 2.0 / Double(period + 1)
        
        // Calculate initial SMA for the first EMA value
        let initialSMA = values.prefix(period).reduce(0, +) / Double(period)
        ema.append(initialSMA)
        
        // Calculate EMA for remaining values
        for i in period..<values.count {
            let emaValue = (values[i] - ema.last!) * multiplier + ema.last!
            ema.append(emaValue)
        }
        
        // Pad the beginning with the first EMA value to match array length
        let padding = Array(repeating: ema.first ?? 0, count: period - 1)
        return padding + ema
    }
}

// MARK: - SwiftUICharts Integration
// Note: SwiftUICharts doesn't have built-in candlestick charts
// We'll use our custom implementation instead

// Extension to round time to nearest interval
// MARK: - Helper Extensions
extension Double {
    func rounded(to interval: Double) -> Double {
        return (self / interval).rounded() * interval
    }
}