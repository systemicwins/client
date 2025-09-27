import SwiftUI
import Charts

// MARK: - Formatting Helpers
func formatCurrency(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
}

func formatPercentage(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 2
    formatter.positivePrefix = "+"
    return formatter.string(from: NSNumber(value: value / 100)) ?? "0.00%"
}

struct TradeView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @EnvironmentObject var appState: AppState
    @StateObject private var candlestickManager = CandlestickManager()
    @State private var selectedStock: Stock?
    @State private var orderType: OrderType = .market
    @State private var orderSide: OrderSide = .buy
    @State private var quantity: String = "100"
    @State private var limitPrice: String = ""
    @State private var stopPrice: String = ""
    @State private var showingOrderConfirmation = false
    @State private var orderError: String?
    @State private var isPlacingOrder = false
    
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
            // Trading interface only - no left panel
            if let stock = selectedStock {
                VStack(spacing: 0) {
                    // Stock header
                    StockHeaderView(stock: stock)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Chart
                            CandlestickChartView(manager: candlestickManager, symbol: stock.symbol)
                                .frame(height: 400)
                            
                            // Order Form
                            OrderFormSection(
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
        .onAppear {
            // Check if there's a stock selected from the scanner
            if let scannerStock = appState.selectedStock {
                print("TradeView: Received stock from scanner: \(scannerStock.symbol)")
                // Convert FilteredStock to Stock
                let stock = Stock(
                    symbol: scannerStock.symbol,
                    name: scannerStock.name,
                    price: scannerStock.currentPrice ?? scannerStock.previousClose,
                    changePercent: scannerStock.changePercent,
                    changeAmount: scannerStock.changeAmount
                )
                selectedStock = stock
                // Load candlesticks for the selected stock
                candlestickManager.loadCandlesticks(for: stock.symbol)
                print("TradeView: Loading candlesticks for \(stock.symbol)")
                // Clear the selection in app state
                appState.selectedStock = nil
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
            message += " with stop price $\(stopPrice)"
        case .stopLimit:
            message += " with stop price $\(stopPrice) and limit price $\(limitPrice)"
        }
        
        if let price = stock.price,
           let qty = Double(quantity) {
            let estimatedCost = price * qty
            message += "\n\nEstimated cost: \(formatCurrency(estimatedCost))"
        }
        
        return message
    }
    
    func placeOrder() {
        guard selectedStock != nil else { return }
        showingOrderConfirmation = true
    }
    
    func executeOrder() {
        guard let stock = selectedStock else { return }
        
        isPlacingOrder = true
        
        // Create order parameters
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
                
                // Clear form on success
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

struct StockHeaderView: View {
    let stock: Stock
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.symbol)
                    .font(.title)
                    .fontWeight(.bold)
                if let name = stock.name {
                    Text(name)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let price = stock.price {
                    Text(formatCurrency(price))
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                if let change = stock.changePercent,
                   let changeAmount = stock.changeAmount {
                    HStack {
                        Text(formatCurrency(changeAmount))
                        Text("(\(formatPercentage(change)))")
                    }
                    .foregroundColor(change >= 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}


struct OrderFormSection: View {
    let stock: Stock
    @Binding var orderType: TradeView.OrderType
    @Binding var orderSide: TradeView.OrderSide
    @Binding var quantity: String
    @Binding var limitPrice: String
    @Binding var stopPrice: String
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Place Order")
                .font(.headline)
            
            // Order side selector
            Picker("Side", selection: $orderSide) {
                ForEach(TradeView.OrderSide.allCases, id: \.self) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)
            
            // Order type selector
            Picker("Order Type", selection: $orderType) {
                ForEach(TradeView.OrderType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            
            // Quantity
            HStack {
                Text("Quantity:")
                    .frame(width: 100, alignment: .leading)
                TextField("100", text: $quantity)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            
            // Limit price (for limit and stop-limit orders)
            if orderType == .limit || orderType == .stopLimit {
                HStack {
                    Text("Limit Price:")
                        .frame(width: 100, alignment: .leading)
                    TextField("0.00", text: $limitPrice)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            // Stop price (for stop-loss and stop-limit orders)
            if orderType == .stopLoss || orderType == .stopLimit {
                HStack {
                    Text("Stop Price:")
                        .frame(width: 100, alignment: .leading)
                    TextField("0.00", text: $stopPrice)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            // Estimated cost
            if let price = stock.price,
               let qty = Double(quantity) {
                HStack {
                    Text("Estimated Cost:")
                        .frame(width: 100, alignment: .leading)
                    Text(formatCurrency(price * qty))
                        .fontWeight(.medium)
                }
            }
            
            // Submit button
            Button(action: onSubmit) {
                HStack {
                    Image(systemName: orderSide == .buy ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    Text("\(orderSide.rawValue) \(stock.symbol)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(orderSide == .buy ? .green : .red)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct RecentOrdersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Orders")
                .font(.headline)
            
            // Placeholder for recent orders
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(height: 200)
                .overlay(
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Recent orders will appear here")
                            .foregroundColor(.secondary)
                    }
                )
        }
    }
}

// MARK: - Trading Error

enum TradingError: LocalizedError {
    case invalidPrice
    case invalidQuantity
    case insufficientFunds
    case orderFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "Please enter a valid price"
        case .invalidQuantity:
            return "Please enter a valid quantity"
        case .insufficientFunds:
            return "Insufficient funds for this order"
        case .orderFailed(let message):
            return "Order failed: \(message)"
        }
    }
}

// MARK: - Preview

struct TradeView_Previews: PreviewProvider {
    static var previews: some View {
        TradeView()
            .environmentObject(TradingManager())
            .frame(width: 1200, height: 800)
    }
}