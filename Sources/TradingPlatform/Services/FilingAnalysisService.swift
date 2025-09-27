import Foundation
import SwiftUI

// Service to analyze SEC filings for ownership and financial health metrics
class FilingAnalysisService: ObservableObject {
    static let shared = FilingAnalysisService()
    
    // MARK: - Analysis Results Models
    
    struct OwnershipAnalysis {
        let insiderOwnershipPercent: Double
        let institutionalOwnershipPercent: Double
        let recentInsiderBuys: Int
        let recentInsiderSells: Int
        let netInsiderActivity: Double // Net shares bought/sold
        let majorHolders: [MajorHolder]
        let insiderTransactions: [InsiderTransaction]
        let ownershipTrend: OwnershipTrend
    }
    
    struct MajorHolder {
        let name: String
        let shares: Double
        let percentOwned: Double
        let filingDate: Date
        let filingType: String // SC 13D, SC 13G, 13F
    }
    
    struct InsiderTransaction {
        let insiderName: String
        let title: String
        let transactionType: String // Buy/Sell
        let shares: Double
        let pricePerShare: Double?
        let value: Double?
        let date: Date
        let remainingShares: Double
    }
    
    enum OwnershipTrend {
        case increasing
        case decreasing
        case stable
        case mixed
    }
    
    struct FinancialHealthAnalysis {
        let revenue: Double?
        let revenueGrowthYoY: Double?
        let grossMargin: Double?
        let operatingMargin: Double?
        let netMargin: Double?
        let debtToEquity: Double?
        let currentRatio: Double?
        let quickRatio: Double?
        let freeCashFlow: Double?
        let cashOnHand: Double?
        let returnOnEquity: Double?
        let returnOnAssets: Double?
        let earningsPerShare: Double?
        let priceToEarnings: Double?
        let healthScore: HealthScore
        let trends: [String] // Key trends identified
        let risks: [String] // Key risks from Risk Factors section
    }
    
