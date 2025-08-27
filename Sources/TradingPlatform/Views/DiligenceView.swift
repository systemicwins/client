import SwiftUI
import Charts

struct DiligenceView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var secService = SECFilingsService.shared
    @StateObject private var secFilingService = SECFilingService.shared
    @StateObject private var secbertService = SECBERTService.shared
    // Float history now handled by TradeableFloatChart component
    @State private var secFilings: [SECFiling] = []
    @State private var isLoadingFilings = false
    @State private var currentStockSymbol: String = ""
    
    // SEC filing fetch progress
    @State private var totalFilingsToFetch = 0
    @State private var filingsFetched = 0
    @State private var isPerformingInference = false
    @State private var secbertAnalysis: SECBERTService.AnalysisResult?
    
    // Cache for SEC filings per stock  
    @State private var secFilingsCache: [String: [SECFiling]] = [:]
    
    // Time range for the chart
    @State private var selectedTimeRange = TimeRange.week
    
    enum TimeRange: String, CaseIterable {
        case week = "1W"
        case month = "1M"
        case threeMonths = "3M"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                Text("Due Diligence")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Time range selector
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if let stock = appState.selectedStock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Stock info header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stock.symbol)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(stock.name)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(formatCurrency(stock.currentPrice ?? stock.previousClose))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                HStack(spacing: 4) {
                                    Text(formatChange(stock.changeAmount))
                                    Text("(\(formatPercentage(stock.changePercent)))")
                                }
                                .font(.subheadline)
                                .foregroundColor(stock.isPositive ? .green : .red)
                            }
                            
                            // Trade button to navigate to Trade view
                            Button(action: {
                                appState.selectedTab = .scannerTrade
                            }) {
                                Label("Trade", systemImage: "arrow.left.arrow.right.circle.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        
                        // Tradeable Float Chart - Using the proper component
                        if let stock = appState.selectedStock {
                            TradeableFloatChart(symbol: stock.symbol)
                                .frame(minHeight: 300)
                        } else {
                            VStack {
                                Image(systemName: "chart.line.downtrend.xyaxis")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No stock selected")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                        }
                        
                        // Loading indicator - show when stock is selected but no data yet
                        if appState.selectedStock != nil && secFilings.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                                Text("Loading SEC filings...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                        
                        // Three-column layout - only show after SEC filings are fetched
                        else if !secFilings.isEmpty && secbertAnalysis != nil {
                            HStack {
                                Spacer()
                                
                                // Three equal columns with vertical centering
                                HStack(alignment: .center, spacing: 20) {
                                    // Column 1: Latest SEC Filings
                                    VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.blue)
                                    Text("Latest SEC Filings")
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    if !secFilings.isEmpty {
                                        Text("\(secFilings.count) total")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Text("Recent filings from the past 5 years:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // List of recent filings
                                VStack(alignment: .leading, spacing: 8) {
                                    if secFilings.isEmpty {
                                        Text("No SEC filings available")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    } else {
                                        ForEach(getRecentSECFilingDescriptions(), id: \.self) { filing in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(colorForFilingDescription(filing))
                                                    .frame(width: 6, height: 6)
                                                    .offset(y: 6)
                                                
                                                Text(filing)
                                                    .font(.caption)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Spacer() // Push content to top
                            }
                                    .padding()
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(8)
                                    .frame(width: 280, alignment: .top)
                                    
                                    // Column 2: Key Insights
                                    if let result = secbertAnalysis, !result.insights.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Image(systemName: "lightbulb.fill")
                                                    .foregroundColor(.yellow)
                                                Text("Key Insights")
                                                    .font(.headline)
                                                Spacer()
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 8) {
                                                ForEach(Array(result.insights.prefix(5).enumerated()), id: \.offset) { _, insight in
                                                    HStack(alignment: .top, spacing: 6) {
                                                        Text("•")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        Text(insight)
                                                            .font(.caption)
                                                            .foregroundColor(.primary)
                                                            .fixedSize(horizontal: false, vertical: true)
                                                    }
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(8)
                                        .frame(width: 280, alignment: .top)
                                    }
                                    
                                    // Column 3: AI Financial Health Analysis
                                    if let result = secbertAnalysis {
                                        VStack(spacing: 12) {
                                            HStack {
                                                Image(systemName: "brain")
                                                    .foregroundColor(.purple)
                                                Text("AI Financial Health")
                                                    .font(.headline)
                                                Spacer()
                                            }
                                            
                                            // Health score display
                                            HStack(spacing: 16) {
                                                ZStack {
                                                    Circle()
                                                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                                        .frame(width: 80, height: 80)
                                                    
                                                    Circle()
                                                        .trim(from: 0, to: result.healthScore / 100)
                                                        .stroke(
                                                            colorForScore(result.healthScore),
                                                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                                        )
                                                        .frame(width: 80, height: 80)
                                                        .rotationEffect(.degrees(-90))
                                                        .animation(.easeInOut(duration: 0.5), value: result.healthScore)
                                                    
                                                    VStack(spacing: 0) {
                                                        Text("\(Int(result.healthScore))")
                                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                                        Text("%")
                                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(result.label)
                                                        .font(.headline)
                                                        .foregroundColor(colorForScore(result.healthScore))
                                                    
                                                    Text("Company Health")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                    
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "shield.checkered")
                                                            .font(.caption)
                                                        Text("Confidence: \(Int(result.confidence * 100))%")
                                                            .font(.caption)
                                                    }
                                                    .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(8)
                                        .frame(width: 280, alignment: .top)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        
                        // Legacy AI Analysis Section (hidden)
                        if false {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "brain")
                                    .foregroundColor(.purple)
                                Text("AI Analysis")
                                    .font(.headline)
                                
                                Spacer()
                                
                                if isLoadingFilings {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if !secFilings.isEmpty {
                                    Text("\(secFilings.count) filings analyzed")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(4)
                                } else {
                                    Text("No filings")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            
                            if isLoadingFilings {
                                VStack(spacing: 12) {
                                    if totalFilingsToFetch > 0 {
                                        // Show fetch progress
                                        VStack(spacing: 8) {
                                            HStack {
                                                Image(systemName: "doc.text.magnifyingglass")
                                                    .font(.system(size: 14))
                                                Text("Fetching SEC filings...")
                                                    .font(.subheadline)
                                            }
                                            
                                            ProgressView(value: Double(filingsFetched), total: Double(totalFilingsToFetch))
                                                .progressViewStyle(.linear)
                                                .frame(width: 250)
                                            
                                            Text("\(filingsFetched) of \(totalFilingsToFetch) filings fetched")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        // Initial loading
                                        ProgressView("Discovering SEC filings...")
                                        Text("Analyzing up to 5 years of filings")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            } else if isPerformingInference {
                                VStack(spacing: 12) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.9)
                                        Text("Performing inference...")
                                            .font(.subheadline)
                                    }
                                    Text("Analyzing \(secFilings.count) SEC filings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            } else if !secFilings.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Financial Health Score: Coming Soon")
                                        .font(.subheadline)
                                    Text("Based on \(secFilings.count) SEC filings from the past \(getFilingPeriodDescription())")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Show filing types breakdown
                                    HStack(spacing: 12) {
                                        ForEach(getFilingTypesSummary(), id: \.type) { summary in
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(colorForFilingType(summary.type))
                                                    .frame(width: 8, height: 8)
                                                Text("\(summary.count) \(summary.type)")
                                                    .font(.caption2)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 12)
                            } else {
                                Text("No SEC filings available for analysis")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        } // End of hidden legacy section
                    }
                    .padding()
                }
            } else {
                // Empty state
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Select a stock to view diligence")
                        .font(.headline)
                        .padding(.top)
                    Text("Click on any stock in the scanner above")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let stock = appState.selectedStock {
                // TradeableFloatChart handles its own loading
                loadSECFilings(for: stock.symbol)
            }
        }
        .onChange(of: appState.selectedStock) { newStock in
            if let stock = newStock {
                // Only reload if it's a different stock
                if stock.symbol != currentStockSymbol {
                    // TradeableFloatChart handles its own loading
                    loadSECFilings(for: stock.symbol)
                    currentStockSymbol = stock.symbol
                }
            } else {
                // Clear data when no stock is selected
                secFilings = []
                currentStockSymbol = ""
            }
        }
        .onChange(of: selectedTimeRange) { _ in
            // TradeableFloatChart will handle time range changes internally
        }
    }
    
    
    // Load float history if needed (with caching) - DEPRECATED: Now handled by TradeableFloatChart
    /*
    private func loadFloatHistoryIfNeeded(for symbol: String) {
        // Update current stock symbol
        currentStockSymbol = symbol
        
        // Check cache first
        let cacheKey = "\(symbol)-\(selectedTimeRange.rawValue)"
        if let cachedData = floatHistoryCache[cacheKey] {
            // Use cached data
            self.floatHistory = cachedData
            return
        }
        
        // Load fresh data
        loadFloatHistory(for: symbol)
    }
    
    // Load float history from SEC filings - ACCURATE DATA WITH FORM 4
    private func loadFloatHistory(for symbol: String) {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // First try to get float history from SEC filings (includes Form 4)
                let floatHistory = try await secFilingService.getFloatHistory(for: symbol)
                
                if !floatHistory.isEmpty {
                    // Use accurate SEC filing data
                    await MainActor.run {
                        // Filter for selected time range
                        let cutoffDate = Calendar.current.date(byAdding: .day, 
                                                              value: -selectedTimeRange.days, 
                                                              to: Date()) ?? Date()
                        let filteredHistory = floatHistory.filter { $0.date >= cutoffDate }
                        
                        // Convert SECFloatDataPoint to FloatDataPoint
                        self.floatHistory = filteredHistory.map { secPoint in
                            FloatDataPoint(
                                date: secPoint.date,
                                floatShares: secPoint.tradeableFloat,
                                percentChange: secPoint.floatPercentage
                            )
                        }
                        
                        // Cache the data
                        let cacheKey = "\(symbol)-\(selectedTimeRange.rawValue)"
                        self.floatHistoryCache[cacheKey] = self.floatHistory
                        self.isLoading = false
                        self.errorMessage = nil
                    }
                } else {
                    // Fallback to backend API if no SEC data
                    let history = try await secService.fetchFloatHistory(
                        for: symbol,
                        days: selectedTimeRange.days
                    )
                    
                    await MainActor.run {
                        self.floatHistory = history
                        // Cache the data
                        let cacheKey = "\(symbol)-\(selectedTimeRange.rawValue)"
                        self.floatHistoryCache[cacheKey] = history
                        self.isLoading = false
                        self.errorMessage = nil
                    }
                }
            } catch {
                // Show error - NO MOCK DATA
                await MainActor.run {
                    self.floatHistory = []
                    self.isLoading = false
                    self.errorMessage = "Unable to fetch float data: \(error.localizedDescription)"
                    print("Float data error for \(symbol): \(error)")
                }
            }
        }
    }
    */
    
    // Find significant float changes - DEPRECATED: Now handled by TradeableFloatChart
    /*
    private func findSignificantFloatChange() -> String? {
        guard floatHistory.count > 1 else { return nil }
        
        let totalChange = floatHistory.last!.floatShares - floatHistory.first!.floatShares
        let percentChange = (totalChange / floatHistory.first!.floatShares) * 100
        
        if abs(percentChange) > 5 {
            return String(format: "Float %@ by %.1f%% this week - significant ownership change detected",
                         percentChange > 0 ? "increased" : "decreased",
                         abs(percentChange))
        } else if abs(percentChange) > 2 {
            return String(format: "Float %@ by %.1f%% this week - moderate ownership activity",
                         percentChange > 0 ? "increased" : "decreased",
                         abs(percentChange))
        }
        
        return nil
    }
    */
    
    // Get recent filing descriptions from actual data
    private func getRecentFilingDescriptions() -> [String] {
        // Now returns descriptions based on SEC filings directly
        guard !secFilings.isEmpty else {
            return ["No filing data available"]
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        
        var descriptions: [String] = []
        
        // Generate descriptions based on SEC filings
        for filing in secFilings.prefix(5) {
            let dateStr = dateFormatter.string(from: filing.filingDate)
            let formType = filing.formType
            descriptions.append("\(dateStr): Form \(formType) filed")
        }
        
        if descriptions.isEmpty {
            return ["No SEC filings available"]
        }
        
        return descriptions
    }
    
    // Formatting helpers
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
    private func formatChange(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
    }
    
    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 70...100:
            return .green
        case 40..<70:
            return .orange
        default:
            return .red
        }
    }
    
    // Load SEC filings using FMP API
    private func loadSECFilings(for symbol: String) {
        // Check cache first
        if let cachedFilings = secFilingsCache[symbol], !cachedFilings.isEmpty {
            self.secFilings = cachedFilings
            // Simulate inference phase for cached data
            performInference()
            return
        }
        
        isLoadingFilings = true
        filingsFetched = 0
        totalFilingsToFetch = 0
        
        Task {
            do {
                // First, get a count of available filings
                await MainActor.run {
                    // Estimate: typically 20-50 filings per year for active companies
                    self.totalFilingsToFetch = 30 // Will be updated with actual count
                }
                
                // Create a custom fetching mechanism with progress tracking
                let filings = try await fetchFilingsWithProgress(for: symbol, years: 5)
                
                await MainActor.run {
                    self.secFilings = filings
                    self.secFilingsCache[symbol] = filings
                    self.isLoadingFilings = false
                    
                    // Switch to inference phase
                    if !filings.isEmpty {
                        self.performInference()
                    }
                }
            } catch {
                await MainActor.run {
                    self.secFilings = []
                    self.isLoadingFilings = false
                    self.isPerformingInference = false
                    print("Failed to load SEC filings for \(symbol): \(error)")
                }
            }
        }
    }
    
    private func fetchFilingsWithProgress(for symbol: String, years: Int) async throws -> [SECFiling] {
        // Monitor the service's loading progress
        let progressTask = Task {
            while secFilingService.isLoading {
                await MainActor.run {
                    // Convert progress (0-1) to filing count estimate
                    let estimatedFilings = max(1, self.totalFilingsToFetch)
                    self.filingsFetched = Int(secFilingService.loadingProgress * Double(estimatedFilings))
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // Update every 100ms
            }
        }
        
        // Fetch the actual filings
        let filings = try await secFilingService.fetchHistoricalFilings(for: symbol, years: years)
        
        // Cancel progress monitoring
        progressTask.cancel()
        
        // Update with actual count
        await MainActor.run {
            self.totalFilingsToFetch = filings.count
            self.filingsFetched = filings.count
        }
        
        return filings
    }
    
    private func performInference() {
        isPerformingInference = true
        
        Task {
            do {
                // Perform actual SEC-BERT analysis
                let analysis = try await secbertService.analyzeSECFilings(secFilings)
                
                await MainActor.run {
                    self.secbertAnalysis = analysis
                    self.isPerformingInference = false
                }
            } catch {
                print("SEC-BERT analysis failed: \(error)")
                await MainActor.run {
                    self.isPerformingInference = false
                    // Could show error state here
                }
            }
        }
    }
    
    // Get filing period description based on actual data
    private func getFilingPeriodDescription() -> String {
        guard !secFilings.isEmpty else { return "unknown period" }
        
        let sortedFilings = secFilings.sorted(by: { $0.filingDate < $1.filingDate })
        guard let oldestFiling = sortedFilings.first,
              let newestFiling = sortedFilings.last else {
            return "unknown period"
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: oldestFiling.filingDate, to: newestFiling.filingDate)
        
        if let years = components.year, years > 0 {
            if years >= 5 {
                return "5 years"
            } else if years == 1 {
                return "1 year"
            } else {
                return "\(years) years"
            }
        } else if let months = components.month, months > 0 {
            if months == 1 {
                return "1 month"
            } else {
                return "\(months) months"
            }
        } else {
            return "recent period"
        }
    }
    
    // Get filing types summary
    private func getFilingTypesSummary() -> [(type: String, count: Int)] {
        var typeCounts: [String: Int] = [:]
        
        for filing in secFilings {
            typeCounts[filing.formType, default: 0] += 1
        }
        
        // Sort by count and take top filing types
        let sorted = typeCounts.sorted { $0.value > $1.value }
        return sorted.prefix(4).map { (type: $0.key, count: $0.value) }
    }
    
    // Get color for filing type
    private func colorForFilingType(_ type: String) -> Color {
        switch type {
        case "10-K":
            return .blue  // Annual report
        case "10-Q":
            return .green  // Quarterly report
        case "8-K":
            return .orange  // Current report
        case "DEF 14A":
            return .purple  // Proxy statement
        case "Form 4", "4":
            return .pink  // Insider trading
        case "13F-HR":
            return .teal  // Institutional holdings
        case "S-1", "S-8":
            return .indigo  // Registration statements
        case "3":
            return .brown  // Initial insider ownership
        default:
            return .gray
        }
    }
    
    // Get recent SEC filing descriptions
    private func getRecentSECFilingDescriptions() -> [String] {
        guard !secFilings.isEmpty else {
            return []
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        // Sort filings by date and take most recent
        let sortedFilings = secFilings.sorted(by: { $0.filingDate > $1.filingDate })
        let recentFilings = sortedFilings.prefix(5)
        
        var descriptions: [String] = []
        for filing in recentFilings {
            let dateStr = dateFormatter.string(from: filing.filingDate)
            let formType = filing.formType
            
            // Create descriptive text based on filing type
            let description: String
            switch formType {
            case "10-K":
                description = "\(dateStr): Annual Report (10-K)"
            case "10-Q":
                description = "\(dateStr): Quarterly Report (10-Q)"
            case "8-K":
                description = "\(dateStr): Current Report (8-K)"
            case "DEF 14A":
                description = "\(dateStr): Proxy Statement (DEF 14A)"
            case "4":
                description = "\(dateStr): Insider Trading (Form 4)"
            case "3":
                description = "\(dateStr): Initial Insider Ownership (Form 3)"
            case "S-1":
                description = "\(dateStr): Registration Statement (S-1)"
            case "S-8":
                description = "\(dateStr): Employee Stock Plan (S-8)"
            default:
                description = "\(dateStr): \(formType) Filing"
            }
            
            descriptions.append(description)
        }
        
        if descriptions.isEmpty {
            return ["No SEC filings in the past 5 years"]
        }
        
        return descriptions
    }
    
    // Get color for filing description
    private func colorForFilingDescription(_ description: String) -> Color {
        if description.contains("10-K") || description.contains("Annual") {
            return .blue
        } else if description.contains("10-Q") || description.contains("Quarterly") {
            return .green
        } else if description.contains("8-K") || description.contains("Current") {
            return .orange
        } else if description.contains("Form 4") || description.contains("Insider Trading") {
            return .pink
        } else if description.contains("Form 3") || description.contains("Initial Insider") {
            return .brown
        } else if description.contains("S-1") || description.contains("S-8") || description.contains("Registration") {
            return .indigo
        } else if description.contains("DEF 14A") || description.contains("Proxy") {
            return .purple
        } else {
            return .gray
        }
    }
}

// MARK: - Float History Chart

struct FloatHistoryChart: View {
    let dataPoints: [FloatDataPoint]
    let timeRange: DiligenceView.TimeRange
    
    var body: some View {
        Chart(dataPoints) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Float", point.floatShares)
            )
            .foregroundStyle(.purple)
            .lineStyle(StrokeStyle(lineWidth: 2))
            
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Float", point.floatShares)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.purple.opacity(0.3), .purple.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: timeRange == .week ? 1 : 7)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let floatValue = value.as(Double.self) {
                        Text(formatFloat(floatValue))
                    }
                }
            }
        }
        .chartYScale(domain: yAxisDomain)
        .animation(.easeInOut, value: dataPoints)
    }
    
    private var yAxisDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.floatShares }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1000000
        let padding = (maxValue - minValue) * 0.1
        return (minValue - padding)...(maxValue + padding)
    }
    
    private func formatFloat(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Data Models

struct FloatDataPoint: Identifiable, Equatable, Codable {
    let id: UUID
    let date: Date
    let floatShares: Double
    let percentChange: Double
    let filings: [String]? // Optional filings array from API
    
    enum CodingKeys: String, CodingKey {
        case date
        case floatShares = "float_shares"
        case percentChange = "percent_change"
        case filings
    }
    
    init(date: Date, floatShares: Double, percentChange: Double) {
        self.id = UUID()
        self.date = date
        self.floatShares = floatShares
        self.percentChange = percentChange
        self.filings = nil
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.date = try container.decode(Date.self, forKey: .date)
        self.floatShares = try container.decode(Double.self, forKey: .floatShares)
        self.percentChange = try container.decode(Double.self, forKey: .percentChange)
        self.filings = try container.decodeIfPresent([String].self, forKey: .filings)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(floatShares, forKey: .floatShares)
        try container.encode(percentChange, forKey: .percentChange)
        try container.encodeIfPresent(filings, forKey: .filings)
    }
}

// MARK: - Preview

struct DiligenceView_Previews: PreviewProvider {
    static var previews: some View {
        DiligenceView()
            .environmentObject(AppState())
            .frame(width: 400, height: 600)
    }
}