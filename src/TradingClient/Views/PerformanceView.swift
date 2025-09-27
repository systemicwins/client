import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedPeriod = "1M"
    @State private var trades: [Trade] = []
    @State private var isLoading = false
    
    let periods = ["1D", "1W", "1M", "3M", "6M", "1Y", "ALL"]
    
    var performanceMetrics: PerformanceMetrics {
        calculateMetrics(from: trades)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Period selector
            HStack {
                Text("Performance Period:")
                    .font(.headline)
                
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(periods, id: \.self) { period in
                        Text(period).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 400)
                
                Spacer()
                
                Button("Refresh") {
                    loadPerformanceData()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Performance summary cards
                    PerformanceSummaryView(metrics: performanceMetrics)
                    
                    HStack(alignment: .top, spacing: 20) {
                        // Performance chart placeholder
                        PerformanceChartView(trades: trades)
                        
                        // Statistics
                        PerformanceStatsView(metrics: performanceMetrics)
                    }
                    
                    // Recent trades table
                    RecentTradesView(trades: trades)
                }
                .padding()
            }
        }
        .navigationTitle("Performance")
        .onAppear {
            loadPerformanceData()
        }
        .onChange(of: selectedPeriod) { _, _ in
            loadPerformanceData()
        }
    }
    
    private func loadPerformanceData() {
        isLoading = true
        
        // TODO: Implement API call to get performance data
        // For now, using mock data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.trades = mockTrades()
            self.isLoading = false
        }
    }
    
    private func mockTrades() -> [Trade] {
        return [
            Trade(id: "1", symbol: "AAPL", quantity: 100, price: 150.0, side: "buy", timestamp: "2024-08-01T09:30:00Z", commission: 1.0),
            Trade(id: "2", symbol: "AAPL", quantity: 100, price: 155.0, side: "sell", timestamp: "2024-08-01T15:30:00Z", commission: 1.0),
            Trade(id: "3", symbol: "TSLA", quantity: 50, price: 250.0, side: "sell", timestamp: "2024-08-02T10:00:00Z", commission: 1.0),
            Trade(id: "4", symbol: "TSLA", quantity: 50, price: 245.0, side: "buy", timestamp: "2024-08-02T14:00:00Z", commission: 1.0)
        ]
    }
}

struct PerformanceMetrics {
    let totalPnL: Double
    let totalPnLPercent: Double
    let winRate: Double
    let averageWin: Double
    let averageLoss: Double
    let profitFactor: Double
    let totalTrades: Int
    let winningTrades: Int
    let losingTrades: Int
    let totalCommissions: Double
}