    enum HealthScore {
        case excellent
        case good
        case fair
        case poor
        case critical
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return Color.green.opacity(0.7)
            case .fair: return .yellow
            case .poor: return .orange
            case .critical: return .red
            }
        }
        
        var description: String {
            switch self {
            case .excellent: return "Excellent Financial Health"
            case .good: return "Good Financial Health"
            case .fair: return "Fair Financial Health"
            case .poor: return "Poor Financial Health"
            case .critical: return "Critical Financial Condition"
            }
        }
    }
    
    // MARK: - Analysis Methods
    
    /// Analyze filings for ownership patterns
    func analyzeOwnership(from filings: [EDGARService.EDGARFiling]) -> OwnershipAnalysis {
        var insiderBuys = 0
        var insiderSells = 0
        var netInsiderShares: Double = 0
        var insiderTransactions: [InsiderTransaction] = []
        var majorHolders: [MajorHolder] = []
        
        // Process Form 4 filings (insider transactions)
        let form4Filings = filings.filter { $0.type == "4" || $0.type.contains("Form 4") }
        for filing in form4Filings {
            // Parse Form 4 content for transaction details
            if let transaction = parseForm4(filing) {
                insiderTransactions.append(transaction)
                if transaction.transactionType.lowercased().contains("buy") || 
                   transaction.transactionType.lowercased().contains("acquisition") {
                    insiderBuys += 1
                    netInsiderShares += transaction.shares
                } else if transaction.transactionType.lowercased().contains("sell") || 
                          transaction.transactionType.lowercased().contains("disposition") {
                    insiderSells += 1
                    netInsiderShares -= transaction.shares
                }
            }
        }
        
        // Process SC 13D/G filings (5%+ ownership)
        let sc13Filings = filings.filter { filing in
            filing.type.contains("SC 13") || filing.type.contains("13D") || filing.type.contains("13G")
        }
        for filing in sc13Filings {
            if let holder = parseSC13Filing(filing) {
                majorHolders.append(holder)
            }
        }
        
        // Process DEF 14A (proxy statements) for insider/institutional ownership
        let proxyFilings = filings.filter { $0.type.contains("DEF 14A") || $0.type.contains("PROXY") }
        let (insiderPercent, institutionalPercent) = parseProxyForOwnership(proxyFilings.first)
        
        // Determine ownership trend
        let trend: OwnershipTrend
        if insiderBuys > insiderSells * 2 {
            trend = .increasing
        } else if insiderSells > insiderBuys * 2 {
            trend = .decreasing
        } else if abs(insiderBuys - insiderSells) <= 2 {
            trend = .stable
        } else {
            trend = .mixed
        }
        
        return OwnershipAnalysis(
            insiderOwnershipPercent: insiderPercent,
            institutionalOwnershipPercent: institutionalPercent,
            recentInsiderBuys: insiderBuys,
            recentInsiderSells: insiderSells,
            netInsiderActivity: netInsiderShares,
            majorHolders: majorHolders.sorted { $0.percentOwned > $1.percentOwned },
            insiderTransactions: insiderTransactions.sorted { $0.date > $1.date },
            ownershipTrend: trend
        )
    }
    
    /// Analyze filings for financial health metrics
    func analyzeFinancialHealth(from filings: [EDGARService.EDGARFiling], currentPrice: Double? = nil) -> FinancialHealthAnalysis {
        // Get the most recent 10-K and 10-Q filings
        let annualReports = filings.filter { $0.type.contains("10-K") }.sorted { 
            Date(filing: $0.filingDate) > Date(filing: $1.filingDate) 
        }
        let quarterlyReports = filings.filter { $0.type.contains("10-Q") }.sorted { 
            Date(filing: $0.filingDate) > Date(filing: $1.filingDate) 
        }
        
        let latestReport = quarterlyReports.first ?? annualReports.first
        let previousYearReport = annualReports.count > 1 ? annualReports[1] : nil
        
        // Extract financial metrics from sections
        var metrics = extractFinancialMetrics(from: latestReport)
        
        // Calculate YoY growth if we have previous year data
        if let previous = previousYearReport {
            let prevMetrics = extractFinancialMetrics(from: previous)
            if let currentRevenue = metrics["revenue"],
               let prevRevenue = prevMetrics["revenue"] {
                metrics["revenueGrowthYoY"] = ((currentRevenue - prevRevenue) / prevRevenue) * 100
            }
        }
        
        // Extract risk factors
        let risks = extractRiskFactors(from: annualReports.first)
        
        // Extract trends from MD&A section
        let trends = extractTrends(from: latestReport)
        
        // Calculate health score based on multiple factors
        let healthScore = calculateHealthScore(metrics: metrics)
        
        // Calculate P/E if we have current price and EPS
        var priceToEarnings: Double? = nil
        if let price = currentPrice, let eps = metrics["earningsPerShare"], eps > 0 {
            priceToEarnings = price / eps
        }
        
        return FinancialHealthAnalysis(
            revenue: metrics["revenue"],
            revenueGrowthYoY: metrics["revenueGrowthYoY"],
            grossMargin: metrics["grossMargin"],
            operatingMargin: metrics["operatingMargin"],
            netMargin: metrics["netMargin"],
            debtToEquity: metrics["debtToEquity"],
            currentRatio: metrics["currentRatio"],
            quickRatio: metrics["quickRatio"],
            freeCashFlow: metrics["freeCashFlow"],
            cashOnHand: metrics["cash"],
            returnOnEquity: metrics["returnOnEquity"],
            returnOnAssets: metrics["returnOnAssets"],
            earningsPerShare: metrics["earningsPerShare"],
            priceToEarnings: priceToEarnings,
            healthScore: healthScore,
            trends: trends,
            risks: risks
        )
    }
    
    // MARK: - Private Parsing Methods
    
    private func parseForm4(_ filing: EDGARService.EDGARFiling) -> InsiderTransaction? {
        // Parse Form 4 content for transaction details
        // This would parse the actual filing content
        // For now, returning mock data structure
        // Note: EDGARFiling doesn't have content property, would need full content fetch
        guard filing.hasFullContent else { return nil }
        
        // Basic parsing logic (would be more sophisticated in production)
        let transaction = InsiderTransaction(
            insiderName: "Parsed from filing",
            title: "Executive",
            transactionType: filing.type.contains("Buy") ? "Buy" : "Sell",
            shares: 1000,
            pricePerShare: nil,
            value: nil,
            date: Date(filing: filing.filingDate),
            remainingShares: 0
        )
        
        return transaction
    }
    
    private func parseSC13Filing(_ filing: EDGARService.EDGARFiling) -> MajorHolder? {
        // Parse SC 13D/G filing for major holder information
        // Note: EDGARFiling doesn't have content property, would need full content fetch
        guard filing.hasFullContent else { return nil }
        
        // Basic parsing (would extract from actual filing content)
        return MajorHolder(
            name: "Major Institution",
            shares: 1000000,
            percentOwned: 5.5,
            filingDate: Date(filing: filing.filingDate),
            filingType: filing.type
        )
    }
    
    private func parseProxyForOwnership(_ filing: EDGARService.EDGARFiling?) -> (insider: Double, institutional: Double) {
        // Parse DEF 14A proxy statement for ownership percentages
        // Note: EDGARFiling doesn't have content property, would need full content fetch
        guard let filing = filing, filing.hasFullContent else { 
            return (0, 0)
        }
        
        // Would parse actual proxy content for ownership tables
        // Returning example values
        return (insider: 12.5, institutional: 65.3)
    }
    
    private func extractFinancialMetrics(from filing: EDGARService.EDGARFiling?) -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        // Extract from filing sections if available
        if let sections = filing?.sections {
            // Look for financial statements section in the array
            let financialsContent = sections.joined(separator: " ")
            if !financialsContent.isEmpty {
                // Parse financial data (simplified example)
                metrics["revenue"] = parseNumber(from: financialsContent, pattern: "revenue|net sales")
                metrics["grossProfit"] = parseNumber(from: financialsContent, pattern: "gross profit")
                metrics["operatingIncome"] = parseNumber(from: financialsContent, pattern: "operating income")
                metrics["netIncome"] = parseNumber(from: financialsContent, pattern: "net income")
                metrics["cash"] = parseNumber(from: financialsContent, pattern: "cash and cash equivalents")
                metrics["totalDebt"] = parseNumber(from: financialsContent, pattern: "total debt|long-term debt")
                metrics["totalEquity"] = parseNumber(from: financialsContent, pattern: "total equity|shareholders' equity")
            }
            
            // Calculate ratios if we have the data
            if let revenue = metrics["revenue"], revenue > 0 {
                if let grossProfit = metrics["grossProfit"] {
                    metrics["grossMargin"] = (grossProfit / revenue) * 100
                }
                if let operatingIncome = metrics["operatingIncome"] {
                    metrics["operatingMargin"] = (operatingIncome / revenue) * 100
                }
                if let netIncome = metrics["netIncome"] {
                    metrics["netMargin"] = (netIncome / revenue) * 100
                }
            }
            
            if let debt = metrics["totalDebt"], let equity = metrics["totalEquity"], equity > 0 {
                metrics["debtToEquity"] = debt / equity
            }
        }
        
        return metrics
    }
    
    private func extractRiskFactors(from filing: EDGARService.EDGARFiling?) -> [String] {
        guard let sections = filing?.sections as? [String: Any],
              let riskFactors = sections["riskFactors"] as? String else {
            return []
        }
        
        // Extract key risk factors (simplified)
        var risks: [String] = []
        let riskPatterns = [
            "competition", "regulatory", "economic conditions", "supply chain",
            "cybersecurity", "intellectual property", "key personnel", "liquidity"
        ]
        
        for pattern in riskPatterns {
            if riskFactors.lowercased().contains(pattern) {
                risks.append(pattern.capitalized)
            }
        }
        
        return risks
    }
    
    private func extractTrends(from filing: EDGARService.EDGARFiling?) -> [String] {
        guard let sections = filing?.sections as? [String: Any],
              let mda = sections["mda"] as? String else {
            return []
        }
        
        // Extract trends from MD&A section
        var trends: [String] = []
        
        if mda.lowercased().contains("growth") {
            trends.append("Revenue Growth")
        }
        if mda.lowercased().contains("margin improvement") {
            trends.append("Margin Improvement")
        }
        if mda.lowercased().contains("cost reduction") {
            trends.append("Cost Reduction Initiatives")
        }
        if mda.lowercased().contains("expansion") {
            trends.append("Market Expansion")
        }
        
        return trends
    }
    
    private func calculateHealthScore(metrics: [String: Double]) -> HealthScore {
        var score = 0
        
        // Score based on margins
        if let grossMargin = metrics["grossMargin"] {
            if grossMargin > 40 { score += 2 }
            else if grossMargin > 25 { score += 1 }
        }
        
        if let operatingMargin = metrics["operatingMargin"] {
            if operatingMargin > 20 { score += 2 }
            else if operatingMargin > 10 { score += 1 }
        }
        
        // Score based on debt
        if let debtToEquity = metrics["debtToEquity"] {
            if debtToEquity < 0.5 { score += 2 }
            else if debtToEquity < 1.0 { score += 1 }
            else if debtToEquity > 2.0 { score -= 1 }
        }
        
        // Score based on growth
        if let growth = metrics["revenueGrowthYoY"] {
            if growth > 20 { score += 2 }
            else if growth > 5 { score += 1 }
            else if growth < -10 { score -= 1 }
        }
        
        // Determine health score
        if score >= 7 { return .excellent }
        else if score >= 5 { return .good }
        else if score >= 3 { return .fair }
        else if score >= 1 { return .poor }
        else { return .critical }
    }
    
    private func parseNumber(from text: String, pattern: String) -> Double? {
        // Simplified number extraction (would be more sophisticated in production)
        let regex = try? NSRegularExpression(pattern: "(\(pattern))[^0-9]*([0-9,]+(?:\\.[0-9]+)?)", options: .caseInsensitive)
        let matches = regex?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        if let match = matches?.first, match.numberOfRanges > 2 {
            let numberRange = match.range(at: 2)
            if let range = Range(numberRange, in: text) {
                let numberString = String(text[range]).replacingOccurrences(of: ",", with: "")
                return Double(numberString)
            }
        }
        
        return nil
    }
}

// Helper extension for date parsing
extension Date {
    init(filing dateString: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self = formatter.date(from: dateString) ?? Date()
    }
}