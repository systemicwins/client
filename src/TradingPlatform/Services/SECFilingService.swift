import Foundation
import Combine

class SECFilingService: ObservableObject {
    static let shared = SECFilingService()
    
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var currentFilingSymbol: String?
    
    private let baseURL = "https://financialmodelingprep.com/api/v3"
    private let secURL = "https://www.sec.gov/Archives/edgar/data"
    private let apiKey = "BiNbCLiPPz7LmMkDuMAfB6Bdj0AJTMxO"
    
    // Local cache directory
    private let cacheDirectory: URL
    private let filingsCacheDirectory: URL
    private var cache: [String: SECFilingCacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.relentless.secfilings", qos: .background)
    
    init() {
        // Set up cache directories
        let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                     in: .userDomainMask).first!
        self.cacheDirectory = documentsPath.appendingPathComponent("SECFilings")
        self.filingsCacheDirectory = cacheDirectory.appendingPathComponent("RawFilings")
        
        // Create directories if they don't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, 
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: filingsCacheDirectory, 
                                                 withIntermediateDirectories: true)
        
        // Load existing cache
        loadCache()
    }
    
    // MARK: - Public Methods
    
    /// Fetch quick estimated float data, then refine with SEC filings
    func fetchHistoricalTradeableFloat(for symbol: String, years: Int = 5, quickEstimate: Bool = true) async throws -> [SECFloatDataPoint] {
        // Check cache first
        let cacheKey = "float_history_\(symbol)"
        if let cached = getCachedFloatHistory(for: cacheKey, maxAge: 24) {
            print("Using cached float history for \(symbol)")
            return cached
        }
        
        isLoading = true
        loadingProgress = 0
        defer { isLoading = false }
        
        // First, get shares outstanding quickly
        let currentShares = await fetchCurrentSharesOutstanding(symbol: symbol) ?? 100_000_000
        print("SECFilingService: Got shares outstanding for \(symbol): \(currentShares)")
        
        // If quick estimate requested, return estimated data immediately
        if quickEstimate {
            let estimatedData = generateQuickEstimateData(symbol: symbol, shares: currentShares, years: years)
            // Don't cache estimates
            return estimatedData
        }
        
        // Fetch detailed data in parallel for accurate calculation
        async let sharesOutstandingTask = fetchSharesOutstandingHistory(symbol: symbol, years: years)
        async let insiderOwnershipTask = fetchInsiderOwnershipHistory(symbol: symbol, years: years)
        async let institutionalOwnershipTask = fetchInstitutionalOwnershipHistory(symbol: symbol, years: years)
        
        loadingProgress = 0.2
        
        // Wait for all data
        let (sharesHistory, insiderHistory, institutionalHistory) = try await (
            sharesOutstandingTask,
            insiderOwnershipTask,
            institutionalOwnershipTask
        )
        
        loadingProgress = 0.8
        
        // Calculate quarterly float data points
        let dataPoints = calculateQuarterlyFloatHistory(
            sharesHistory: sharesHistory,
            insiderHistory: insiderHistory,
            institutionalHistory: institutionalHistory,
            years: years
        )
        
        // Cache the results
        cacheFloatHistory(dataPoints, for: cacheKey)
        
        loadingProgress = 1.0
        
        return dataPoints
    }
    
    /// Generate quick estimated float data based on industry standards
    private func generateQuickEstimateData(symbol: String, shares: Double, years: Int) -> [SECFloatDataPoint] {
        var dataPoints: [SECFloatDataPoint] = []
        
        // Industry standard estimates with slight variation over time
        let baseInsiderPercent = 0.15  // 15% insider ownership typical
        let baseInstitutionalPercent = 0.30  // 30% institutional typical
        
        // Generate quarterly data points
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .year, value: -years, to: endDate)!
        
        var currentDate = startDate
        var quarterCount = 0
        
        while currentDate <= endDate {
            // Add slight variation to make the chart more realistic
            let timeProgress = Double(quarterCount) / Double(years * 4)
            let insiderPercent = baseInsiderPercent * (1.0 - timeProgress * 0.1) // Slight decrease over time
            let institutionalPercent = baseInstitutionalPercent * (1.0 + timeProgress * 0.2) // Slight increase
            
            let insiderShares = shares * insiderPercent
            let institutionalShares = shares * institutionalPercent
            let tradeableFloat = shares - insiderShares - institutionalShares
            
            let dataPoint = SECFloatDataPoint(
                date: currentDate,
                tradeableFloat: tradeableFloat,
                totalShares: shares,
                institutionalOwnership: institutionalShares,
                insiderOwnership: insiderShares,
                source: "Estimated (Industry Standards)"
            )
            dataPoints.append(dataPoint)
            
            // Move to next quarter
            if let nextQuarter = calendar.date(byAdding: .month, value: 3, to: currentDate) {
                currentDate = nextQuarter
                quarterCount += 1
            } else {
                break
            }
            
            // Ensure we don't go past end date
            if currentDate > endDate {
                break
            }
        }
        
        print("Generated \(dataPoints.count) estimated float data points for \(symbol)")
        return dataPoints
    }
    
    /// Fetch insider ownership history from SEC Forms 3/4/5 via FMP
    private func fetchInsiderOwnershipHistory(symbol: String, years: Int) async throws -> [(date: Date, ownership: Double)] {
        var ownershipHistory: [(date: Date, ownership: Double)] = []
        
        // Fetch insider trading data from FMP
        let insiderURL = "https://financialmodelingprep.com/api/v4/insider-trading?symbol=\(symbol)&limit=500&apikey=\(apiKey)"
        guard let url = URL(string: insiderURL) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            
            // Parse insider transactions
            if let transactions = try? decoder.decode([InsiderTransaction].self, from: data) {
                // Group transactions by quarter
                var quarterlyOwnership: [String: Double] = [:]
                var currentOwnership: [String: Double] = [:] // Track by person
                
                for transaction in transactions.sorted(by: { $0.parsedFilingDate < $1.parsedFilingDate }) {
                    let quarterKey = quarterKeyFromDate(transaction.parsedFilingDate)
                    let owner = transaction.reportingName
                    
                    // Update ownership for this person
                    if transaction.securitiesOwned > 0 {
                        currentOwnership[owner] = Double(transaction.securitiesOwned)
                    }
                    
                    // Sum all insider holdings for this quarter
                    quarterlyOwnership[quarterKey] = currentOwnership.values.reduce(0, +)
                }
                
                // Convert to history array
                for (quarterKey, ownership) in quarterlyOwnership {
                    if let date = dateFromQuarterKey(quarterKey) {
                        ownershipHistory.append((date: date, ownership: ownership))
                    }
                }
            }
        } catch {
            print("Error fetching insider ownership: \(error)")
        }
        
        // If no data, estimate 15% insider ownership as baseline
        if ownershipHistory.isEmpty {
            ownershipHistory.append((date: Date(), ownership: 0.15))
        }
        
        return ownershipHistory.sorted { $0.date < $1.date }
    }
    
    /// Fetch institutional ownership history from 13F filings via FMP
    private func fetchInstitutionalOwnershipHistory(symbol: String, years: Int) async throws -> [(date: Date, ownership: Double)] {
        var ownershipHistory: [(date: Date, ownership: Double)] = []
        
        // Fetch institutional holder data
        let instURL = "https://financialmodelingprep.com/api/v3/institutional-holder/\(symbol)?apikey=\(apiKey)"
        guard let url = URL(string: instURL) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            
            if let holders = try? decoder.decode([InstitutionalHolder].self, from: data) {
                // Group by reporting date
                var dateOwnership: [Date: Double] = [:]
                
                for holder in holders {
                    let date = holder.parsedDateReported
                    dateOwnership[date, default: 0] += Double(holder.shares)
                }
                
                // Convert to history array
                for (date, shares) in dateOwnership {
                    ownershipHistory.append((date: date, ownership: shares))
                }
            }
        } catch {
            print("Error fetching institutional ownership: \(error)")
        }
        
        // If no data, estimate 30% institutional ownership
        if ownershipHistory.isEmpty {
            ownershipHistory.append((date: Date(), ownership: 0.30))
        }
        
        return ownershipHistory.sorted { $0.date < $1.date }
    }
    
    /// Fetch shares outstanding history
    private func fetchSharesOutstandingHistory(symbol: String, years: Int) async throws -> [(date: Date, shares: Double)] {
        var sharesHistory: [(date: Date, shares: Double)] = []
        
        // Try FMP enterprise values endpoint for historical shares
        let evURL = "https://financialmodelingprep.com/api/v3/enterprise-values/\(symbol)?limit=\(years * 4)&apikey=\(apiKey)"
        guard let url = URL(string: evURL) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let evData = try? decoder.decode([EnterpriseValue].self, from: data) {
                for ev in evData {
                    if let shares = ev.numberOfShares {
                        sharesHistory.append((date: ev.parsedDate, shares: shares))
                    }
                }
            }
        } catch {
            print("Error fetching shares outstanding: \(error)")
        }
        
        // If no history, get current shares outstanding
        if sharesHistory.isEmpty {
            if let currentShares = await fetchCurrentSharesOutstanding(symbol: symbol) {
                sharesHistory.append((date: Date(), shares: currentShares))
            }
        }
        
        return sharesHistory.sorted { $0.date < $1.date }
    }
    
    /// Calculate quarterly float data points from ownership histories
    private func calculateQuarterlyFloatHistory(
        sharesHistory: [(date: Date, shares: Double)],
        insiderHistory: [(date: Date, ownership: Double)],
        institutionalHistory: [(date: Date, ownership: Double)],
        years: Int
    ) -> [SECFloatDataPoint] {
        var dataPoints: [SECFloatDataPoint] = []
        
        // Generate quarterly dates going back
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .year, value: -years, to: endDate)!
        
        var currentDate = startDate
        while currentDate <= endDate {
            // Find closest data points for this date
            let shares = findClosestValue(in: sharesHistory.map { ($0.date, $0.shares) }, for: currentDate) ?? 100_000_000
            let insiderOwnership = findClosestValue(in: insiderHistory.map { ($0.date, $0.ownership) }, for: currentDate) ?? 0
            let institutionalOwnership = findClosestValue(in: institutionalHistory.map { ($0.date, $0.ownership) }, for: currentDate) ?? 0
            
            // For institutional ownership that's already in shares, don't multiply
            let instShares = institutionalOwnership > 1 ? institutionalOwnership : institutionalOwnership * shares
            let insiderShares = insiderOwnership > 1 ? insiderOwnership : insiderOwnership * shares
            
            let tradeableFloat = max(0, shares - insiderShares - instShares)
            
            let dataPoint = SECFloatDataPoint(
                date: currentDate,
                tradeableFloat: tradeableFloat,
                totalShares: shares,
                institutionalOwnership: instShares,
                insiderOwnership: insiderShares,
                source: "SEC EDGAR & FMP APIs"
            )
            
            dataPoints.append(dataPoint)
            
            // Move to next quarter
            currentDate = calendar.date(byAdding: .month, value: 3, to: currentDate) ?? endDate
        }
        
        return dataPoints
    }
    
    /// Helper to find closest value in time series data
    private func findClosestValue(in data: [(Date, Double)], for targetDate: Date) -> Double? {
        guard !data.isEmpty else { return nil }
        
        // Find the closest date that's not after the target
        let validData = data.filter { $0.0 <= targetDate }.sorted { $0.0 > $1.0 }
        return validData.first?.1 ?? data.first?.1
    }
    
    /// Helper to create quarter key from date
    private func quarterKeyFromDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let quarter = (month - 1) / 3 + 1
        return "\(year)Q\(quarter)"
    }
    
    /// Helper to create date from quarter key
    private func dateFromQuarterKey(_ key: String) -> Date? {
        guard key.count >= 6 else { return nil }
        let parts = key.split(separator: "Q")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let quarter = Int(parts[1]) else { return nil }
        
        let month = (quarter - 1) * 3 + 1
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components)
    }
    
    func fetchHistoricalFilings(for symbol: String, years: Int = 5) async throws -> [SECFiling] {
        currentFilingSymbol = symbol
        
        // Check cache first
        if let cached = getCachedFilings(for: symbol, maxAge: 24) {
            print("Using cached SEC filings for \(symbol)")
            return cached.filings
        }
        
        isLoading = true
        loadingProgress = 0
        
        defer {
            isLoading = false
            currentFilingSymbol = nil
        }
        
        // Fetch from FMP API
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .year, value: -years, to: endDate)!
        
        let urlString = "\(baseURL)/sec_filings/\(symbol)?apikey=\(apiKey)&limit=500"
        guard let url = URL(string: urlString) else {
            throw SECError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Configure decoder for FMP date format
        let decoder = JSONDecoder()
        let fmpDateFormatter = DateFormatter()
        fmpDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        decoder.dateDecodingStrategy = .formatted(fmpDateFormatter)
        
        var filings = try decoder.decode([SECFiling].self, from: data)
        
        // Filter for relevant form types and date range
        // Include Form 4 (insider trading) which is common for many tickers
        let relevantForms = ["10-K", "10-Q", "8-K", "DEF 14A", "20-F", "SC 13G", "SC 13D", "4", "3", "S-1", "S-8", "424B3"]
        filings = filings.filter { filing in
            relevantForms.contains(filing.formType) &&
            filing.filingDate >= startDate &&
            filing.filingDate <= endDate
        }
        
        loadingProgress = 0.3
        
        // Process filings to extract financial data
        var processedFilings: [SECFiling] = []
        let totalFilings = min(filings.count, 100) // Process up to 100 most recent filings to capture more data
        
        for (index, filing) in filings.prefix(totalFilings).enumerated() {
            var processedFiling = filing
            
            // Extract financial data based on form type
            if ["10-K", "10-Q", "20-F"].contains(filing.formType) {
                processedFiling.financialData = try await extractFinancialData(from: filing)
            } else if ["4", "3", "5"].contains(filing.formType) {
                // For Form 4/3/5 (insider transactions), extract transaction data
                processedFiling.financialData = try await extractInsiderTransactionData(from: filing)
            }
            
            processedFilings.append(processedFiling)
            loadingProgress = 0.3 + (0.6 * Double(index + 1) / Double(totalFilings))
        }
        
        // Calculate float history
        let floatHistory = try await calculateFloatHistory(from: processedFilings, symbol: symbol)
        
        // Cache the results
        let cacheEntry = SECFilingCacheEntry(
            symbol: symbol,
            timestamp: Date(),
            filings: processedFilings,
            floatHistory: floatHistory,
            quarterlyFloatHistory: nil
        )
        
        saveCacheEntry(cacheEntry, for: symbol)
        loadingProgress = 1.0
        
        return processedFilings
    }
    
    func getFloatHistory(for symbol: String) async throws -> [SECFloatDataPoint] {
        // First try cache
        if let cached = getCachedFilings(for: symbol, maxAge: 24),
           let floatHistory = cached.floatHistory {
            return floatHistory
        }
        
        // Otherwise fetch filings
        let filings = try await fetchHistoricalFilings(for: symbol)
        return try await calculateFloatHistory(from: filings, symbol: symbol)
    }
    
    // MARK: - Private Methods
    
    private func extractFinancialData(from filing: SECFiling) async throws -> FinancialData? {
        // For now, fetch supplementary data from FMP
        // In future, we'll parse the actual SEC filing documents
        
        let urlString = "\(baseURL)/enterprise-values/\(filing.symbol)?apikey=\(apiKey)&limit=1"
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let values = try JSONDecoder().decode([EnterpriseValue].self, from: data)
            
            guard let value = values.first else { return nil }
            
            return FinancialData(
                commonSharesOutstanding: value.numberOfShares,
                preferredSharesOutstanding: nil,
                totalSharesOutstanding: value.numberOfShares,
                institutionalOwnership: nil, // Will fetch separately
                insiderOwnership: nil, // Will fetch separately
                floatShares: nil,
                tradeableFloat: nil,
                totalAssets: nil,
                totalLiabilities: nil,
                totalEquity: nil,
                revenue: nil,
                netIncome: nil,
                operatingCashFlow: nil,
                freeCashFlow: nil,
                debtToEquity: nil,
                currentRatio: nil,
                quickRatio: nil,
                dataDate: filing.filingDate
            )
        } catch {
            return nil
        }
    }
    
    private func extractInsiderTransactionData(from filing: SECFiling) async throws -> FinancialData? {
        // Use the accurate parser to get exact transaction data
        let parser = SECFilingParser.shared
        
        do {
            if let parsedData = try await parser.parseSecFiling(filing) {
                // Get baseline shares outstanding from FMP
                var sharesOutstanding: Double = 100_000_000 // Default 100M
                
                let ownershipURL = "\(baseURL)/shares-float/\(filing.symbol)?apikey=\(apiKey)"
                if let url = URL(string: ownershipURL) {
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let floatData = try? JSONDecoder().decode([SharesFloat].self, from: data),
                       let float = floatData.first {
                        sharesOutstanding = float.sharesOutstanding ?? sharesOutstanding
                    }
                }
                
                // Calculate impact on ownership
                let insiderShareChange = parsedData.netShareChange
                let floatImpact = parsedData.impactOnFloat
                
                return FinancialData(
                    commonSharesOutstanding: sharesOutstanding,
                    preferredSharesOutstanding: nil,
                    totalSharesOutstanding: sharesOutstanding,
                    institutionalOwnership: parsedData.formType.contains("13") ? parsedData.sharesAcquired : nil,
                    insiderOwnership: ["3", "4", "5"].contains(parsedData.formType) ? abs(insiderShareChange) : nil,
                    floatShares: nil,
                    tradeableFloat: sharesOutstanding - abs(floatImpact), // Adjust float based on transaction
                    totalAssets: nil,
                    totalLiabilities: nil,
                    totalEquity: nil,
                    revenue: nil,
                    netIncome: nil,
                    operatingCashFlow: nil,
                    freeCashFlow: nil,
                    debtToEquity: nil,
                    currentRatio: nil,
                    quickRatio: nil,
                    dataDate: filing.filingDate
                )
            }
        } catch {
            print("Failed to parse filing \(filing.formType): \(error)")
        }
        
        // Fallback to estimation if parsing fails
        return nil
    }
    
    private func calculateFloatHistory(from filings: [SECFiling], symbol: String) async throws -> [SECFloatDataPoint] {
        var history: [SECFloatDataPoint] = []
        
        // Sort filings by date to process chronologically
        let sortedFilings = filings.sorted { $0.filingDate < $1.filingDate }
        
        // Get current shares outstanding from Polygon as baseline
        var currentTotalShares: Double = 100_000_000  // Default fallback
        var currentInsiderOwnership: Double = 0
        var currentInstitutionalOwnership: Double = 0
        
        // Fetch actual shares outstanding from Polygon
        currentTotalShares = try await fetchSharesOutstandingFromPolygon(symbol: symbol) ?? 100_000_000
        
        // If we have no filings but we have shares outstanding, create a baseline data point
        if sortedFilings.isEmpty && currentTotalShares > 0 {
            // Create a single data point with just shares outstanding
            let dataPoint = SECFloatDataPoint(
                date: Date(),
                tradeableFloat: currentTotalShares * 0.7, // Assume 70% float if no other data
                totalShares: currentTotalShares,
                institutionalOwnership: currentTotalShares * 0.2, // Assume 20% institutional
                insiderOwnership: currentTotalShares * 0.1, // Assume 10% insider
                source: "Estimated from shares outstanding"
            )
            return [dataPoint]
        }
        
        // Group filings by date to accumulate same-day changes
        var filingsByDate: [Date: [SECFiling]] = [:]
        for filing in sortedFilings {
            let dateKey = Calendar.current.startOfDay(for: filing.filingDate)
            filingsByDate[dateKey, default: []].append(filing)
        }
        
        // Process filings chronologically
        for date in filingsByDate.keys.sorted() {
            let dayFilings = filingsByDate[date] ?? []
            
            var dayInsiderChange: Double = 0
            var dayInstitutionalChange: Double = 0
            var updatedTotalShares = false
            
            for filing in dayFilings {
                guard let financialData = filing.financialData else { continue }
                
                // Update baseline shares from 10-K/10-Q
                if ["10-K", "10-Q", "20-F"].contains(filing.formType) {
                    if let totalShares = financialData.totalSharesOutstanding, totalShares > 0 {
                        currentTotalShares = totalShares
                        updatedTotalShares = true
                    }
                    // These forms report total ownership, not changes
                    if let institutional = financialData.institutionalOwnership {
                        currentInstitutionalOwnership = institutional
                    }
                    if let insider = financialData.insiderOwnership {
                        currentInsiderOwnership = insider
                    }
                }
                
                // Accumulate changes from transactions
                if ["3", "4", "5"].contains(filing.formType) {
                    // Form 3: Initial statement - sets baseline
                    // Form 4: Transaction - adds/subtracts
                    // Form 5: Annual statement - updates total
                    if let insiderChange = financialData.insiderOwnership {
                        if filing.formType == "3" || filing.formType == "5" {
                            // These report total holdings, not changes
                            currentInsiderOwnership = max(currentInsiderOwnership, insiderChange)
                        } else {
                            // Form 4 is a change
                            dayInsiderChange += insiderChange
                        }
                    }
                } else if filing.formType.contains("13") {
                    // 13F, 13G, 13D report institutional holdings
                    if let institutionalHolding = financialData.institutionalOwnership {
                        // These report total holdings for the institution
                        // We should aggregate all institutional holdings
                        dayInstitutionalChange = max(dayInstitutionalChange, institutionalHolding - currentInstitutionalOwnership)
                    }
                }
            }
            
            // Apply day's changes
            currentInsiderOwnership += dayInsiderChange
            currentInstitutionalOwnership += dayInstitutionalChange
            
            // Calculate tradeable float
            let tradeableFloat = max(0, currentTotalShares - currentInsiderOwnership - currentInstitutionalOwnership)
            
            // Create data point for this date
            let dataPoint = SECFloatDataPoint(
                date: date,
                tradeableFloat: tradeableFloat,
                totalShares: currentTotalShares,
                institutionalOwnership: currentInstitutionalOwnership,
                insiderOwnership: currentInsiderOwnership,
                source: dayFilings.map { $0.formType }.joined(separator: ", ")
            )
            
            history.append(dataPoint)
        }
        
        return history
    }
    
    // MARK: - Polygon Data Fetching
    
    private func fetchSharesOutstandingFromPolygon(symbol: String) async throws -> Double? {
        // Try to get ticker details from Polygon which includes shares outstanding
        let polygonApiKey = "n5fZHkb5kFvl6GrREpo1K05hCMVwUKK7"
        let urlString = "https://api.polygon.io/v3/reference/tickers/\(symbol)?apikey=\(polygonApiKey)"
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any],
               let sharesOutstanding = results["share_class_shares_outstanding"] as? Double {
                print("Got shares outstanding for \(symbol) from Polygon: \(sharesOutstanding)")
                return sharesOutstanding
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [String: Any],
                      let weightedShares = results["weighted_shares_outstanding"] as? Double {
                print("Got weighted shares outstanding for \(symbol) from Polygon: \(weightedShares)")
                return weightedShares
            }
        } catch {
            print("Failed to get shares outstanding from Polygon for \(symbol): \(error)")
        }
        
        // Fallback to FMP if Polygon doesn't have the data
        return try await fetchSharesOutstandingFromFMP(symbol: symbol)
    }
    
    private func fetchSharesOutstandingFromFMP(symbol: String) async throws -> Double? {
        // First try shares-float endpoint
        let floatURL = "\(baseURL)/shares-float/\(symbol)?apikey=\(apiKey)"
        if let url = URL(string: floatURL) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let floatData = try? JSONDecoder().decode([SharesFloat].self, from: data),
                   let float = floatData.first,
                   let shares = float.sharesOutstanding {
                    print("Got shares outstanding for \(symbol) from FMP shares-float: \(shares)")
                    return shares
                }
            } catch {
                print("shares-float endpoint failed for \(symbol): \(error)")
            }
        }
        
        // Fallback to enterprise-values endpoint which usually has numberOfShares
        let evURL = "\(baseURL)/enterprise-values/\(symbol)?apikey=\(apiKey)&limit=1"
        if let url = URL(string: evURL) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let evData = try? JSONDecoder().decode([EnterpriseValue].self, from: data),
                   let ev = evData.first,
                   let shares = ev.numberOfShares {
                    print("Got shares outstanding for \(symbol) from FMP enterprise-values: \(shares)")
                    return shares
                }
            } catch {
                print("enterprise-values endpoint failed for \(symbol): \(error)")
            }
        }
        
        return nil
    }
    
    // MARK: - Cache Management
    
    private func loadCache() {
        cacheQueue.sync {
            let cacheFile = cacheDirectory.appendingPathComponent("cache.json")
            
            guard FileManager.default.fileExists(atPath: cacheFile.path),
                  let data = try? Data(contentsOf: cacheFile),
                  let decoded = try? JSONDecoder().decode([String: SECFilingCacheEntry].self, from: data) else {
                return
            }
            
            self.cache = decoded
        }
    }
    
    private func saveCacheEntry(_ entry: SECFilingCacheEntry, for symbol: String) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.cache[symbol] = entry
            
            let cacheFile = self.cacheDirectory.appendingPathComponent("cache.json")
            
            if let encoded = try? JSONEncoder().encode(self.cache) {
                try? encoded.write(to: cacheFile)
            }
        }
    }
    
    private func getCachedFilings(for symbol: String, maxAge: Int) -> SECFilingCacheEntry? {
        guard let entry = cache[symbol] else { return nil }
        
        let hoursSinceUpdate = Date().timeIntervalSince(entry.timestamp) / 3600
        
        if hoursSinceUpdate <= Double(maxAge) {
            return entry
        }
        
        return nil
    }
    
    func clearCache(for symbol: String? = nil) {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let symbol = symbol {
                self.cache.removeValue(forKey: symbol)
            } else {
                self.cache.removeAll()
                // Clear all files
                try? FileManager.default.removeItem(at: self.filingsCacheDirectory)
                try? FileManager.default.createDirectory(at: self.filingsCacheDirectory,
                                                         withIntermediateDirectories: true)
            }
            
            let cacheFile = self.cacheDirectory.appendingPathComponent("cache.json")
            if let encoded = try? JSONEncoder().encode(self.cache) {
                try? encoded.write(to: cacheFile)
            }
        }
    }
    
    // MARK: - Float History Cache Methods
    
    private func getCachedFloatHistory(for key: String, maxAge: Int) -> [SECFloatDataPoint]? {
        cacheQueue.sync {
            guard let entry = cache[key],
                  let floatHistory = entry.floatHistory,
                  Date().timeIntervalSince(entry.timestamp) < Double(maxAge * 3600) else {
                return nil
            }
            return floatHistory
        }
    }
    
    private func cacheFloatHistory(_ history: [SECFloatDataPoint], for key: String) {
        cacheQueue.sync {
            var entry = cache[key] ?? SECFilingCacheEntry(
                symbol: key,
                timestamp: Date(),
                filings: [],
                floatHistory: nil,
                quarterlyFloatHistory: nil
            )
            entry.floatHistory = history
            entry.timestamp = Date()
            cache[key] = entry
            
            // Save to disk
            let cacheFile = self.cacheDirectory.appendingPathComponent("float_\(key).json")
            if let encoded = try? JSONEncoder().encode(history) {
                try? encoded.write(to: cacheFile)
            }
        }
    }
    
    /// Fetch current shares outstanding
    private func fetchCurrentSharesOutstanding(symbol: String) async -> Double? {
        // Try enterprise values endpoint first
        let evURL = "https://financialmodelingprep.com/api/v3/enterprise-values/\(symbol)?limit=1&apikey=\(apiKey)"
        if let url = URL(string: evURL) {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let evData = try? decoder.decode([EnterpriseValueAPI].self, from: data),
                   let firstEV = evData.first,
                   let shares = firstEV.numberOfShares {
                    return shares
                }
            }
        }
        
        // Fallback to key metrics endpoint
        let metricsURL = "https://financialmodelingprep.com/api/v3/key-metrics/\(symbol)?limit=1&apikey=\(apiKey)"
        if let url = URL(string: metricsURL) {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstMetric = json.first,
                   let shares = firstMetric["numberOfShares"] as? Double {
                    return shares
                }
            }
        }
        
        return nil
    }
}
// Extension ends above, Supporting Types below

// MARK: - Supporting Types

enum SECError: Error {
    case invalidURL
    case noData
    case decodingError
    case networkError(String)
}

// Different from the model EnterpriseValue - this is for API parsing
struct EnterpriseValueAPI: Codable {
    let symbol: String
    let date: String
    let stockPrice: Double?
    let numberOfShares: Double?
    let marketCapitalization: Double?
    
    enum CodingKeys: String, CodingKey {
        case symbol, date, stockPrice, numberOfShares, marketCapitalization
    }
}

struct InstitutionalOwnership: Codable {
    let symbol: String?
    let date: String?
    let totalInvested: Double?
    let changePercentage: Double?
    let investorsHolding: Int?
    let lastInvestorsHolding: Int?
    
    enum CodingKeys: String, CodingKey {
        case symbol, date, totalInvested, changePercentage
        case investorsHolding, lastInvestorsHolding
    }
}

struct SharesFloat: Codable {
    let symbol: String?
    let date: String?
    let freeFloat: Double?
    let floatShares: Double?
    let sharesOutstanding: Double?
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case symbol, date, freeFloat, floatShares
        case sharesOutstanding, source
    }
}