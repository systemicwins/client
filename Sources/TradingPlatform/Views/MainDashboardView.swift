import SwiftUI
import Charts

struct MainDashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tradingManager: TradingManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var scannerManager: StockScannerManager
    @State private var selectedStockForTrading: FilteredStock?
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .environmentObject(authManager)
        } detail: {
            TabView(selection: $appState.selectedTab) {
                UnifiedDashboardView()
                    .tag(AppState.MainTab.dashboard)
                    .environmentObject(tradingManager)
                
                StockScannerView()
                    .tag(AppState.MainTab.scanner)
                    .environmentObject(scannerManager)
                
                DiligenceView()
                    .tag(AppState.MainTab.diligence)
                    .environmentObject(appState)
                
                ScannerTradeView(selectedStock: selectedStockForTrading)
                    .tag(AppState.MainTab.scannerTrade)
                    .environmentObject(tradingManager)
                    .environmentObject(scannerManager)
                
                PositionsView()
                    .tag(AppState.MainTab.positions)
                    .environmentObject(tradingManager)
                
                SettingsView()
                    .tag(AppState.MainTab.settings)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .onAppear {
            tradingManager.loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenTradeView"))) { notification in
            if let stock = notification.userInfo?["stock"] as? FilteredStock {
                selectedStockForTrading = stock
                appState.selectedTab = .scannerTrade
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tradingManager: TradingManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    Text("Relentless Trader")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                
                // Portfolio summary card
                if let portfolio = tradingManager.portfolioSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Portfolio Value")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        Text(formatCurrency(portfolio.totalValue))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            Text(formatCurrency(portfolio.dailyPnL))
                                .foregroundColor(portfolio.dailyPnL >= 0 ? .green : .red)
                            
                            Text("(\(formatPercentage(portfolio.dailyPnLPercent)))")
                                .foregroundColor(portfolio.dailyPnL >= 0 ? .green : .red)
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            Divider()
            
            // Navigation items
            List(AppState.MainTab.allCases, id: \.self, selection: $appState.selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            
            Spacer()
            
            // User info and logout
            VStack(spacing: 12) {
                Divider()
                
                if let user = appState.currentUser {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.headline)
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Logout") {
                    authManager.logout()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 300)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
    }
}

struct DashboardView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedTimeframe = "1D"
    
    let timeframes = ["1D", "1W", "1M", "3M", "6M", "1Y"]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header
                HStack {
                    Text("Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Refresh") {
                        tradingManager.loadInitialData()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                // Performance metrics cards
                MetricsCardsView()
                    .environmentObject(tradingManager)
                
                // Portfolio performance chart
                PortfolioChartView(selectedTimeframe: $selectedTimeframe)
                    .environmentObject(tradingManager)
                
                HStack(alignment: .top, spacing: 20) {
                    // Top positions
                    TopPositionsView()
                        .environmentObject(tradingManager)
                    
                }
                .padding(.horizontal)
            }
        }
        .refreshable {
            tradingManager.loadInitialData()
        }
    }
}

struct MetricsCardsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            MetricCardDashboard(
                title: "Portfolio Value",
                value: formatCurrency(tradingManager.totalPortfolioValue),
                change: nil,
                color: .blue
            )
            
            MetricCardDashboard(
                title: "Day P&L",
                value: formatCurrency(tradingManager.totalUnrealizedPnL),
                change: formatPercentage(tradingManager.totalUnrealizedPnLPercent),
                color: tradingManager.totalUnrealizedPnL >= 0 ? .green : .red
            )
            
            MetricCardDashboard(
                title: "Positions",
                value: "\(tradingManager.positions.count)",
                change: nil,
                color: .orange
            )
            
            MetricCardDashboard(
                title: "Buying Power",
                value: formatCurrency(tradingManager.portfolioSummary?.buyingPower ?? 0),
                change: nil,
                color: .purple
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
    }
}


struct PortfolioChartView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @Binding var selectedTimeframe: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Portfolio Performance")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(["1D", "1W", "1M", "3M", "6M", "1Y"], id: \.self) { timeframe in
                        Text(timeframe).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            
            // Portfolio performance chart using Charts framework
            Chart(tradingManager.performanceData) { data in
                LineMark(
                    x: .value("Date", data.date),
                    y: .value("Portfolio Value", data.portfolioValue)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                
                AreaMark(
                    x: .value("Date", data.date),
                    y: .value("Portfolio Value", data.portfolioValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 300)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel(format: .currency(code: "USD"))
                    AxisGridLine()
                    AxisTick()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TopPositionsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Positions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                NavigationLink("View All") {
                    PositionsView()
                        .environmentObject(tradingManager)
                }
                .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                ForEach(Array(tradingManager.positions.prefix(5))) { position in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.symbol)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("\(Int(position.quantity)) shares")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatCurrency(position.unrealizedPnL))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(position.isProfit ? .green : .red)
                            
                            Text(formatPercentage(position.unrealizedPnLPercent))
                                .font(.caption)
                                .foregroundColor(position.isProfit ? .green : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if position.id != tradingManager.positions.prefix(5).last?.id {
                        Divider()
                    }
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
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
    private func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
    }
}


