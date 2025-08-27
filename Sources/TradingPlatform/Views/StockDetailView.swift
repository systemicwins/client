import SwiftUI
import Charts

struct StockDetailView: View {
    let stock: FilteredStock
    @StateObject private var candlestickData = CandlestickChartData()
    @State private var selectedCandle: Candle?
    @State private var hoveredCandle: Candle?
    @State private var showVolume = true
    @State private var chartTimeframe = "1D"
    @State private var orderQuantity = "100"
    @State private var orderType = "market"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Chart section (left side)
                VStack(spacing: 0) {
                    // Price info bar
                    priceInfoBar
                    
                    // Candlestick chart
                    candlestickChart
                        .frame(minHeight: 400)
                    
                    // Volume chart
                    if showVolume {
                        volumeChart
                            .frame(height: 100)
                    }
                }
                .frame(minWidth: 800)
                
                Divider()
                
                // Trading panel (right side)
                tradingPanel
                    .frame(width: 350)
            }
            
            Divider()
            
            // Bottom info bar
            bottomInfoBar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupWebSocket()
            loadHistoricalData()
        }
        .onDisappear {
            // Data cleanup handled by CandlestickManager
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.left")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(stock.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Timeframe selector
            Picker("Timeframe", selection: $chartTimeframe) {
                Text("1D").tag("1D")
                Text("5D").tag("5D")
                Text("1M").tag("1M")
                Text("3M").tag("3M")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            Toggle("Volume", isOn: $showVolume)
                .padding(.leading)
            
        }
        .padding()
    }
    
    // MARK: - Price Info Bar
    private var priceInfoBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last Price")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "$%.2f", candlestickData.currentPrice))
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Change")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(String(format: "%.2f", candlestickData.dayChange))
                    Text(String(format: "(%.2f%%)", candlestickData.dayChangePercent))
                }
                .foregroundColor(candlestickData.dayChange >= 0 ? .green : .red)
                .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Volume")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatVolume(candlestickData.dayVolume))
                    .font(.title3)
            }
            
            Spacer()
            
            if let candle = hoveredCandle ?? candlestickData.candles.last {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDate(candle.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Label(String(format: "O: %.2f", candle.open), systemImage: "")
                        Label(String(format: "H: %.2f", candle.high), systemImage: "")
                        Label(String(format: "L: %.2f", candle.low), systemImage: "")
                        Label(String(format: "C: %.2f", candle.close), systemImage: "")
                    }
                    .font(.caption)
                    .foregroundColor(candle.isGreen ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    // MARK: - Candlestick Chart
    private var candlestickChart: some View {
        Chart(candlestickData.candles) { candle in
            // Candle body
            RectangleMark(
                x: .value("Time", candle.timestamp),
                yStart: .value("Open", min(candle.open, candle.close)),
                yEnd: .value("Close", max(candle.open, candle.close)),
                width: 2
            )
            .foregroundStyle(candle.isGreen ? Color.green : Color.red)
            
            // Upper wick
            RuleMark(
                x: .value("Time", candle.timestamp),
                yStart: .value("High", candle.high),
                yEnd: .value("Body Top", max(candle.open, candle.close))
            )
            .lineStyle(StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(candle.isGreen ? Color.green : Color.red)
            
            // Lower wick
            RuleMark(
                x: .value("Time", candle.timestamp),
                yStart: .value("Body Bottom", min(candle.open, candle.close)),
                yEnd: .value("Low", candle.low)
            )
            .lineStyle(StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(candle.isGreen ? Color.green : Color.red)
        }
        .chartYScale(domain: candlestickData.priceRange)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: 30)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .padding()
    }
    
    // MARK: - Volume Chart
    private var volumeChart: some View {
        Chart(candlestickData.candles) { candle in
            BarMark(
                x: .value("Time", candle.timestamp),
                y: .value("Volume", candle.volume)
            )
            .foregroundStyle(candle.isGreen ? Color.green.opacity(0.6) : Color.red.opacity(0.6))
        }
        .chartYScale(domain: candlestickData.volumeRange)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    // MARK: - Trading Panel
    private var tradingPanel: some View {
        VStack(spacing: 16) {
            Text("Trade \(stock.symbol)")
                .font(.headline)
                .padding(.top)
            
            Divider()
            
            // Bid/Ask spread
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bid")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", candlestickData.bid))
                        .font(.title3)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Spread")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.3f", candlestickData.spread))
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Ask")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", candlestickData.ask))
                        .font(.title3)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            
            // Order type selector
            Picker("Order Type", selection: $orderType) {
                Text("Market").tag("market")
                Text("Limit").tag("limit")
                Text("Stop").tag("stop")
                Text("Stop Limit").tag("stop_limit")
            }
            .pickerStyle(.segmented)
            
            // Quantity input
            VStack(alignment: .leading, spacing: 4) {
                Text("Quantity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("Shares", text: $orderQuantity)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("-10") { adjustQuantity(-10) }
                        .buttonStyle(.bordered)
                    Button("+10") { adjustQuantity(10) }
                        .buttonStyle(.bordered)
                    Button("+100") { adjustQuantity(100) }
                        .buttonStyle(.bordered)
                }
            }
            
            // Estimated cost
            if let qty = Int(orderQuantity) {
                VStack(spacing: 4) {
                    HStack {
                        Text("Estimated Cost:")
                        Spacer()
                        Text(String(format: "$%.2f", Double(qty) * candlestickData.currentPrice))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
            }
            
            // Buy/Sell buttons
            HStack(spacing: 12) {
                Button(action: placeBuyOrder) {
                    Text("Buy")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: placeSellOrder) {
                    Text("Sell")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            Spacer()
            
            // Stock info
            VStack(alignment: .leading, spacing: 8) {
                StockInfoRow(label: "Float", value: formatFloat(stock.float))
                StockInfoRow(label: "Prev Close", value: String(format: "$%.2f", stock.previousClose))
                StockInfoRow(label: "Prev Volume", value: formatVolume(stock.previousVolume))
                StockInfoRow(label: "Exchange", value: stock.exchange)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
        }
        .padding()
    }
    
    // MARK: - Bottom Info Bar
    private var bottomInfoBar: some View {
        HStack(spacing: 20) {
            Label("\(candlestickData.candles.count) candles", systemImage: "chart.xyaxis.line")
            
            if let firstCandle = candlestickData.candles.first,
               let lastCandle = candlestickData.candles.last {
                Label("\(formatTimeRange(from: firstCandle.timestamp, to: lastCandle.timestamp))",
                      systemImage: "clock")
            }
            
            Spacer()
            
            Label("Real-time data from Polygon", systemImage: "dot.radiowaves.left.and.right")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .padding()
        .background(Color.gray.opacity(0.05))
    }
    
    // MARK: - Helper Functions
    
    private func setupWebSocket() {
        // Real-time data now comes through the API via SSE
        // The CandlestickManager handles all subscriptions
    }
    
    private func loadHistoricalData() {
        // TODO: Load historical 1-minute candles from API or Polygon REST API
        // For now, initialize with current data
        candlestickData.currentPrice = stock.currentPrice ?? stock.previousClose
        candlestickData.bid = stock.bid ?? 0
        candlestickData.ask = stock.ask ?? 0
        candlestickData.spread = (stock.ask ?? 0) - (stock.bid ?? 0)
    }
    
    private func adjustQuantity(_ delta: Int) {
        if let current = Int(orderQuantity) {
            orderQuantity = String(max(1, current + delta))
        }
    }
    
    private func placeBuyOrder() {
        print("Placing buy order for \(orderQuantity) shares of \(stock.symbol)")
        // TODO: Implement order placement
    }
    
    private func placeSellOrder() {
        print("Placing sell order for \(orderQuantity) shares of \(stock.symbol)")
        // TODO: Implement order placement
    }
    
    private func formatVolume(_ volume: Int) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", Double(volume) / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.1fK", Double(volume) / 1_000)
        } else {
            return "\(volume)"
        }
    }
    
    private func formatFloat(_ float: Double?) -> String {
        guard let float = float else { return "N/A" }
        if float >= 1_000_000 {
            return String(format: "%.2fM", float / 1_000_000)
        } else if float >= 1_000 {
            return String(format: "%.0fK", float / 1_000)
        } else {
            return String(format: "%.0f", float)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatTimeRange(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: from)) - \(formatter.string(from: to))"
    }
}

struct StockInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}