struct PerformanceSummaryView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        GroupBox("Performance Summary") {
            HStack(spacing: 20) {
                MetricCard(
                    title: "Total P&L",
                    value: String(format: "$%.2f", metrics.totalPnL),
                    color: metrics.totalPnL >= 0 ? .green : .red
                )
                
                MetricCard(
                    title: "Win Rate",
                    value: String(format: "%.1f%%", metrics.winRate),
                    color: metrics.winRate >= 50 ? .green : .red
                )
                
                MetricCard(
                    title: "Total Trades",
                    value: String(metrics.totalTrades),
                    color: .blue
                )
                
                MetricCard(
                    title: "Profit Factor",
                    value: String(format: "%.2f", metrics.profitFactor),
                    color: metrics.profitFactor >= 1.0 ? .green : .red
                )
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct PerformanceChartView: View {
    let trades: [Trade]
    
    var body: some View {
        GroupBox("P&L Chart") {
            VStack {
                Text("Chart Integration Point")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("This is where a performance chart would be displayed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Placeholder chart visualization
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    )
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }
}

struct PerformanceStatsView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 12) {
                StatRow(label: "Winning Trades", value: String(metrics.winningTrades))
                StatRow(label: "Losing Trades", value: String(metrics.losingTrades))
                StatRow(label: "Average Win", value: String(format: "$%.2f", metrics.averageWin))
                StatRow(label: "Average Loss", value: String(format: "$%.2f", metrics.averageLoss))
                StatRow(label: "Total Commissions", value: String(format: "$%.2f", metrics.totalCommissions))
            }
            .padding()
        }
        .frame(width: 250)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct RecentTradesView: View {
    let trades: [Trade]
    
    var body: some View {
        GroupBox("Recent Trades") {
            if trades.isEmpty {
                Text("No trades found for selected period")
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            } else {
                Table(trades) {
                    TableColumn("Symbol") { trade in
                        Text(trade.symbol)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Side") { trade in
                        Text(trade.side.uppercased())
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(trade.side == "buy" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                            .foregroundColor(trade.side == "buy" ? .green : .red)
                            .cornerRadius(4)
                    }
                    .width(min: 60, ideal: 80)
                    
                    TableColumn("Quantity") { trade in
                        Text(String(format: "%.0f", trade.quantity))
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Price") { trade in
                        Text(String(format: "$%.2f", trade.price))
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Time") { trade in
                        Text(formatTimestamp(trade.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Commission") { trade in
                        Text(String(format: "$%.2f", trade.commission ?? 0))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100)
                }
                .frame(minHeight: 200)
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, HH:mm"
            return displayFormatter.string(from: date)
        }
        
        return timestamp
    }
}

private func calculateMetrics(from trades: [Trade]) -> PerformanceMetrics {
    // Group trades by symbol to calculate P&L
    var positions: [String: (quantity: Double, totalCost: Double)] = [:]
    var completedTrades: [(pnl: Double, commission: Double)] = []
    
    for trade in trades.sorted(by: { $0.timestamp < $1.timestamp }) {
        let symbol = trade.symbol
        let isBuy = trade.side == "buy"
        let quantity = isBuy ? trade.quantity : -trade.quantity
        let cost = trade.quantity * trade.price
        
        if let existingPosition = positions[symbol] {
            if (existingPosition.quantity > 0 && !isBuy) || (existingPosition.quantity < 0 && isBuy) {
                // Closing or reducing position
                let closeQuantity = min(abs(quantity), abs(existingPosition.quantity))
                let avgCost = existingPosition.totalCost / abs(existingPosition.quantity)
                let pnl = isBuy ? (avgCost - trade.price) * closeQuantity : (trade.price - avgCost) * closeQuantity
                
                completedTrades.append((pnl: pnl, commission: trade.commission ?? 0))
                
                // Update position
                let remainingQuantity = existingPosition.quantity + quantity
                if remainingQuantity == 0 {
                    positions.removeValue(forKey: symbol)
                } else {
                    let remainingCost = (abs(existingPosition.quantity) - closeQuantity) * avgCost
                    positions[symbol] = (quantity: remainingQuantity, totalCost: remainingCost)
                }
            } else {
                // Adding to position
                positions[symbol] = (
                    quantity: existingPosition.quantity + quantity,
                    totalCost: existingPosition.totalCost + cost
                )
            }
        } else {
            // New position
            positions[symbol] = (quantity: quantity, totalCost: cost)
        }
    }
    
    let totalPnL = completedTrades.reduce(0) { $0 + $1.pnl }
    let totalCommissions = completedTrades.reduce(0) { $0 + $1.commission }
    let winningTrades = completedTrades.filter { $0.pnl > 0 }
    let losingTrades = completedTrades.filter { $0.pnl < 0 }
    
    let winRate = completedTrades.isEmpty ? 0 : Double(winningTrades.count) / Double(completedTrades.count) * 100
    let averageWin = winningTrades.isEmpty ? 0 : winningTrades.reduce(0) { $0 + $1.pnl } / Double(winningTrades.count)
    let averageLoss = losingTrades.isEmpty ? 0 : abs(losingTrades.reduce(0) { $0 + $1.pnl } / Double(losingTrades.count))
    let profitFactor = averageLoss == 0 ? 0 : averageWin / averageLoss
    
    return PerformanceMetrics(
        totalPnL: totalPnL - totalCommissions,
        totalPnLPercent: 0, // Would need account value to calculate
        winRate: winRate,
        averageWin: averageWin,
        averageLoss: averageLoss,
        profitFactor: profitFactor,
        totalTrades: completedTrades.count,
        winningTrades: winningTrades.count,
        losingTrades: losingTrades.count,
        totalCommissions: totalCommissions
    )
}