import SwiftUI

struct PositionsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var sortOrder = SortOrder.symbol
    @State private var searchText = ""
    
    enum SortOrder: String, CaseIterable {
        case symbol = "Symbol"
        case quantity = "Quantity"
        case pnl = "P&L"
        case pnlPercent = "P&L %"
    }
    
    var filteredPositions: [Position] {
        let filtered = searchText.isEmpty ? tradingManager.positions :
            tradingManager.positions.filter { $0.symbol.localizedCaseInsensitiveContains(searchText) }
        
        return filtered.sorted { first, second in
            switch sortOrder {
            case .symbol:
                return first.symbol < second.symbol
            case .quantity:
                return first.quantity > second.quantity
            case .pnl:
                return first.unrealizedPnL > second.unrealizedPnL
            case .pnlPercent:
                return first.unrealizedPnLPercent > second.unrealizedPnLPercent
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and controls
            VStack(spacing: 16) {
                HStack {
                    TextField("Search positions...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    
                    Button("Refresh") {
                        tradingManager.loadPositions()
                    }
                    .buttonStyle(.bordered)
                }
                
                // Summary bar
                if !tradingManager.positions.isEmpty {
                    HStack {
                        Text("Total Positions: \(tradingManager.positions.count)")
                        
                        Spacer()
                        
                        Text("Total P&L: ")
                        + Text(String(format: "$%.2f", tradingManager.totalUnrealizedPnL))
                            .foregroundColor(tradingManager.totalUnrealizedPnL >= 0 ? .green : .red)
                        
                        Text("(\(String(format: "%.2f%%", tradingManager.totalUnrealizedPnLPercent)))")
                            .foregroundColor(tradingManager.totalUnrealizedPnLPercent >= 0 ? .green : .red)
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            // Positions table
            if filteredPositions.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? "No positions found" : "No positions match your search")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if searchText.isEmpty {
                        Text("Your positions will appear here once you have active trades")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                Table(filteredPositions) {
                    TableColumn("Symbol") { position in
                        HStack {
                            Text(position.symbol)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text(position.side.uppercased())
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(position.side == "long" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(position.side == "long" ? .green : .red)
                                .cornerRadius(4)
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Quantity") { position in
                        Text(String(format: "%.0f", position.quantity))
                            .font(.body)
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Avg Price") { position in
                        Text(String(format: "$%.2f", position.averagePrice))
                            .font(.body)
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Current Price") { position in
                        Text(String(format: "$%.2f", position.currentPrice))
                            .font(.body)
                    }
                    .width(min: 100, ideal: 120)
                    
                    TableColumn("Market Value") { position in
                        Text(String(format: "$%.2f", position.marketValue))
                            .font(.body)
                    }
                    .width(min: 100, ideal: 120)
                    
                    TableColumn("Unrealized P&L") { position in
                        HStack {
                            Text(String(format: "$%.2f", position.unrealizedPnL))
                                .foregroundColor(position.unrealizedPnL >= 0 ? .green : .red)
                                .fontWeight(.medium)
                            
                            Text(String(format: "(%.2f%%)", position.unrealizedPnLPercent))
                                .font(.caption)
                                .foregroundColor(position.unrealizedPnL >= 0 ? .green : .red)
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Actions") { position in
                        HStack(spacing: 8) {
                            Button("Close") {
                                closePosition(position)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button("Details") {
                                // TODO: Show position details
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                    .width(min: 100, ideal: 120)
                }
            }
        }
        .navigationTitle("Positions")
        .refreshable {
            tradingManager.loadPositions()
        }
    }
    
    private func closePosition(_ position: Position) {
        let side = position.side == "long" ? "sell" : "buy"
        tradingManager.placeOrder(
            symbol: position.symbol,
            quantity: abs(position.quantity),
            side: side,
            orderType: "market"
        )
    }
}