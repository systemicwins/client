// THIS SERVICE IS DISABLED - DO NOT USE
// Streaming all stocks causes stale data issues (like NAKA appearing)
// Use GapperAPIClient or TradingManager.loadGappers() instead

// The original StreamService has been disabled to prevent:
// 1. Loading 8000+ stocks (performance issue)
// 2. Stale/cached data appearing in UI
// 3. Non-gapper stocks showing in trade tab

// CORRECT APPROACH:
// - Use TradingManager.loadGappers() to fetch only qualified gappers
// - Gappers are automatically sorted by gap % (descending)
// - Updates every 30 seconds during market hours
// - Only shows stocks meeting strict criteria (10%+ gap, $2-20, etc.)

class StreamService_DISABLED {
    static let shared = StreamService_DISABLED()
    
    init() {
        print("⚠️ StreamService is DISABLED - use TradingManager.loadGappers() instead")
    }
    
    func streamAllStocks(batchSize: Int = 100) {
        fatalError("DO NOT USE streamAllStocks - it causes stale data. Use TradingManager.loadGappers() instead")
    }
}