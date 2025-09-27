import SwiftUI
import Charts

struct UnifiedDashboardView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedTimeframe = "1M"
    @State private var selectedChart = ChartType.portfolioValue
    @State private var showDetailedStats = false
    
    let timeframes = ["1D", "1W", "1M", "3M", "6M", "1Y", "ALL"]
    
    enum ChartType: String, CaseIterable {
        case portfolioValue = "Portfolio Value"
        case dailyPnL = "Daily P&L"
        case cumulativePnL = "Cumulative P&L"
    }
    
    var performanceMetrics: PerformanceMetrics {
        calculatePerformanceMetrics()
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header with timeframe selector
                HStack {
                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Timeframe selector
                    Picker("Period", selection: $selectedTimeframe) {
                        ForEach(timeframes, id: \.self) { period in
                            Text(period).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 350)
                    
                    Button(action: { tradingManager.loadInitialData() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                // Key Metrics Cards - Combined from both views
                KeyMetricsView(metrics: performanceMetrics)
                    .environmentObject(tradingManager)
                
                // Main Chart Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Portfolio Performance")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Picker("Chart", selection: $selectedChart) {
                            ForEach(ChartType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        
                        Button(action: { withAnimation { showDetailedStats.toggle() } }) {
                            Image(systemName: showDetailedStats ? "chevron.up" : "chevron.down")
                            Text(showDetailedStats ? "Hide Stats" : "Show Stats")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Performance chart
                    UnifiedPerformanceChartView(chartType: selectedChart, data: tradingManager.performanceData)
                        .frame(height: 350)
                    
                    // Detailed statistics (collapsible)
                    if showDetailedStats {
                        DetailedStatsGrid(metrics: performanceMetrics)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Bottom Section: Positions and Activity
                HStack(alignment: .top, spacing: 20) {
                    // Top Positions
                    TopPositionsCard()
                        .environmentObject(tradingManager)
                    
                    // Trading Statistics
                    TradingStatsCard(metrics: performanceMetrics)
                }
                .padding(.horizontal)
            }
        }
        .refreshable {
            tradingManager.loadInitialData()
            tradingManager.loadPerformanceData()
        }
    }
    
    private func calculatePerformanceMetrics() -> PerformanceMetrics {
        let data = tradingManager.performanceData
        guard !data.isEmpty else {
            return PerformanceMetrics(
                totalReturn: 0, totalReturnPercent: 0, annualizedReturn: 0,
                volatility: 0, sharpeRatio: 0, maxDrawdown: 0,
                winRate: 0, profitFactor: 0, avgWin: 0, avgLoss: 0,
                totalTrades: 0, winningTrades: 0, losingTrades: 0
            )
        }
        
        let totalReturn = data.last!.cumulativePnL - data.first!.cumulativePnL
        let initialValue = data.first!.portfolioValue - data.first!.cumulativePnL
        let totalReturnPercent = initialValue > 0 ? (totalReturn / initialValue) * 100 : 0
        
        // Calculate daily returns for volatility and Sharpe ratio
        let dailyReturns = zip(data.dropFirst(), data).map { current, previous in
            let prevValue = previous.portfolioValue
            return prevValue > 0 ? (current.portfolioValue - prevValue) / prevValue : 0
        }
        
        let avgDailyReturn = dailyReturns.reduce(0, +) / Double(dailyReturns.count)
        let variance = dailyReturns.reduce(0) { sum, ret in
            sum + pow(ret - avgDailyReturn, 2)
        } / Double(dailyReturns.count)
        let volatility = sqrt(variance) * sqrt(252) * 100 // Annualized volatility
        
        let annualizedReturn = pow(1 + avgDailyReturn, 252) - 1
        let sharpeRatio = volatility > 0 ? (annualizedReturn * 100) / volatility : 0
        
        // Calculate max drawdown
        var peak = data.first!.portfolioValue
        var maxDrawdown = 0.0
        
        for point in data {
            peak = max(peak, point.portfolioValue)
            let drawdown = (peak - point.portfolioValue) / peak
            maxDrawdown = max(maxDrawdown, drawdown)
        }
        
        return PerformanceMetrics(
            totalReturn: totalReturn,
            totalReturnPercent: totalReturnPercent,
            annualizedReturn: annualizedReturn * 100,
            volatility: volatility,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown * 100,
            winRate: 65.0, // This would come from actual trade data
            profitFactor: 1.45, // This would come from actual trade data
            avgWin: 250.0, // This would come from actual trade data
            avgLoss: -180.0, // This would come from actual trade data
            totalTrades: 45, // This would come from actual trade data
            winningTrades: 29, // This would come from actual trade data
            losingTrades: 16 // This would come from actual trade data
        )
    }
}

// MARK: - Key Metrics View
struct KeyMetricsView: View {
    let metrics: PerformanceMetrics
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
            MetricCard(
                title: "Portfolio Value",
                value: formatCurrency(tradingManager.totalPortfolioValue),
                subtitle: nil,
                color: .blue,
                icon: "dollarsign.circle.fill"
            )
            
            MetricCard(
                title: "Total Return",
                value: formatCurrency(metrics.totalReturn),
                subtitle: formatPercentage(metrics.totalReturnPercent),
                color: metrics.totalReturn >= 0 ? .green : .red,
                icon: metrics.totalReturn >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
            )
            
            MetricCard(
                title: "Day P&L",
                value: formatCurrency(tradingManager.totalUnrealizedPnL),
                subtitle: formatPercentage(tradingManager.totalUnrealizedPnLPercent),
                color: tradingManager.totalUnrealizedPnL >= 0 ? .green : .red,
                icon: "calendar.circle.fill"
            )
            
            MetricCard(
                title: "Win Rate",
                value: formatPercentage(metrics.winRate),
                subtitle: "\(metrics.winningTrades)/\(metrics.totalTrades)",
                color: metrics.winRate >= 50 ? .green : .orange,
                icon: "percent"
            )
            
            MetricCard(
                title: "Positions",
                value: "\(tradingManager.positions.count)",
                subtitle: "\(tradingManager.positions.filter { $0.isProfit }.count) winning",
                color: .purple,
                icon: "chart.pie.fill"
            )
        }
        .padding(.horizontal)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        return String(format: "%.2f%%", value)
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(color.opacity(0.7))
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Detailed Stats Grid
struct DetailedStatsGrid: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            StatItem(label: "Sharpe Ratio", value: String(format: "%.2f", metrics.sharpeRatio))
            StatItem(label: "Max Drawdown", value: String(format: "%.2f%%", metrics.maxDrawdown))
            StatItem(label: "Volatility", value: String(format: "%.2f%%", metrics.volatility))
            StatItem(label: "Profit Factor", value: String(format: "%.2f", metrics.profitFactor))
            StatItem(label: "Avg Win", value: formatCurrency(metrics.avgWin))
            StatItem(label: "Avg Loss", value: formatCurrency(metrics.avgLoss))
            StatItem(label: "Win Trades", value: "\(metrics.winningTrades)")
            StatItem(label: "Loss Trades", value: "\(metrics.losingTrades)")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

// MARK: - Top Positions Card
struct TopPositionsCard: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var topPositions: [Position] {
        Array(tradingManager.positions
            .sorted { abs($0.unrealizedPnL) > abs($1.unrealizedPnL) }
            .prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Top Positions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(tradingManager.positions.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if topPositions.isEmpty {
                Text("No open positions")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(topPositions) { position in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(position.symbol)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                Text("\(Int(position.quantity)) shares")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCurrency(position.unrealizedPnL))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(position.isProfit ? .green : .red)
                                Text(formatPercentage(position.unrealizedPnLPercent))
                                    .font(.caption)
                                    .foregroundColor(position.isProfit ? .green : .red)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if position.id != topPositions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        return String(format: "%+.2f%%", value)
    }
}

// MARK: - Trading Stats Card
struct TradingStatsCard: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trading Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                DashboardStatRow(label: "Total Trades", value: "\(metrics.totalTrades)")
                Divider()
                DashboardStatRow(label: "Win Rate", value: String(format: "%.1f%%", metrics.winRate))
                Divider()
                DashboardStatRow(label: "Profit Factor", value: String(format: "%.2f", metrics.profitFactor))
                Divider()
                DashboardStatRow(label: "Average Win", value: formatCurrency(metrics.avgWin), color: Color.green)
                Divider()
                DashboardStatRow(label: "Average Loss", value: formatCurrency(metrics.avgLoss), color: Color.red)
                Divider()
                DashboardStatRow(label: "Best Day", value: formatCurrency(1250.00), color: Color.green)
                Divider()
                DashboardStatRow(label: "Worst Day", value: formatCurrency(-850.00), color: Color.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

struct DashboardStatRow: View {
    let label: String
    let value: String
    var color: Color
    
    init(label: String, value: String, color: Color = .primary) {
        self.label = label
        self.value = value
        self.color = color
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Performance Chart View
struct UnifiedPerformanceChartView: View {
    let chartType: UnifiedDashboardView.ChartType
    let data: [PerformanceData]
    
    var body: some View {
        Chart(data) { dataPoint in
            switch chartType {
            case .portfolioValue:
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Portfolio Value", dataPoint.portfolioValue)
                )
                .foregroundStyle(.blue)
                
            case .dailyPnL:
                BarMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Daily P&L", dataPoint.dailyPnL)
                )
                .foregroundStyle(dataPoint.dailyPnL >= 0 ? .green : .red)
                
            case .cumulativePnL:
                AreaMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Cumulative P&L", dataPoint.cumulativePnL)
                )
                .foregroundStyle(.blue.gradient.opacity(0.3))
                
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Cumulative P&L", dataPoint.cumulativePnL)
                )
                .foregroundStyle(.blue)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}