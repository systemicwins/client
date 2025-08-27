import SwiftUI

// Helper views for ScannerTradeView

struct MarketClosedView: View {
    let marketStatus: MarketStatus
    
    var body: some View {
        VStack {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Market Closed")
                .font(.title2)
                .padding(.top)
            if let reason = marketStatus.reason {
                Text(reason)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScannerFiltersSheet: View {
    @ObservedObject var scannerManager: StockScannerManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Scanner Filters")
                .font(.title2)
                .padding()
            
            Text("Filters are applied on the server side")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

struct ScannedStockHeaderView: View {
    let stock: FilteredStock
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(stock.symbol)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(stock.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(formatCurrency(stock.currentPrice ?? stock.previousClose))
                    .font(.title)
                    .fontWeight(.semibold)
                HStack {
                    Text(formatCurrency(stock.changeAmount))
                    Text("(\(formatPercentage(stock.changePercent)))")
                }
                .font(.title3)
                .foregroundColor(stock.changeAmount >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
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

struct StockDetailsSection: View {
    let stock: FilteredStock
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stock Details")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                DetailItem(label: "Volume", value: formatNumber(Double(stock.currentVolume ?? 0)))
                DetailItem(label: "Prev Volume", value: formatNumber(Double(stock.previousVolume)))
                DetailItem(label: "Prev Close", value: formatCurrency(stock.previousClose))
                DetailItem(label: "Float", value: stock.formattedFloat)
                DetailItem(label: "Change %", value: formatPercentage(stock.changePercent))
                DetailItem(label: "Exchange", value: stock.exchange)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    private func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

struct DetailItem: View {
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

struct ScannerOrderFormSection: View {
    let stock: FilteredStock
    @Binding var orderType: ScannerTradeView.OrderType
    @Binding var orderSide: ScannerTradeView.OrderSide
    @Binding var quantity: String
    @Binding var limitPrice: String
    @Binding var stopPrice: String
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Place Order")
                .font(.headline)
            
            HStack {
                Picker("Side", selection: $orderSide) {
                    ForEach(ScannerTradeView.OrderSide.allCases, id: \.self) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Type", selection: $orderType) {
                    ForEach(ScannerTradeView.OrderType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("Quantity")
                TextField("100", text: $quantity)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            
            if orderType == .limit || orderType == .stopLimit {
                HStack {
                    Text("Limit Price")
                    TextField("0.00", text: $limitPrice)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            if orderType == .stopLoss || orderType == .stopLimit {
                HStack {
                    Text("Stop Price")
                    TextField("0.00", text: $stopPrice)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            Button(action: onSubmit) {
                Label("Place Order", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}