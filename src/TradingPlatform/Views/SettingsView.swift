import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tradingManager: TradingManager
    @State private var selectedTab = SettingsTab.general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case trading = "Trading"
        case api = "API"
        case appearance = "Appearance"
        case notifications = "Notifications"
        case about = "About"
    }
    
    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(selectedTab: $selectedTab)
        } detail: {
            SettingsDetailView(selectedTab: selectedTab)
                .environmentObject(tradingManager)
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsView.SettingsTab
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            
            Divider()
            
            List(SettingsView.SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: iconForTab(tab))
                    .tag(tab)
            }
            .listStyle(.sidebar)
            
            Spacer()
        }
        .frame(minWidth: 200, idealWidth: 250)
    }
    
    private func iconForTab(_ tab: SettingsView.SettingsTab) -> String {
        switch tab {
        case .general: return "gear"
        case .trading: return "chart.line.uptrend.xyaxis"
        case .api: return "network"
        case .appearance: return "paintbrush"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}

struct SettingsDetailView: View {
    let selectedTab: SettingsView.SettingsTab
    @EnvironmentObject var tradingManager: TradingManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .trading:
                    TradingSettingsView()
                        .environmentObject(tradingManager)
                case .api:
                    APISettingsView()
                        .environmentObject(tradingManager)
                case .appearance:
                    AppearanceSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .padding()
        }
    }
}

struct GeneralSettingsView: View {
    @State private var autoRefresh = true
    @State private var refreshInterval = 30.0
    @State private var showConfirmations = true
    @State private var enableSounds = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "Data Refresh") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-refresh data", isOn: $autoRefresh)
                    
                    if autoRefresh {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Refresh interval: \(Int(refreshInterval)) seconds")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Slider(value: $refreshInterval, in: 10...120, step: 10)
                                .frame(maxWidth: 300)
                        }
                    }
                }
            }
            
            SettingsSection(title: "User Interface") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show confirmation dialogs", isOn: $showConfirmations)
                    Toggle("Enable sound effects", isOn: $enableSounds)
                }
            }
        }
    }
}

struct TradingSettingsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var defaultQuantity = "100"
    @State private var riskPerTrade = 2.0
    @State private var stopLossEnabled = true
    @State private var takeProfitEnabled = false
    @State private var defaultStopLoss = 5.0
    @State private var defaultTakeProfit = 10.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Trading Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "Order Defaults") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Default quantity:")
                        Spacer()
                        TextField("Shares", text: $defaultQuantity)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Risk per trade: \(String(format: "%.1f", riskPerTrade))%")
                            .font(.subheadline)
                        
                        Slider(value: $riskPerTrade, in: 0.5...5.0, step: 0.1)
                            .frame(maxWidth: 300)
                    }
                }
            }
            
            SettingsSection(title: "Risk Management") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable stop loss by default", isOn: $stopLossEnabled)
                    
                    if stopLossEnabled {
                        HStack {
                            Text("Default stop loss:")
                            Spacer()
                            TextField("Percentage", value: $defaultStopLoss, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("%")
                        }
                    }
                    
                    Toggle("Enable take profit by default", isOn: $takeProfitEnabled)
                    
                    if takeProfitEnabled {
                        HStack {
                            Text("Default take profit:")
                            Spacer()
                            TextField("Percentage", value: $defaultTakeProfit, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("%")
                        }
                    }
                }
            }
        }
    }
}

struct APISettingsView: View {
    @EnvironmentObject var tradingManager: TradingManager
    @State private var apiEndpoint = AppConfiguration.apiBaseURL
    @State private var connectionTimeout = 30.0
    @State private var retryAttempts = 3.0
    @State private var showingConnectionTest = false
    @State private var connectionStatus = "Not tested"
    
