import SwiftUI
import Charts

struct PerformanceView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedPeriod = "1M"
    @State private var selectedChart = ChartType.portfolioValue
    
    let periods = ["1D", "1W", "1M", "3M", "6M", "1Y", "ALL"]
    
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
                // Header
                HStack {
                    Text("Performance Analytics")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Period selector
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(periods, id: \.self) { period in
                            Text(period).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 400)
                }
                .padding(.horizontal)
                
                // Performance summary cards
                PerformanceSummaryView(metrics: performanceMetrics)
                    .padding(.horizontal)
                
                // Chart section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Performance Charts")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Picker("Chart Type", selection: $selectedChart) {
                            ForEach(ChartType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                    
                    // Performance chart
                    PerformanceChartView(chartType: selectedChart, data: tradingManager.performanceData)
                        .frame(height: 400)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 20) {
                    // Statistics
                    PerformanceStatsView(metrics: performanceMetrics)
                    
                    // Distribution charts
                    PerformanceDistributionView(data: tradingManager.performanceData)
                }
                .padding(.horizontal)
            }
        }
        .refreshable {
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

struct PerformanceMetrics {
    let totalReturn: Double
    let totalReturnPercent: Double
    let annualizedReturn: Double
    let volatility: Double
    let sharpeRatio: Double
    let maxDrawdown: Double
    let winRate: Double
    let profitFactor: Double
    let avgWin: Double
    let avgLoss: Double
    let totalTrades: Int
    let winningTrades: Int
    let losingTrades: Int
}

struct PerformanceSummaryView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            PerformanceCard(
                title: "Total Return",
                value: formatCurrency(metrics.totalReturn),
                subtitle: formatPercentage(metrics.totalReturnPercent),
                color: metrics.totalReturn >= 0 ? .green : .red
            )
            
            PerformanceCard(
                title: "Win Rate",
                value: formatPercentage(metrics.winRate),
                subtitle: "\(metrics.winningTrades)/\(metrics.totalTrades) trades",
                color: metrics.winRate >= 50 ? .green : .red
            )
            
            PerformanceCard(
                title: "Sharpe Ratio",
                value: String(format: "%.2f", metrics.sharpeRatio),
                subtitle: "Risk-adjusted return",
                color: metrics.sharpeRatio >= 1.0 ? .green : .orange
            )
            
            PerformanceCard(
                title: "Max Drawdown",
                value: formatPercentage(metrics.maxDrawdown),
                subtitle: "Peak to trough",
                color: .red
            )
        }
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

struct PerformanceCard: View {
    let title: String
    let value: String
    let subtitle: String
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
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct PerformanceChartView: View {
    let chartType: PerformanceView.ChartType
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
                .lineStyle(StrokeStyle(lineWidth: 2))
                
                AreaMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Portfolio Value", dataPoint.portfolioValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
            case .dailyPnL:
                BarMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Daily P&L", dataPoint.dailyPnL)
                )
                .foregroundStyle(dataPoint.dailyPnL >= 0 ? .green : .red)
                
            case .cumulativePnL:
                LineMark(
                    x: .value("Date", dataPoint.date),
                    y: .value("Cumulative P&L", dataPoint.cumulativePnL)
                )
                .foregroundStyle(LinearGradient(
                    colors: [.green, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                AxisGridLine()
                AxisTick()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if chartType == .portfolioValue {
                    AxisValueLabel(format: .currency(code: "USD"))
                } else {
                    AxisValueLabel(format: .currency(code: "USD"))
                }
                AxisGridLine()
                AxisTick()
            }
        }
    }
}

struct PerformanceStatsView: View {
    let metrics: PerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                StatRow(label: "Total Trades", value: "\(metrics.totalTrades)")
                StatRow(label: "Winning Trades", value: "\(metrics.winningTrades)")
                StatRow(label: "Losing Trades", value: "\(metrics.losingTrades)")
                StatRow(label: "Win Rate", value: formatPercentage(metrics.winRate))
                
                Divider()
                
                StatRow(label: "Profit Factor", value: String(format: "%.2f", metrics.profitFactor))
                StatRow(label: "Average Win", value: formatCurrency(metrics.avgWin))
                StatRow(label: "Average Loss", value: formatCurrency(metrics.avgLoss))
                
                Divider()
                
                StatRow(label: "Annualized Return", value: formatPercentage(metrics.annualizedReturn))
                StatRow(label: "Volatility", value: formatPercentage(metrics.volatility))
                StatRow(label: "Sharpe Ratio", value: String(format: "%.2f", metrics.sharpeRatio))
                StatRow(label: "Max Drawdown", value: formatPercentage(metrics.maxDrawdown))
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .frame(width: 300)
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

struct PerformanceDistributionView: View {
    let data: [PerformanceData]
    
    var distributionData: [DistributionBucket] {
        let returns = data.map { $0.dailyPnL }
        let min = returns.min() ?? 0
        let max = returns.max() ?? 0
        let bucketSize = (max - min) / 10
        
        var buckets: [DistributionBucket] = []
        
        for i in 0..<10 {
            let start = min + Double(i) * bucketSize
            let end = min + Double(i + 1) * bucketSize
            let count = returns.filter { $0 >= start && $0 < end }.count
            
            buckets.append(DistributionBucket(
                range: "\(formatCurrency(start)) to \(formatCurrency(end))",
                count: count,
                midpoint: (start + end) / 2
            ))
        }
        
        return buckets
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily P&L Distribution")
                .font(.headline)
                .fontWeight(.semibold)
            
            Chart(distributionData, id: \.range) { bucket in
                BarMark(
                    x: .value("P&L Range", bucket.midpoint),
                    y: .value("Frequency", bucket.count)
                )
                .foregroundStyle(bucket.midpoint >= 0 ? .green : .red)
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .currency(code: "USD"))
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

struct DistributionBucket {
    let range: String
    let count: Int
    let midpoint: Double
}

