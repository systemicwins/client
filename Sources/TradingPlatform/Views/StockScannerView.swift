import SwiftUI
import Charts

struct StockScannerView: View {
    @EnvironmentObject var scannerManager: StockScannerManager
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = "filtered"
    @State private var searchText = ""
    @State private var sortBy: SortOption = .changePercent
    @State private var sortAscending = false
    @State private var selectedStock: FilteredStock?
    @State private var showingStockDetail = false
    @State private var showDiligence = true
    
    enum SortOption: String, CaseIterable {
        case symbol = "Symbol"
        case changePercent = "% Change"
        case volume = "Volume"
        case price = "Price"
        case float = "Float"
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Header
                HeaderView()
                .environmentObject(scannerManager)
            
            if scannerManager.isLoading {
                ProgressView("Loading Stocks...")
                    .progressViewStyle(.linear)
                    .padding()
            } else if let error = scannerManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                // Summary Cards
                if let summary = scannerManager.scannerSummary {
                    SummaryCardsView(summary: summary)
                        .padding()
                }
                
                // Tab Selection
                TabSelectorView(selectedTab: $selectedTab)
                    .padding(.horizontal)
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case "filtered":
                        FilteredStocksView(
                            stocks: sortedAndFilteredStocks,
                            searchText: $searchText,
                            sortBy: $sortBy,
                            sortAscending: $sortAscending,
                            selectedStock: $selectedStock,
                            showingStockDetail: $showingStockDetail
                        )
                        
                    case "gainers":
                        StockListView(
                            title: "Top Gainers",
                            stocks: scannerManager.topGainers,
                            showFloat: false,
                            selectedStock: $selectedStock,
                            showingStockDetail: $showingStockDetail
                        )
                        
                    case "losers":
                        StockListView(
                            title: "Top Losers",
                            stocks: scannerManager.topLosers,
                            showFloat: false,
                            selectedStock: $selectedStock,
                            showingStockDetail: $showingStockDetail
                        )
                        
                    case "active":
                        StockListView(
                            title: "Most Active",
                            stocks: scannerManager.mostActive,
                            showFloat: false,
                            selectedStock: $selectedStock,
                            showingStockDetail: $showingStockDetail
                        )
                        
