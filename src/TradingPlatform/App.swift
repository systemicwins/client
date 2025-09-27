import SwiftUI
import AppKit
import UserNotifications

@main
struct TradingPlatformApp: App {
    @StateObject private var appState = AppState()
    private let windowDelegate = WindowDelegate()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("startMinimized") private var startMinimized = false
    
    init() {
        // Ensure app appears in dock and can take focus
        NSApplication.shared.setActivationPolicy(.regular)
        
        // SEC-BERT will initialize automatically when needed
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    setupWindow()
                }
        }
        .defaultSize(width: 500, height: 700)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
    
    private func setupWindow() {
        // Configure the main window
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.backgroundColor = NSColor.controlBackgroundColor
                
                // Enable proper window closing
                window.standardWindowButton(.closeButton)?.isEnabled = true
                
                // Set appropriate close behavior
                window.delegate = self.windowDelegate
                
                // Set initial window size for login
                window.setContentSize(NSSize(width: 500, height: 700))
                window.center()
                
                // Check if should start minimized
                if self.startMinimized {
                    window.orderOut(nil)  // Hide the window
                } else {
                    // Make sure window appears and takes focus
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var scannerManager: StockScannerManager?
    private var statusUpdateTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only set up notification center if running as a proper app bundle
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        
        // Initialize scanner manager
        scannerManager = StockScannerManager()
        
        // Set up status bar item (menu bar icon)
        setupStatusBarItem()
    }
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Trading Platform")
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        
        // Start timer to update status bar icon based on gapper count
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatusBarIcon()
        }
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        if let scannerManager = scannerManager {
            let gapperCount = scannerManager.topGainers.count
            
            if gapperCount > 0 {
                // Show a different icon or add a badge when gappers are found
                button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis.circle.fill", 
                                      accessibilityDescription: "Trading Platform - \(gapperCount) gappers")
                button.image?.isTemplate = true
                
                // Update tooltip
                button.toolTip = "\(gapperCount) gapper\(gapperCount == 1 ? "" : "s") found"
            } else {
                // Regular icon when no gappers
                button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", 
                                      accessibilityDescription: "Trading Platform")
                button.image?.isTemplate = true
                button.toolTip = "No gappers found"
            }
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // Show menu on right-click
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Hide Window", action: #selector(hideMainWindow), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit Trading Platform", action: #selector(quitApp), keyEquivalent: "q"))
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Check if we have gappers to show
            if let scannerManager = scannerManager {
                let topGappers = scannerManager.topGainers
                if !topGappers.isEmpty {
                    showGapperPopover(with: topGappers, from: sender)
                } else {
                    toggleWindow()
                }
            } else {
                toggleWindow()
            }
        }
    }
    
    @objc private func toggleWindow() {
        if let window = NSApplication.shared.windows.first {
            if window.isVisible && !window.isMiniaturized {
                window.orderOut(nil)
            } else {
                showMainWindow()
            }
        }
    }
    
    @objc private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }
    
    private func showGapperPopover(with gappers: [FilteredStock], from sender: NSStatusBarButton) {
        // Close existing popover if any
        popover?.close()
        
        // Create new popover
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.animates = true
        
        // Create the SwiftUI view
        let contentView = GapperPopoverView(gappers: gappers) { selectedStock in
            // Handle gapper selection
            self.openTradeView(for: selectedStock)
        }
        
        // Set up the popover content
        let hostingController = NSHostingController(rootView: contentView)
        popover?.contentViewController = hostingController
        
        // Show the popover
        popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    
    private func openTradeView(for stock: FilteredStock) {
        // First, show the main window
        showMainWindow()
        
        // Post a notification to open the trade view with the selected stock
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenTradeView"),
            object: nil,
            userInfo: ["stock": stock]
        )
    }
    
    func setScannerManager(_ manager: StockScannerManager) {
        self.scannerManager = manager
        // Immediately update the status bar icon
        updateStatusBarIcon()
    }
    
    @objc private func showMainWindow() {
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func hideMainWindow() {
        if let window = NSApplication.shared.windows.first {
            window.miniaturize(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // Handle notification clicks - bring app to foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse, 
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Bring app to foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // If window is minimized, restore it
        if let window = NSApplication.shared.windows.first {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        
        // Check if this is a gapper notification
        let userInfo = response.notification.request.content.userInfo
        if let type = userInfo["type"] as? String, type == "gapper" {
            // Create a FilteredStock from the notification data
            if let symbol = userInfo["symbol"] as? String,
               let name = userInfo["name"] as? String,
               let price = userInfo["price"] as? Double,
               let changePercent = userInfo["changePercent"] as? Double,
               let previousClose = userInfo["previousClose"] as? Double {
                
                let stock = FilteredStock(
                    symbol: symbol,
                    name: name,
                    exchange: "NASDAQ", // Default, will be updated when full data loads
                    previousClose: previousClose,
                    previousVolume: 0,
                    previousVWAP: nil,
                    float: nil,
                    currentPrice: price,
                    currentVolume: nil
                )
                
                // Open the trade view with this stock
                openTradeView(for: stock)
            }
        }
        
        completionHandler()
    }
    
    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even if app is active
        if #available(macOS 12.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.sound, .badge])
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up timer
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window instead of closing it
        sender.orderOut(nil)
        return false  // Prevent actual closing
    }
    
    func windowWillMiniaturize(_ notification: Notification) {
        // Window is being minimized - it will go to dock
    }
    
    // Allow the app to be terminated from dock or menu
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var tradingManager = TradingManager()
    @StateObject private var scannerManager = StockScannerManager()
    
    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainDashboardView()
                    .environmentObject(tradingManager)
                    .environmentObject(authManager)
                    .environmentObject(scannerManager)
                    .frame(minWidth: 1400, minHeight: 900)
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            // Pass scanner manager to AppDelegate for menu bar integration
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.setScannerManager(scannerManager)
            }
            
            // Start the scanner immediately on app launch
            // This ensures gapper data is available even before the scanner view is opened
            scannerManager.loadScannerSummary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                scannerManager.loadFilteredStocks()
            }
            
            // Set up periodic refresh every 30 seconds
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                scannerManager.refreshScanner()
            }
        }
        .onReceive(authManager.$isAuthenticated) { isAuth in
            if isAuth {
                appState.isAuthenticated = true
                appState.currentUser = authManager.currentUser
                
                // Resize window for dashboard
                if let window = NSApplication.shared.windows.first {
                    window.setContentSize(NSSize(width: 1600, height: 1000))
                    window.center()
                }
            } else {
                appState.isAuthenticated = false
                appState.currentUser = nil
                
                // Resize window for login
                if let window = NSApplication.shared.windows.first {
                    window.setContentSize(NSSize(width: 500, height: 700))
                    window.center()
                }
            }
        }
        .onChange(of: appState.isAuthenticated) { isAuthenticated in
            if let window = NSApplication.shared.windows.first {
                if isAuthenticated {
                    // Dashboard size
                    window.setContentSize(NSSize(width: 1600, height: 1000))
                } else {
                    // Login size
                    window.setContentSize(NSSize(width: 500, height: 700))
                }
                window.center()
            }
        }
    }
}