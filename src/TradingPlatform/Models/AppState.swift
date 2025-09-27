import SwiftUI

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var selectedTab: MainTab = .dashboard
    @Published var selectedStock: FilteredStock?  // Stock selected from scanner
    
    enum MainTab: CaseIterable {
        case dashboard
        case scanner
        case diligence
        case scannerTrade
        case positions
        case settings
        
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .scanner: return "Scanner"
            case .diligence: return "Diligence"
            case .scannerTrade: return "Trade"
            case .positions: return "Positions"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.line.uptrend.xyaxis"
            case .scanner: return "magnifyingglass"
            case .diligence: return "doc.text.magnifyingglass"
            case .scannerTrade: return "arrow.left.arrow.right.circle.fill"
            case .positions: return "list.bullet"
            case .settings: return "gearshape.fill"
            }
        }
    }
}