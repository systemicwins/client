import SwiftUI

@main
struct TradingClientApp: App {
    init() {
        // Run network test on startup
        TestNetwork.test()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1200, minHeight: 800)
        }
    }
}

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var tradingManager = TradingManager()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            if authManager.isAuthenticated {
                MainContentView()
                    .environmentObject(tradingManager)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .navigationTitle("Trading Platform")
    }
}

struct SidebarView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedItem: SidebarItem? = .dashboard
    
    enum SidebarItem: String, CaseIterable {
        case dashboard = "Dashboard"
        case positions = "Positions"
        case orders = "Orders"
        case performance = "Performance"
        case settings = "Settings"
        
        var iconName: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .positions: return "list.bullet"
            case .orders: return "doc.text.fill"
            case .performance: return "chart.line.uptrend.xyaxis"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        List(SidebarItem.allCases, id: \.self, selection: $selectedItem) { item in
            NavigationLink(value: item) {
                Label(item.rawValue, systemImage: item.iconName)
            }
        }
        .navigationTitle("Trading Platform")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Logout") {
                    authManager.logout()
                }
            }
        }
    }
}

struct MainContentView: View {
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .environmentObject(tradingManager)
            
            PositionsView()
                .tabItem {
                    Label("Positions", systemImage: "list.bullet")
                }
                .environmentObject(tradingManager)
            
            
            PerformanceView()
                .tabItem {
                    Label("Performance", systemImage: "chart.line.uptrend.xyaxis")
                }
                .environmentObject(tradingManager)
        }
        .onAppear {
            tradingManager.loadInitialData()
        }
    }
}