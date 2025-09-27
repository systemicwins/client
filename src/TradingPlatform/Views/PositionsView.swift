import SwiftUI

struct PositionsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var sortOrder = SortOrder.unrealizedPnL
    @State private var searchText = ""
    @State private var selectedPosition: Position?
    @State private var showingCloseConfirmation = false
    
    enum SortOrder: String, CaseIterable {
        case symbol = "Symbol"
        case quantity = "Quantity"
        case unrealizedPnL = "P&L"
        case unrealizedPnLPercent = "P&L %"
        case marketValue = "Market Value"
    }
    
    var filteredPositions: [Position] {
        let filtered = searchText.isEmpty ? tradingManager.positions :
            tradingManager.positions.filter { $0.symbol.localizedCaseInsensitiveContains(searchText) }
        
        return filtered.sorted { first, second in
            switch sortOrder {
            case .symbol:
                return first.symbol < second.symbol
            case .quantity:
                return abs(first.quantity) > abs(second.quantity)
            case .unrealizedPnL:
                return first.unrealizedPnL > second.unrealizedPnL
            case .unrealizedPnLPercent:
                return first.unrealizedPnLPercent > second.unrealizedPnLPercent
            case .marketValue:
                return first.marketValue > second.marketValue
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and controls
            VStack(spacing: 16) {
                HStack {
                    Text("Positions")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Refresh") {
                        tradingManager.loadPositions()
                    }
                    .buttonStyle(.bordered)
                }
                
                HStack(spacing: 16) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search positions...", text: $searchText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    // Sort picker
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                // Summary bar
                if !tradingManager.positions.isEmpty {
                    HStack {
                        Text("Total Positions: \(tradingManager.positions.count)")
                        
                        Spacer()
                        
                        Text("Total P&L: ")
                        + Text(formatCurrency(tradingManager.totalUnrealizedPnL))
                            .foregroundColor(tradingManager.totalUnrealizedPnL >= 0 ? .green : .red)
                        
                        Text("(\(formatPercentage(tradingManager.totalUnrealizedPnLPercent)))")
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
            
            Divider()
            
            // Positions table
            if filteredPositions.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 64))
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(position.symbol)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(position.side.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(position.side == "long" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .foregroundColor(position.side == "long" ? .green : .red)
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Quantity") { position in
                        Text(formatQuantity(position.quantity))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .width(min: 80, ideal: 100)
                    
                    TableColumn("Entry Price") { position in
                        Text(formatCurrency(position.entryPrice))
                            .font(.body)
                    }
                    .width(min: 100, ideal: 120)
                    
                    TableColumn("Current Price") { position in
                        Text(formatCurrency(position.currentPrice))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .width(min: 100, ideal: 120)
                    
                    TableColumn("Market Value") { position in
                        Text(formatCurrency(position.marketValue))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .width(min: 120, ideal: 140)
                    
                    TableColumn("Unrealized P&L") { position in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatCurrency(position.unrealizedPnL))
                                .foregroundColor(position.isProfit ? .green : .red)
                                .fontWeight(.semibold)
                            
                            Text(formatPercentage(position.unrealizedPnLPercent))
                                .font(.caption)
                                .foregroundColor(position.isProfit ? .green : .red)
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("Actions") { position in
                        HStack(spacing: 8) {
                            Button("Close") {
                                selectedPosition = position
                                showingCloseConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                            
                            Button("Details") {
                                selectedPosition = position
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                    .width(min: 120, ideal: 140)
                }
            }
        }
        .refreshable {
            tradingManager.loadPositions()
        }
        .sheet(item: $selectedPosition) { position in
            PositionDetailView(position: position)
                .environmentObject(tradingManager)
        }
        .alert("Close Position", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Close Position", role: .destructive) {
                if let position = selectedPosition {
                    tradingManager.closePosition(position)
                }
            }
        } message: {
            if let position = selectedPosition {
                Text("Are you sure you want to close your \(position.side) position in \(position.symbol)?")
            }
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
    
    private func formatQuantity(_ value: Double) -> String {
        return String(format: "%.0f", abs(value))
    }
}

struct PositionDetailView: View {
    let position: Position
    @EnvironmentObject var tradingManager: TradingManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(position.symbol)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text(position.side.capitalized)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(position.side == "long" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                            .foregroundColor(position.side == "long" ? .green : .red)
                            .cornerRadius(8)
                        
                        Text("\(formatQuantity(position.quantity)) shares")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            // Position metrics
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                MetricCardPosition(
                    title: "Entry Price",
                    value: formatCurrency(position.entryPrice),
                    subtitle: nil
                )
                
                MetricCardPosition(
                    title: "Current Price",
                    value: formatCurrency(position.currentPrice),
                    subtitle: nil
                )
                
                MetricCardPosition(
                    title: "Market Value",
                    value: formatCurrency(position.marketValue),
                    subtitle: nil
                )
                
                MetricCardPosition(
                    title: "Unrealized P&L",
                    value: formatCurrency(position.unrealizedPnL),
                    subtitle: formatPercentage(position.unrealizedPnLPercent),
                    color: position.isProfit ? .green : .red
                )
                
                MetricCardPosition(
                    title: "Total Cost",
                    value: formatCurrency(abs(position.quantity) * position.entryPrice),
                    subtitle: nil
                )
                
                MetricCardPosition(
                    title: "Position Size",
                    value: formatQuantity(position.quantity),
                    subtitle: "shares"
                )
            }
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Close Position") {
                    tradingManager.closePosition(position)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("View Chart") {
                    // TODO: Show chart for this symbol
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Add to Watchlist") {
                    // TODO: Add to watchlist
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(30)
        .frame(width: 600, height: 500)
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
    
    private func formatQuantity(_ value: Double) -> String {
        return String(format: "%.0f", abs(value))
    }
}


