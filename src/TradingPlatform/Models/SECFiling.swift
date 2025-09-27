import Foundation

// MARK: - SEC Filing Models

struct SECFiling: Codable, Identifiable {
    let id = UUID()
    let symbol: String
    let filingDate: Date
    let formType: String
    let accessionNumber: String?  // Make optional - not always in FMP response
    let fileNumber: String?
    let filmNumber: String?
    let reportDate: Date?
    let acceptedDate: Date?
    let url: String
    let finalUrl: String?
    
    // Extracted financial data
    var financialData: FinancialData?
    
    // Local cache metadata
    var cachedDate: Date?
    var localFilePath: String?
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case filingDate = "fillingDate"  // FMP API uses "fillingDate" with double 'l'
        case formType = "type"  // FMP API uses "type" not "formType"
        case accessionNumber
        case fileNumber
        case filmNumber
        case reportDate
        case acceptedDate
        case url = "link"  // FMP API uses "link"
        case finalUrl = "finalLink"  // FMP API uses "finalLink"
        case financialData
        case cachedDate
        case localFilePath
    }
}

struct FinancialData: Codable {
    // Share structure
    let commonSharesOutstanding: Double?
    let preferredSharesOutstanding: Double?
    let totalSharesOutstanding: Double?
    
    // Ownership data
    let institutionalOwnership: Double?
    let insiderOwnership: Double?
    let floatShares: Double?
    let tradeableFloat: Double?
    
    // Key financial metrics for health analysis
    let totalAssets: Double?
    let totalLiabilities: Double?
    let totalEquity: Double?
    let revenue: Double?
    let netIncome: Double?
    let operatingCashFlow: Double?
    let freeCashFlow: Double?
    let debtToEquity: Double?
    let currentRatio: Double?
    let quickRatio: Double?
    
    // Calculated date for this data
    let dataDate: Date
    
    var calculatedTradeableFloat: Double {
        // If we have explicit tradeable float, use it
        if let tradeableFloat = tradeableFloat {
            return tradeableFloat
        }
        
        // Otherwise calculate: Total - Institutional - Insider
        guard let total = totalSharesOutstanding ?? commonSharesOutstanding else {
            return 0
        }
        
        let institutional = institutionalOwnership ?? 0
        let insider = insiderOwnership ?? 0
        
        return max(0, total - institutional - insider)
    }
}

// MARK: - Historical Float Data Point

struct SECFloatDataPoint: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let tradeableFloat: Double
    let totalShares: Double
    let institutionalOwnership: Double
    let insiderOwnership: Double
    let source: String // "10-K", "10-Q", "DEF 14A", etc.
    
    var floatPercentage: Double {
        guard totalShares > 0 else { return 0 }
        return (tradeableFloat / totalShares) * 100
    }
}

// MARK: - Insider Transaction Model (from FMP API)

struct InsiderTransaction: Codable {
    let symbol: String
    let reportingName: String
    let filingDate: String // Keep as String, parse later
    let transactionDate: String?
    let transactionType: String // "P" = Purchase, "S" = Sale, etc.
    let securitiesTransacted: Int
    let securitiesOwned: Int
    let typeOfOwner: String // "director", "officer", "10% owner", etc.
    let formType: String? // "4", "3", etc.
    
    var parsedFilingDate: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(filingDate.prefix(10))) ?? Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case reportingName
        case filingDate = "fillingDate"
        case transactionDate
        case transactionType
        case securitiesTransacted
        case securitiesOwned
        case typeOfOwner
        case formType
    }
}

// MARK: - Institutional Holder Model (from FMP API)

struct InstitutionalHolder: Codable {
    let holder: String
    let shares: Int
    let dateReported: String // Keep as String
    let change: Int?
    let changePercentage: Double?
    
    var parsedDateReported: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(dateReported.prefix(10))) ?? Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case holder
        case shares
        case dateReported
        case change
        case changePercentage = "changePercent"
    }
}

// MARK: - Enterprise Value Model (for shares outstanding history)

struct EnterpriseValue: Codable {
    let symbol: String
    let date: String // Keep as String
    let marketCapitalization: Double?
    let enterpriseValue: Double?
    let numberOfShares: Double?
    
    var parsedDate: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(date.prefix(10))) ?? Date()
    }
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case date
        case marketCapitalization
        case enterpriseValue
        case numberOfShares
    }
}

// MARK: - Historical Data Models

struct SharesOutstandingData: Codable {
    let date: Date
    let sharesOutstanding: Double
    let source: String // "FMP", "Polygon", "SEC Filing"
}

struct InsiderOwnershipData: Codable {
    let date: Date
    let insiderShares: Double
    let insiderPercentage: Double?
    let source: String // "insider-trading", "insider-ownership"
}

struct InstitutionalOwnershipData: Codable {
    let date: Date
    let institutionalShares: Double
    let institutionalPercentage: Double?
    let numberOfInstitutions: Int?
    let source: String // "institutional-holder"
}

struct QuarterlyFloatData: Codable, Identifiable {
    let id = UUID()
    let quarter: String // "2024-Q1"
    let date: Date
    let sharesOutstanding: Double
    let institutionalOwnership: Double
    let insiderOwnership: Double
    let tradeableFloat: Double
    let floatPercentage: Double
    let dataQuality: DataQuality
    let sources: [String]
    
    enum DataQuality: String, Codable {
        case high = "high"      // All data sources available
        case medium = "medium"  // Some data estimated
        case low = "low"        // Mostly estimated
    }
}

// MARK: - SEC Filing Cache Entry

struct SECFilingCacheEntry: Codable {
    let symbol: String
    var timestamp: Date
    let filings: [SECFiling]
    var floatHistory: [SECFloatDataPoint]?
    let quarterlyFloatHistory: [QuarterlyFloatData]? // New enhanced data
}