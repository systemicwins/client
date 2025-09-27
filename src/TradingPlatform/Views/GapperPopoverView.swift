import SwiftUI

struct GapperPopoverView: View {
    let gappers: [FilteredStock]
    let onSelectGapper: (FilteredStock) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Top Gappers")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Gapper list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(gappers.prefix(10)) { stock in
                        GapperRow(stock: stock) {
                            onSelectGapper(stock)
                            dismiss()
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

struct GapperRow: View {
    let stock: FilteredStock
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Symbol and Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(stock.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(stock.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer()
                
                // Price and Change
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(stock.currentPrice ?? stock.previousClose, specifier: "%.2f")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 2) {
                        Image(systemName: stock.isPositive ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9))
                        Text("\(abs(stock.changePercent), specifier: "%.1f")%")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(stock.isPositive ? .green : .red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color(NSColor.selectedControlColor).opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// Preview
struct GapperPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        GapperPopoverView(
            gappers: [
                FilteredStock(
                    symbol: "AAPL",
                    name: "Apple Inc.",
                    exchange: "NASDAQ",
                    previousClose: 180.0,
                    previousVolume: 1000000,
                    previousVWAP: nil,
                    float: nil,
                    currentPrice: 195.0,
                    currentVolume: 1500000
                ),
                FilteredStock(
                    symbol: "TSLA",
                    name: "Tesla Inc.",
                    exchange: "NASDAQ",
                    previousClose: 240.0,
                    previousVolume: 2000000,
                    previousVWAP: nil,
                    float: nil,
                    currentPrice: 255.0,
                    currentVolume: 2500000
                )
            ],
            onSelectGapper: { _ in }
        )
    }
}