                    default:
                        EmptyView()
                    }
                }
                
                // Enhanced progress bar for batch loading
                if scannerManager.isLoading {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fetching Stocks in Batches")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("Loading stocks...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(scannerManager.filteredStocks.count) stocks loaded")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("~1000 per batch")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        ProgressView()
                            .progressViewStyle(.linear)
                            .accentColor(.blue)
                        
                        HStack {
                            Text("ETA: \(estimatedTimeRemaining)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if scannerManager.isLoading {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .progressViewStyle(.circular)
                                    Text("Fetching...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Status Bar
                StatusBarView(
                    isConnected: scannerManager.isConnected,
                    lastUpdate: scannerManager.lastUpdate,
                    stockCount: scannerManager.filteredStocks.count
                )
            }
        }
        .onAppear {
            // Only load if we don't have data yet (scanner runs continuously in background)
            if scannerManager.filteredStocks.isEmpty && !scannerManager.isLoading {
                print("StockScannerView appeared, no data available, loading filtered stocks...")
                scannerManager.loadFilteredStocks()
                scannerManager.loadScannerSummary()
            } else {
                print("StockScannerView appeared, using existing data: \(scannerManager.filteredStocks.count) stocks")
            }
        }
        .alert("Error", isPresented: .constant(scannerManager.errorMessage != nil)) {
            Button("OK") {
                scannerManager.errorMessage = nil
            }
        } message: {
            Text(scannerManager.errorMessage ?? "")
        }
        .sheet(isPresented: $showingStockDetail) {
            if let stock = selectedStock {
                StockDetailView(stock: stock)
                    .frame(minWidth: 1200, minHeight: 800)
            }
        }
    }
    
    var estimatedTimeRemaining: String {
        // TODO: Implement batch loading progress tracking
        // This would require totalBatches and completedBatches properties in StockScannerManager
        return "Loading..."
    }
    
    var sortedAndFilteredStocks: [FilteredStock] {
        let filtered = searchText.isEmpty 
            ? scannerManager.filteredStocks
            : scannerManager.filteredStocks.filter { 
                $0.symbol.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        
        return filtered.sorted { first, second in
            let result: Bool
            switch sortBy {
            case .symbol:
                result = first.symbol < second.symbol
            case .changePercent:
                result = abs(first.changePercent) > abs(second.changePercent)
            case .volume:
                result = (first.currentVolume ?? 0) > (second.currentVolume ?? 0)
            case .price:
                result = (first.currentPrice ?? first.previousClose) > (second.currentPrice ?? second.previousClose)
            case .float:
                result = (first.float ?? 0) < (second.float ?? 0)
            }
            return sortAscending ? !result : result
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var scannerManager: StockScannerManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stock Scanner")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Low Float Scanner ($2-20, ≤10M shares) • Real-time updates via Polygon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Market Status Display
            if let marketStatus = scannerManager.scannerSummary?.marketStatus {
                VStack(spacing: 4) {
                    HStack(spacing: 16) {
                        // Market Open/Closed Today
                        HStack(spacing: 6) {
                            Circle()
                                .fill(marketStatus.isMarketOpenToday ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(marketStatus.isMarketOpenToday ? "Market Open Today" : "Market Closed Today")
                                .font(.system(size: 13, weight: .medium))
                        }
                        
                        Divider()
                            .frame(height: 20)
                        
                        // Current Session
                        HStack(spacing: 6) {
                            Image(systemName: sessionIcon(for: marketStatus.status))
                                .foregroundColor(sessionColor(for: marketStatus.status))
                            Text(marketStatus.sessionDescription)
                                .font(.system(size: 13, weight: .medium))
                        }
                        
                        Divider()
                            .frame(height: 20)
                        
                        // Market Hours
                        Text(marketStatus.marketHoursDescription)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        if marketStatus.scannerActive {
                            Divider()
                                .frame(height: 20)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("Scanner Active")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                    
                    if let message = marketStatus.scannerMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    scannerManager.loadFilteredStocks()
                    scannerManager.loadScannerSummary()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    scannerManager.refreshScanner()
                }) {
                    Label("Full Rescan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    func sessionIcon(for status: String) -> String {
        switch status {
        case "premarket":
            return "sunrise.fill"
        case "open":
            return "sun.max.fill"
        case "afterhours":
            return "sunset.fill"
        case "closed":
            return "moon.fill"
        default:
            return "clock.fill"
        }
    }
    
    func sessionColor(for status: String) -> Color {
        switch status {
        case "premarket":
            return .orange
        case "open":
            return .green
        case "afterhours":
            return .blue
        case "closed":
            return .gray
        default:
            return .secondary
        }
    }
}

struct SummaryCardsView: View {
    let summary: ScannerSummary
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            SummaryCard(
                title: "Filtered Stocks",
                value: "\(summary.totalFiltered)",
                icon: "chart.bar.doc.horizontal",
                color: .blue
            )
            
            SummaryCard(
                title: "Price Range",
                value: "$\(Int(summary.priceRange.min))-$\(Int(summary.priceRange.max))",
                icon: "dollarsign.circle",
                color: .green
            )
            
            SummaryCard(
                title: "Max Float",
                value: "\(summary.maxFloat / 1_000_000)M",
                icon: "chart.pie",
                color: .orange
            )
            
            SummaryCard(
                title: "Top Mover",
                value: summary.topMovers.first.map { 
                    String(format: "%.1f%%", $0.changePercent) 
                } ?? "N/A",
                icon: "arrow.up.arrow.down",
                color: .purple
            )
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct TabSelectorView: View {
    @Binding var selectedTab: String
    
    let tabs = [
        ("filtered", "All Filtered"),
        ("gainers", "Gainers"),
        ("losers", "Losers"),
        ("active", "Most Active")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab in
                Button(action: { selectedTab = tab.0 }) {
                    Text(tab.1)
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab.0 ? .semibold : .regular)
                        .foregroundColor(selectedTab == tab.0 ? .white : .primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            selectedTab == tab.0
                                ? Color.blue
                                : Color(NSColor.controlBackgroundColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .cornerRadius(8)
    }
}

struct FilteredStocksView: View {
    let stocks: [FilteredStock]
    @Binding var searchText: String
    @Binding var sortBy: StockScannerView.SortOption
    @Binding var sortAscending: Bool
    @Binding var selectedStock: FilteredStock?
    @Binding var showingStockDetail: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and Sort Bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search symbols...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                Spacer()
                
                Picker("Sort by", selection: $sortBy) {
                    ForEach(StockScannerView.SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Button(action: { sortAscending.toggle() }) {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            // Stock List Table
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Symbol")
                            .frame(width: 80, alignment: .leading)
                        Text("Name")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Price")
                            .frame(width: 80, alignment: .trailing)
                        Text("Change")
                            .frame(width: 80, alignment: .trailing)
                        Text("% Change")
                            .frame(width: 80, alignment: .trailing)
                        Text("Volume")
                            .frame(width: 100, alignment: .trailing)
                        Text("Float")
                            .frame(width: 80, alignment: .trailing)
                        Text("Spread")
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    // Rows
                    ForEach(stocks) { stock in
                        StockRowView(
                            stock: stock,
                            selectedStock: $selectedStock,
                            showingDetail: $showingStockDetail
                        )
                        .environmentObject(appState)
                        Divider()
                    }
                }
            }
        }
    }
}

struct StockRowView: View {
    let stock: FilteredStock
    @Binding var selectedStock: FilteredStock?
    @Binding var showingDetail: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack {
            Text(stock.symbol)
                .fontWeight(.semibold)
                .frame(width: 80, alignment: .leading)
            
            Text(stock.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(formatCurrency(stock.currentPrice ?? stock.previousClose))
                .frame(width: 80, alignment: .trailing)
            
            Text(formatChange(stock.changeAmount))
                .foregroundColor(stock.isPositive ? .green : .red)
                .frame(width: 80, alignment: .trailing)
            
            Text(formatPercentage(stock.changePercent))
                .foregroundColor(stock.isPositive ? .green : .red)
                .frame(width: 80, alignment: .trailing)
            
            Text(formatVolume(stock.currentVolume ?? 0))
                .frame(width: 100, alignment: .trailing)
            
            Text(stock.formattedFloat)
                .frame(width: 80, alignment: .trailing)
            
            Text(stock.spreadPercent.map { String(format: "%.2f%%", $0) } ?? "-")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            stock.lastUpdate != nil && stock.lastUpdate!.timeIntervalSinceNow > -2
                ? Color.blue.opacity(0.1)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            print("Stock tapped: \(stock.symbol)")
            // Update local selection
            selectedStock = stock
            // Set the selected stock in the shared app state
            appState.selectedStock = stock
            // Switch to the Diligence tab (new flow: Scanner -> Diligence -> Trade)
            appState.selectedTab = .diligence
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        return String(format: "$%.2f", value)
    }
    
    private func formatChange(_ value: Double) -> String {
        return String(format: "%+.2f", value)
    }
    
    private func formatPercentage(_ value: Double) -> String {
        return String(format: "%+.2f%%", value)
    }
    
    private func formatVolume(_ volume: Int) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.2fM", Double(volume) / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.1fK", Double(volume) / 1_000)
        }
        return "\(volume)"
    }
}

struct StockListView: View {
    let title: String
    let stocks: [FilteredStock]
    let showFloat: Bool
    @Binding var selectedStock: FilteredStock?
    @Binding var showingStockDetail: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(stocks) { stock in
                        StockRowView(
                            stock: stock,
                            selectedStock: $selectedStock,
                            showingDetail: $showingStockDetail
                        )
                        .environmentObject(appState)
                        Divider()
                    }
                }
            }
        }
    }
}

struct StatusBarView: View {
    let isConnected: Bool
    let lastUpdate: Date
    let stockCount: Int
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Updating...")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            Divider()
                .frame(height: 16)
            
            Text("\(stockCount) stocks")
                .font(.caption)
            
            Spacer()
            
            Text("Last update: \(lastUpdate, formatter: timeFormatter)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }
}