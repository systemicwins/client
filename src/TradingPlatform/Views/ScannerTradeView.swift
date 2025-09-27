import SwiftUI
import Charts

struct ScannerTradeView: View {
    @EnvironmentObject var scannerManager: StockScannerManager
    @StateObject private var candlestickManager = CandlestickManager()
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedStock: FilteredStock?
    @State private var searchText = ""
    @State private var orderType: OrderType = .market
    @State private var orderSide: OrderSide = .buy
    @State private var quantity: String = "100"
    @State private var limitPrice: String = ""
    @State private var stopPrice: String = ""
    @State private var showingOrderConfirmation = false
    @State private var orderError: String?
    @State private var isPlacingOrder = false
    @State private var showingFilters = false
    
    // For receiving stock selection from menu bar
    let selectedStockFromMenuBar: FilteredStock?
    
    init(selectedStock: FilteredStock? = nil) {
        self.selectedStockFromMenuBar = selectedStock
    }
    
    enum OrderType: String, CaseIterable {
        case market = "Market"
        case limit = "Limit"
        case stopLoss = "Stop Loss"
        case stopLimit = "Stop Limit"
    }
    
    enum OrderSide: String, CaseIterable {
        case buy = "Buy"
        case sell = "Sell"
    }
    
    var body: some View {
        Group {
            // Check market status first
            if scannerManager.scannerSummary == nil && scannerManager.isLoading {
                loadingView
            } else if let marketStatus = scannerManager.scannerSummary?.marketStatus,
               marketStatus.status == "closed" && 
               !marketStatus.isPremarket && 
               !marketStatus.isRegularHours && 
               !marketStatus.isAfterhours {
                // Full screen market closed view - only when completely outside trading hours
                MarketClosedView(marketStatus: marketStatus)
            } else {
                // Normal trading view
                tradingView
            }
        }
        .onAppear {
            // Set selected stock if provided from menu bar
            if let stockFromMenuBar = selectedStockFromMenuBar {
                selectedStock = stockFromMenuBar
            }
            
            // Only load if we don't have data yet (scanner runs continuously in background)
            if scannerManager.filteredStocks.isEmpty && !scannerManager.isLoading {
                print("ScannerTradeView: No data available, loading...")
                scannerManager.loadScannerSummary()
                // Delay filtered stocks load slightly to avoid concurrent parsing issues
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    scannerManager.loadFilteredStocks()
                }
            } else {
                print("ScannerTradeView: Using existing data with \(scannerManager.filteredStocks.count) stocks")
            }
        }
        .alert("Order Confirmation", isPresented: $showingOrderConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Place Order", role: .destructive) {
                executeOrder()
            }
        } message: {
            Text(orderConfirmationMessage)
        }
        .alert("Order Error", isPresented: .constant(orderError != nil)) {
            Button("OK") {
                orderError = nil
            }
        } message: {
            Text(orderError ?? "")
        }
        .sheet(isPresented: $showingFilters) {
            ScannerFiltersSheet(scannerManager: scannerManager)
        }
    }
    
    @ViewBuilder
    var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Loading market status...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    var tradingView: some View {
        // Trading interface only - no scanner panel
        if let stock = selectedStock {
            VStack(spacing: 0) {
                // Stock header
                ScannedStockHeaderView(stock: stock)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Stock details
                        StockDetailsSection(stock: stock)
                        
                        // Tradeable Float History (SEC Filings)
                        TradeableFloatChart(symbol: stock.symbol)
                        
                        // Candlestick chart with real-time updates
                        CandlestickChartView(manager: candlestickManager, symbol: stock.symbol)
                            .frame(height: 400)
                        
                        // Order Form
                        ScannerOrderFormSection(
                            stock: stock,
                            orderType: $orderType,
                            orderSide: $orderSide,
                            quantity: $quantity,
                            limitPrice: $limitPrice,
                            stopPrice: $stopPrice,
                            onSubmit: placeOrder
                        )
                        
                        // Recent Orders
                        RecentOrdersSection()
                        
                        Spacer()
                    }
                    .padding()
                }
            }
        } else {
            // Empty state
            VStack {
                Image(systemName: "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("No Stock Selected")
                    .font(.title2)
                    .padding(.top)
                Text("Select a stock from the Scanner tab to begin trading")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    var filteredScannedStocks: [FilteredStock] {
        let stocks = if searchText.isEmpty {
            scannerManager.filteredStocks
        } else {
            scannerManager.filteredStocks.filter { stock in
                stock.symbol.localizedCaseInsensitiveContains(searchText) ||
                stock.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        // Sort by percentage gain in descending order (highest gainers first)
        return stocks.sorted { $0.changePercent > $1.changePercent }
    }
    
    var orderConfirmationMessage: String {
        guard let stock = selectedStock else { return "" }
        
        var message = "\(orderSide.rawValue) \(quantity) shares of \(stock.symbol)"
        
        switch orderType {
        case .market:
            message += " at market price"
        case .limit:
            message += " at limit price $\(limitPrice)"
        case .stopLoss:
            message += " with stop loss at $\(stopPrice)"
        case .stopLimit:
            message += " with stop at $\(stopPrice) and limit at $\(limitPrice)"
        }
        
        return message
    }
    
    func placeOrder() {
        showingOrderConfirmation = true
    }
    
    func executeOrder() {
        guard let stock = selectedStock else { return }
        
        isPlacingOrder = true
        
        let qty = Int(quantity) ?? 100
        
        Task {
            do {
                switch orderType {
                case .market:
                    try await tradingManager.placeMarketOrder(
                        symbol: stock.symbol,
                        side: orderSide == .buy ? "buy" : "sell",
                        quantity: qty
                    )
                case .limit:
                    guard let price = Double(limitPrice) else {
                        throw TradingError.invalidPrice
                    }
                    try await tradingManager.placeLimitOrder(
                        symbol: stock.symbol,
                        side: orderSide == .buy ? "buy" : "sell",
                        quantity: qty,
                        limitPrice: price
                    )
                case .stopLoss:
                    guard let stop = Double(stopPrice) else {
                        throw TradingError.invalidPrice
                    }
                    try await tradingManager.placeStopOrder(
                        symbol: stock.symbol,
                        side: orderSide == .buy ? "buy" : "sell",
                        quantity: qty,
                        stopPrice: stop
                    )
                case .stopLimit:
                    guard let stop = Double(stopPrice),
                          let limit = Double(limitPrice) else {
                        throw TradingError.invalidPrice
                    }
                    try await tradingManager.placeStopLimitOrder(
                        symbol: stock.symbol,
                        side: orderSide == .buy ? "buy" : "sell",
                        quantity: qty,
                        stopPrice: stop,
                        limitPrice: limit
                    )
                }
                
                await MainActor.run {
                    quantity = "100"
                    limitPrice = ""
                    stopPrice = ""
                    isPlacingOrder = false
                }
            } catch {
                await MainActor.run {
                    orderError = error.localizedDescription
                    isPlacingOrder = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ScannedStockRow: View {
    let stock: FilteredStock
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol)
                    .font(.headline)
                Text(stock.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(stock.currentPrice ?? stock.previousClose))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(formatPercentage(stock.changePercent))
                    .font(.caption)
                    .foregroundColor(stock.changePercent >= 0 ? .green : .red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
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
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
    }
}

