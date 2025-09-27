import SwiftUI
import Charts

struct TradeableFloatChart: View {
    let symbol: String
    @StateObject private var secService = SECFilingService.shared
    @State private var floatHistory: [SECFloatDataPoint] = []
    @State private var isLoading = true
    @State private var isLoadingRealData = false
    @State private var selectedDataPoint: SECFloatDataPoint?
    @State private var showFilingDetails = false
    @State private var hasEstimatedData = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tradeable Float History")
                        .font(.headline)
                    Text(periodDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isLoadingRealData {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Refining with SEC data...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        if hasEstimatedData {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .help("Using estimated data")
                        }
                        Button(action: refreshData) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Chart
            if hasMinimumData {
                Chart(floatHistory) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Float", dataPoint.tradeableFloat / 1_000_000)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    PointMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Float", dataPoint.tradeableFloat / 1_000_000)
                    )
                    .foregroundStyle(colorForSource(dataPoint.source))
                    .symbolSize(60)
                    
                    if let selected = selectedDataPoint, selected.id == dataPoint.id {
                        RuleMark(x: .value("Date", dataPoint.date))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .frame(height: 200)
                .chartYAxisLabel("Tradeable Float (M shares)")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: getDesiredAxisCount())) { value in
                        AxisGridLine()
                        AxisValueLabel(format: getAxisDateFormat())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let floatValue = value.as(Double.self) {
                                Text("\(Int(floatValue))M")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let selected = selectedDataPoint {
                        floatTooltip(for: selected)
                            .padding(8)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                            .padding()
                    }
                }
                .onTapGesture { location in
                    // Handle tap to show details
                    handleChartTap(at: location)
                }
            } else if isLoading {
                VStack {
                    ProgressView("Loading SEC filings...")
                    if secService.loadingProgress > 0 {
                        ProgressView(value: secService.loadingProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            } else if !floatHistory.isEmpty && !hasMinimumData {
                // Have some data but not enough for a chart
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Limited Filing History")
                        .font(.headline)
                    Text("Only \(floatHistory.count) filing\(floatHistory.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let dataPoint = floatHistory.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest Float: \(formatShares(dataPoint.tradeableFloat))")
                            Text("Date: \(dataPoint.date, format: .dateTime.year().month())")
                            Text("Source: \(dataPoint.source)")
                        }
                        .font(.caption)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Float Data Available")
                        .font(.headline)
                    Text("Data points: \(floatHistory.count), Loading: \(isLoading ? "Yes" : "No")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if floatHistory.isEmpty && !isLoading {
                        Button("Retry Loading") {
                            loadFloatHistory()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            }
            
            // Summary Statistics
            if !floatHistory.isEmpty {
                HStack(spacing: 20) {
                    FloatStatItem(
                        label: "Current Float",
                        value: formatShares(floatHistory.last?.tradeableFloat ?? 0)
                    )
                    
                    FloatStatItem(
                        label: "Change (1Y)",
                        value: formatFloatChange(yearOverYear: true)
                    )
                    
                    FloatStatItem(
                        label: "Avg Float %",
                        value: formatPercentage(averageFloatPercentage())
                    )
                    
                    FloatStatItem(
                        label: "Filings",
                        value: "\(floatHistory.count)"
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            loadFloatHistory()
        }
        .sheet(isPresented: $showFilingDetails) {
            if let selected = selectedDataPoint {
                FilingDetailsSheet(dataPoint: selected, symbol: symbol)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var periodDescription: String {
        guard !floatHistory.isEmpty else {
            return "SEC Filing Analysis"
        }
        
        let firstDate = floatHistory.first?.date ?? Date()
        let lastDate = floatHistory.last?.date ?? Date()
        let years = Calendar.current.dateComponents([.year], from: firstDate, to: lastDate).year ?? 0
        let months = Calendar.current.dateComponents([.month], from: firstDate, to: lastDate).month ?? 0
        
        if years >= 5 {
            return "Past 5 Years of SEC Filings"
        } else if years > 1 {
            return "Past \(years) Years of SEC Filings"
        } else if years == 1 {
            return "Past Year of SEC Filings"
        } else if months > 1 {
            return "Past \(months) Months of SEC Filings"
        } else {
            return "Available SEC Filings"
        }
    }
    
    private var hasMinimumData: Bool {
        // Need at least 2 data points to show a meaningful chart
        return floatHistory.count >= 2
    }
    
    // MARK: - Helper Methods
    
    private func loadFloatHistory() {
        Task {
            isLoading = true
            do {
                // Phase 1: Load estimated data quickly
                let estimatedHistory = try await secService.fetchHistoricalTradeableFloat(
                    for: symbol, 
                    years: 2,  // At least 2 years for meaningful chart
                    quickEstimate: true
                )
                
                await MainActor.run {
                    print("TradeableFloatChart: Received \(estimatedHistory.count) estimated data points")
                    self.floatHistory = estimatedHistory
                    self.isLoading = false
                    self.isLoadingRealData = true
                    self.hasEstimatedData = true
                }
                
                // Phase 2: Load real SEC data in background
                let realHistory = try await secService.fetchHistoricalTradeableFloat(
                    for: symbol, 
                    years: 5, 
                    quickEstimate: false
                )
                
                await MainActor.run {
                    print("TradeableFloatChart: Received \(realHistory.count) real data points")
                    // Only update if we got better data
                    if !realHistory.isEmpty {
                        self.floatHistory = realHistory
                        self.hasEstimatedData = realHistory.first?.source.contains("Estimated") ?? false
                    }
                    self.isLoadingRealData = false
                }
            } catch {
                print("Error loading float history: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingRealData = false
                }
            }
        }
    }
    
    private func refreshData() {
        secService.clearCache(for: symbol)
        loadFloatHistory()
    }
    
    private func colorForSource(_ source: String) -> Color {
        switch source {
        case "10-K": return .blue
        case "10-Q": return .green
        case "8-K": return .orange
        case "DEF 14A": return .purple
        default: return .gray
        }
    }
    
    private func floatTooltip(for dataPoint: SECFloatDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dataPoint.date, format: .dateTime.year().month().day())
                .font(.caption.bold())
                .foregroundColor(.white)
            
            Text("Float: \(formatShares(dataPoint.tradeableFloat))")
                .font(.caption)
                .foregroundColor(.white)
            
            Text("Source: \(dataPoint.source)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            Text("\(dataPoint.floatPercentage, specifier: "%.1f")% of total")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func handleChartTap(at location: CGPoint) {
        // Simple implementation - in production would calculate nearest point
        selectedDataPoint = floatHistory.randomElement()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            selectedDataPoint = nil
        }
    }
    
    private func formatShares(_ shares: Double) -> String {
        if shares >= 1_000_000_000 {
            return String(format: "%.2fB", shares / 1_000_000_000)
        } else if shares >= 1_000_000 {
            return String(format: "%.2fM", shares / 1_000_000)
        } else if shares >= 1_000 {
            return String(format: "%.2fK", shares / 1_000)
        } else {
            return String(format: "%.0f", shares)
        }
    }
    
    private func formatFloatChange(yearOverYear: Bool) -> String {
        guard floatHistory.count >= 2 else { return "N/A" }
        
        let current = floatHistory.last?.tradeableFloat ?? 0
        let comparison: Double
        
        if yearOverYear {
            let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
            comparison = floatHistory.last(where: { $0.date <= oneYearAgo })?.tradeableFloat ?? floatHistory.first?.tradeableFloat ?? 0
        } else {
            comparison = floatHistory.first?.tradeableFloat ?? 0
        }
        
        guard comparison > 0 else { return "N/A" }
        
        let change = ((current - comparison) / comparison) * 100
        let sign = change >= 0 ? "+" : ""
        
        return "\(sign)\(String(format: "%.1f", change))%"
    }
    
    private func averageFloatPercentage() -> Double {
        guard !floatHistory.isEmpty else { return 0 }
        let sum = floatHistory.reduce(0) { $0 + $1.floatPercentage }
        return sum / Double(floatHistory.count)
    }
    
    private func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value)
    }
    
    private func getDesiredAxisCount() -> Int {
        guard !floatHistory.isEmpty else { return 5 }
        
        let firstDate = floatHistory.first?.date ?? Date()
        let lastDate = floatHistory.last?.date ?? Date()
        let months = Calendar.current.dateComponents([.month], from: firstDate, to: lastDate).month ?? 0
        
        if months > 36 {
            return 5  // Show 5 marks for > 3 years
        } else if months > 12 {
            return 4  // Show 4 marks for 1-3 years
        } else if months > 6 {
            return 3  // Show 3 marks for 6-12 months
        } else {
            return min(floatHistory.count, 3)  // Show up to 3 marks for < 6 months
        }
    }
    
    private func getAxisDateFormat() -> Date.FormatStyle {
        guard !floatHistory.isEmpty else {
            return .dateTime.year().month(.abbreviated)
        }
        
        let firstDate = floatHistory.first?.date ?? Date()
        let lastDate = floatHistory.last?.date ?? Date()
        let months = Calendar.current.dateComponents([.month], from: firstDate, to: lastDate).month ?? 0
        
        if months > 12 {
            return .dateTime.year().month(.abbreviated)
        } else if months > 3 {
            return .dateTime.month(.abbreviated).day()
        } else {
            return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Supporting Views

struct FloatStatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

struct FilingDetailsSheet: View {
    let dataPoint: SECFloatDataPoint
    let symbol: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Filing Information") {
                    LabeledContent("Date", value: dataPoint.date.formatted())
                    LabeledContent("Form Type", value: dataPoint.source)
                    LabeledContent("Symbol", value: symbol)
                }
                
                Section("Share Structure") {
                    LabeledContent("Total Shares", value: formatNumber(dataPoint.totalShares))
                    LabeledContent("Institutional", value: formatNumber(dataPoint.institutionalOwnership))
                    LabeledContent("Insider", value: formatNumber(dataPoint.insiderOwnership))
                    LabeledContent("Tradeable Float", value: formatNumber(dataPoint.tradeableFloat))
                    LabeledContent("Float %", value: String(format: "%.2f%%", dataPoint.floatPercentage))
                }
            }
            .navigationTitle("SEC Filing Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}