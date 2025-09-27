import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Account Summary Cards
                AccountSummaryView()
                    .environmentObject(tradingManager)
                
                // Quick Actions
                QuickActionsView()
                    .environmentObject(tradingManager)
                
                // Recent Activity
                HStack(alignment: .top, spacing: 20) {
                    // Positions Summary
                    PositionsSummaryView()
                        .environmentObject(tradingManager)
                    
                    // Gap Opportunities
                    GapOpportunitiesSummaryView()
                        .environmentObject(tradingManager)
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .refreshable {
            tradingManager.loadInitialData()
        }
    }
}

struct AccountSummaryView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        GroupBox("Account Summary") {
            HStack(spacing: 20) {
                AccountMetricCard(
                    title: "Portfolio Value",
                    value: tradingManager.totalPortfolioValue,
                    format: .currency,
                    color: .blue
                )
                
                AccountMetricCard(
                    title: "Buying Power",
                    value: tradingManager.accountInfo?.buyingPower ?? 0,
                    format: .currency,
                    color: .green
                )
                
                AccountMetricCard(
                    title: "Day P&L",
                    value: tradingManager.totalUnrealizedPnL,
                    format: .currency,
                    color: tradingManager.totalUnrealizedPnL >= 0 ? .green : .red
                )
                
                AccountMetricCard(
                    title: "Day P&L %",
                    value: tradingManager.totalUnrealizedPnLPercent,
                    format: .percentage,
                    color: tradingManager.totalUnrealizedPnLPercent >= 0 ? .green : .red
                )
            }
        }
    }
}

struct AccountMetricCard: View {
    let title: String
    let value: Double
    let format: NumberFormat
    let color: Color
    
    enum NumberFormat {
        case currency
        case percentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(formattedValue)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var formattedValue: String {
        switch format {
        case .currency:
            return String(format: "$%.2f", value)
        case .percentage:
            return String(format: "%.2f%%", value)
        }
    }
}

struct QuickActionsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var showingOrderSheet = false
    
    var body: some View {
        GroupBox("Quick Actions") {
            HStack(spacing: 16) {
                ActionButton(
                    title: "Place Order",
                    icon: "plus.circle.fill",
                    color: .blue
                ) {
                    showingOrderSheet = true
                }
                
                ActionButton(
                    title: "Refresh Data",
                    icon: "arrow.clockwise",
                    color: .green
                ) {
                    tradingManager.loadInitialData()
                }
                
                ActionButton(
                    title: "Scan Gaps",
                    icon: "magnifyingglass",
                    color: .orange
                ) {
                    tradingManager.loadGapOpportunities()
                }
                
                Spacer()
                
                // Market Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Market Open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingOrderSheet) {
            OrderEntryView()
                .environmentObject(tradingManager)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 80, height: 60)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct PositionsSummaryView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        GroupBox("Active Positions") {
            if tradingManager.positions.isEmpty {
                Text("No active positions")
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tradingManager.positions.prefix(5)) { position in
                        PositionRowView(position: position)
                    }
                    
                    if tradingManager.positions.count > 5 {
                        NavigationLink("View All Positions") {
                            PositionsView()
                                .environmentObject(tradingManager)
                        }
                        .font(.caption)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PositionRowView: View {
    let position: Position
    
    var body: some View {
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
                Text(String(format: "$%.2f", position.unrealizedPnL))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(position.unrealizedPnL >= 0 ? .green : .red)
                
                Text(String(format: "%.2f%%", position.unrealizedPnLPercent))
                    .font(.caption)
                    .foregroundColor(position.unrealizedPnLPercent >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GapOpportunitiesSummaryView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        GroupBox("Gap Opportunities") {
            if tradingManager.gapOpportunities.isEmpty {
                Text("No gap opportunities found")
                    .foregroundColor(.secondary)
                    .frame(height: 100)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tradingManager.gapOpportunities.prefix(5)) { opportunity in
                        GapOpportunityRowView(opportunity: opportunity)
                    }
                    
                    if tradingManager.gapOpportunities.count > 5 {
                        NavigationLink("View All Opportunities") {
                            GapScannerView()
                                .environmentObject(tradingManager)
                        }
                        .font(.caption)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct GapOpportunityRowView: View {
    let opportunity: GapOpportunity
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.symbol)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Confidence: \(Int(opportunity.confidence))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f%%", opportunity.gapPercent))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(opportunity.gapPercent >= 0 ? .green : .red)
                
                Text(String(format: "$%.2f", opportunity.price))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}