    // Alpaca API settings
    @State private var alpacaAPIKey = ""
    @State private var alpacaSecretKey = ""
    @State private var alpacaPaperTrading = true
    @State private var hasAlpacaCredentials = false
    @State private var isLoadingAlpacaStatus = true
    @State private var isSavingAlpacaCredentials = false
    @State private var showAlpacaSuccess = false
    @State private var showAlpacaError = false
    @State private var alpacaErrorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "Connection") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Endpoint:")
                        Spacer()
                        TextField("API Endpoint", text: $apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .onChange(of: apiEndpoint) { _ in
                                // Update APIService with new endpoint
                                APIService.updateBaseURL(apiEndpoint)
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection timeout: \(Int(connectionTimeout)) seconds")
                            .font(.subheadline)
                        
                        Slider(value: $connectionTimeout, in: 10...120, step: 5)
                            .frame(maxWidth: 300)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Retry attempts: \(Int(retryAttempts))")
                            .font(.subheadline)
                        
                        Slider(value: $retryAttempts, in: 1...10, step: 1)
                            .frame(maxWidth: 300)
                    }
                }
            }
            
            SettingsSection(title: "Connection Status") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(connectionStatus)
                            .foregroundColor(connectionStatus == "Connected" ? .green : .secondary)
                    }
                    
                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            SettingsSection(title: "Alpaca Trading API") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configure your Alpaca API credentials to enable live trading.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("API Key:")
                        Spacer()
                        SecureField("Enter your Alpaca API key", text: $alpacaAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    HStack {
                        Text("Secret Key:")
                        Spacer()
                        SecureField("Enter your Alpaca secret key", text: $alpacaSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    HStack {
                        Toggle("Use Paper Trading", isOn: $alpacaPaperTrading)
                        Spacer()
                    }
                    .help("Enable this to use Alpaca's paper trading environment. Disable for live trading.")
                    
                    HStack {
                        Text("Status:")
                        if isLoadingAlpacaStatus {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Text(hasAlpacaCredentials ? "Configured" : "Not configured")
                                .foregroundColor(hasAlpacaCredentials ? .green : .orange)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Button("Save Credentials") {
                            saveAlpacaCredentials()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(alpacaAPIKey.isEmpty || alpacaSecretKey.isEmpty || isSavingAlpacaCredentials)
                        
                        if hasAlpacaCredentials {
                            Button("Remove Credentials") {
                                removeAlpacaCredentials()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSavingAlpacaCredentials)
                        }
                        
                        if isSavingAlpacaCredentials {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    
                    if showAlpacaSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Credentials saved successfully!")
                                .foregroundColor(.green)
                        }
                        .font(.subheadline)
                    }
                    
                    if showAlpacaError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(alpacaErrorMessage)
                                .foregroundColor(.red)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .onAppear {
            loadAlpacaStatus()
        }
    }
    
    private func testConnection() {
        showingConnectionTest = true
        connectionStatus = "Testing..."
        
        Task {
            do {
                // Test the health endpoint
                let _ = try await APIService.shared.healthCheck()
                await MainActor.run {
                    connectionStatus = "Connected"
                    showingConnectionTest = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = "Failed: \(error.localizedDescription)"
                    showingConnectionTest = false
                }
            }
        }
    }
    
    private func loadAlpacaStatus() {
        Task {
            do {
                let credentials = try await APIService.shared.getAlpacaCredentials()
                await MainActor.run {
                    hasAlpacaCredentials = credentials.hasAPIKey && credentials.hasSecretKey
                    alpacaPaperTrading = credentials.paperTrading
                    isLoadingAlpacaStatus = false
                }
            } catch {
                await MainActor.run {
                    hasAlpacaCredentials = false
                    isLoadingAlpacaStatus = false
                }
            }
        }
    }
    
    private func saveAlpacaCredentials() {
        isSavingAlpacaCredentials = true
        showAlpacaSuccess = false
        showAlpacaError = false
        
        Task {
            do {
                try await APIService.shared.updateAlpacaCredentials(
                    apiKey: alpacaAPIKey,
                    secretKey: alpacaSecretKey,
                    paperTrading: alpacaPaperTrading
                )
                
                await MainActor.run {
                    isSavingAlpacaCredentials = false
                    showAlpacaSuccess = true
                    hasAlpacaCredentials = true
                    // Clear the fields for security
                    alpacaAPIKey = ""
                    alpacaSecretKey = ""
                    
                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showAlpacaSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingAlpacaCredentials = false
                    showAlpacaError = true
                    alpacaErrorMessage = error.localizedDescription
                    
                    // Hide error message after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        showAlpacaError = false
                    }
                }
            }
        }
    }
    
    private func removeAlpacaCredentials() {
        isSavingAlpacaCredentials = true
        showAlpacaSuccess = false
        showAlpacaError = false
        
        Task {
            do {
                try await APIService.shared.deleteAlpacaCredentials()
                
                await MainActor.run {
                    isSavingAlpacaCredentials = false
                    hasAlpacaCredentials = false
                    alpacaAPIKey = ""
                    alpacaSecretKey = ""
                    alpacaPaperTrading = true
                    showAlpacaSuccess = true
                    
                    // Hide success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showAlpacaSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingAlpacaCredentials = false
                    showAlpacaError = true
                    alpacaErrorMessage = error.localizedDescription
                    
                    // Hide error message after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        showAlpacaError = false
                    }
                }
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @State private var colorScheme = "System"
    @State private var accentColor = "Blue"
    @State private var showGridLines = true
    @State private var animateCharts = true
    
    let colorSchemes = ["System", "Light", "Dark"]
    let accentColors = ["Blue", "Purple", "Green", "Orange", "Red"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "Theme") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Color scheme:")
                        Spacer()
                        Picker("Color Scheme", selection: $colorScheme) {
                            ForEach(colorSchemes, id: \.self) { scheme in
                                Text(scheme).tag(scheme)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    
                    HStack {
                        Text("Accent color:")
                        Spacer()
                        Picker("Accent Color", selection: $accentColor) {
                            ForEach(accentColors, id: \.self) { color in
                                Text(color).tag(color)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }
            }
            
            SettingsSection(title: "Charts") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show grid lines", isOn: $showGridLines)
                    Toggle("Animate chart transitions", isOn: $animateCharts)
                }
            }
        }
    }
}

struct NotificationSettingsView: View {
    @State private var enableNotifications = true
    @State private var priceAlerts = true
    @State private var orderFills = true
    @AppStorage("enableGapperNotifications") private var gapperAlerts = true
    @AppStorage("minGapPercentForNotification") private var minGapPercent = 5.0
    @AppStorage("startMinimized") private var startMinimized = false
    @State private var portfolioUpdates = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Notification Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "General") {
                Toggle("Enable notifications", isOn: $enableNotifications)
                Toggle("Start minimized to menu bar", isOn: $startMinimized)
            }
            
            if enableNotifications {
                SettingsSection(title: "Alert Types") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Price alerts", isOn: $priceAlerts)
                        Toggle("Order fills", isOn: $orderFills)
                        Toggle("Portfolio updates", isOn: $portfolioUpdates)
                    }
                }
                
                SettingsSection(title: "Gapper Notifications") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable gapper alerts", isOn: $gapperAlerts)
                        
                        if gapperAlerts {
                            HStack {
                                Text("Minimum gap percentage:")
                                Slider(value: $minGapPercent, in: 1...20, step: 0.5)
                                    .frame(width: 200)
                                Text("\(minGapPercent, specifier: "%.1f")%")
                                    .frame(width: 50, alignment: .trailing)
                            }
                            
                            Text("You'll be notified when stocks gap above \(minGapPercent, specifier: "%.1f")%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About")
                .font(.title2)
                .fontWeight(.bold)
            
            SettingsSection(title: "Application") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Version", value: "1.0.0")
                    InfoRow(label: "Build", value: "2024.1")
                    InfoRow(label: "Swift Version", value: "5.9")
                    InfoRow(label: "Charts Library", value: "5.0.0")
                }
            }
            
            SettingsSection(title: "System") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Platform", value: "macOS 14.0+")
                    InfoRow(label: "Architecture", value: ProcessInfo.processInfo.machineHardwareName)
                    InfoRow(label: "Memory", value: "\(ProcessInfo.processInfo.physicalMemory / 1_000_000_000)GB RAM")
                }
            }
            
            SettingsSection(title: "Links") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("View License") {
                        // TODO: Show license
                    }
                    .buttonStyle(.link)
                    
                    Button("Privacy Policy") {
                        // TODO: Show privacy policy
                    }
                    .buttonStyle(.link)
                    
                    Button("Support") {
                        // TODO: Open support
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            content
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

