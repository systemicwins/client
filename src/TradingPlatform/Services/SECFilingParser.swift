import Foundation
import SwiftSoup

/// Parser for SEC filing documents to extract exact ownership and transaction data
class SECFilingParser {
    static let shared = SECFilingParser()
    
    private let session = URLSession.shared
    
    // MARK: - Models for Parsed Data
    
    struct Form4Transaction {
        let transactionDate: Date
        let transactionCode: String // P = Purchase, S = Sale, A = Award, M = Exercise, etc.
        let shares: Double
        let pricePerShare: Double?
        let sharesOwnedFollowing: Double
        let isDirect: Bool
        let isDerivative: Bool
        let securityTitle: String
        let ownerName: String
        let ownerRelationship: String // Director, Officer, 10% Owner
    }
    
    struct Form13FHolding {
        let nameOfIssuer: String
        let shares: Double
        let value: Double
        let putCall: String? // PUT, CALL, or nil
        let investmentDiscretion: String
        let votingAuthority: VotingAuthority
        
        struct VotingAuthority {
            let sole: Double
            let shared: Double
            let none: Double
        }
    }
    
    struct SC13Filing {
        let filingDate: Date
        let beneficialOwner: String
        let sharesOwned: Double
        let percentOfClass: Double
        let purposeOfTransaction: String
    }
    
    struct DEF14AData {
        let meetingDate: Date?
        let sharesOutstanding: Double?
        let insiderOwnership: InsiderOwnership?
        let institutionalOwnership: Double?
        
        struct InsiderOwnership {
            let directors: Double
            let officers: Double
            let total: Double
        }
    }
    
    // MARK: - Main Parsing Function
    
    func parseSecFiling(_ filing: SECFiling) async throws -> ParsedFilingData? {
        let finalUrl = filing.finalUrl ?? filing.url
        
        // Fetch the filing document
        guard let url = URL(string: finalUrl) else {
            print("Invalid URL: \(finalUrl)")
            return nil
        }
        let (data, _) = try await session.data(from: url)
        
        // Parse based on form type
        switch filing.formType {
        case "4":
            return try parseForm4(data, filing: filing)
        case "3":
            return try parseForm3(data, filing: filing)
        case "13F-HR", "13F-HR/A":
            return try parseForm13F(data, filing: filing)
        case "SC 13G", "SC 13G/A", "SC 13D", "SC 13D/A":
            return try parseSC13(data, filing: filing)
        case "DEF 14A":
            return try parseDEF14A(data, filing: filing)
        case "10-K", "10-Q":
            return try parse10K10Q(data, filing: filing)
        case "8-K":
            return try parse8K(data, filing: filing)
        default:
            print("Unsupported form type: \(filing.formType)")
            return nil
        }
    }
    
    // MARK: - Form 4 Parser (Insider Trading)
    
    private func parseForm4(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        
        var transactions: [Form4Transaction] = []
        var totalSharesAcquired: Double = 0
        var totalSharesDisposed: Double = 0
        
        // Parse XML structure
        if xmlString.contains("<ownershipDocument>") {
            // Parse XML format Form 4
            transactions = try parseForm4XML(xmlString, filingDate: filing.filingDate)
        } else if xmlString.contains("<!DOCTYPE html") || xmlString.contains("<html") {
            // Parse HTML format Form 4
            transactions = try parseForm4HTML(xmlString, filingDate: filing.filingDate)
        }
        
        // Calculate net change
        for transaction in transactions {
            if ["P", "A", "M", "G"].contains(transaction.transactionCode) {
                totalSharesAcquired += transaction.shares
            } else if ["S", "D", "F"].contains(transaction.transactionCode) {
                totalSharesDisposed += transaction.shares
            }
        }
        
        let netChange = totalSharesAcquired - totalSharesDisposed
        
        return ParsedFilingData(
            formType: "4",
            filingDate: filing.filingDate,
            sharesAcquired: totalSharesAcquired,
            sharesDisposed: totalSharesDisposed,
            netShareChange: netChange,
            totalSharesOwned: transactions.last?.sharesOwnedFollowing,
            transactions: transactions,
            rawData: [:],
            impactOnFloat: -netChange // Negative because insider buying reduces float
        )
    }
    
    private func parseForm4XML(_ xml: String, filingDate: Date) throws -> [Form4Transaction] {
        var transactions: [Form4Transaction] = []
        
        // Extract owner information
        let ownerName = extractXMLValue(xml, tag: "rptOwnerName") ?? "Unknown"
        var ownerRelationship = ""
        if xml.contains("<isDirector>1</isDirector>") || xml.contains("<isDirector>true</isDirector>") {
            ownerRelationship = "Director"
        }
        if xml.contains("<isOfficer>1</isOfficer>") || xml.contains("<isOfficer>true</isOfficer>") {
            ownerRelationship += ownerRelationship.isEmpty ? "Officer" : ", Officer"
        }
        if xml.contains("<isTenPercentOwner>1</isTenPercentOwner>") || xml.contains("<isTenPercentOwner>true</isTenPercentOwner>") {
            ownerRelationship += ownerRelationship.isEmpty ? "10% Owner" : ", 10% Owner"
        }
        
        // Parse non-derivative transactions
        let nonDerivativePattern = "<nonDerivativeTransaction>(.*?)</nonDerivativeTransaction>"
        let nonDerivativeMatches = xml.groups(for: nonDerivativePattern)
        
        for match in nonDerivativeMatches {
            let transactionXML = match[1]
            
            let dateStr = extractXMLValue(transactionXML, tag: "transactionDate") ?? ""
            let date = parseDate(dateStr)
            
            let code = extractXMLValue(transactionXML, tag: "transactionCode") ?? ""
            let shares = Double(extractXMLValue(transactionXML, tag: "transactionShares") ?? "0") ?? 0
            let pricePerShare = Double(extractXMLValue(transactionXML, tag: "transactionPricePerShare") ?? "0")
            let sharesAfter = Double(extractXMLValue(transactionXML, tag: "sharesOwnedFollowingTransaction") ?? "0") ?? 0
            let isDirect = extractXMLValue(transactionXML, tag: "directOrIndirectOwnership")?.contains("D") ?? true
            let securityTitle = extractXMLValue(transactionXML, tag: "securityTitle") ?? "Common Stock"
            
            transactions.append(Form4Transaction(
                transactionDate: date ?? filingDate,
                transactionCode: code,
                shares: shares,
                pricePerShare: pricePerShare,
                sharesOwnedFollowing: sharesAfter,
                isDirect: isDirect,
                isDerivative: false,
                securityTitle: securityTitle,
                ownerName: ownerName,
                ownerRelationship: ownerRelationship
            ))
        }
        
        // Parse derivative transactions (options, warrants, etc.)
        let derivativePattern = "<derivativeTransaction>(.*?)</derivativeTransaction>"
        let derivativeMatches = xml.groups(for: derivativePattern)
        
        for match in derivativeMatches {
            let transactionXML = match[1]
            
            let dateStr = extractXMLValue(transactionXML, tag: "transactionDate") ?? ""
            let date = parseDate(dateStr)
            
            let code = extractXMLValue(transactionXML, tag: "transactionCode") ?? ""
            let shares = Double(extractXMLValue(transactionXML, tag: "transactionShares") ?? "0") ?? 0
            let pricePerShare = Double(extractXMLValue(transactionXML, tag: "conversionOrExercisePrice") ?? "0")
            let underlyingShares = Double(extractXMLValue(transactionXML, tag: "underlyingSecurityShares") ?? "0") ?? 0
            let securityTitle = extractXMLValue(transactionXML, tag: "securityTitle") ?? "Derivative"
            
            // For derivatives, we care about the underlying shares
            if underlyingShares > 0 {
                transactions.append(Form4Transaction(
                    transactionDate: date ?? filingDate,
                    transactionCode: code,
                    shares: underlyingShares,
                    pricePerShare: pricePerShare,
                    sharesOwnedFollowing: 0, // Not directly applicable for derivatives
                    isDirect: true,
                    isDerivative: true,
                    securityTitle: securityTitle,
                    ownerName: ownerName,
                    ownerRelationship: ownerRelationship
                ))
            }
        }
        
        return transactions
    }
    
    private func parseForm4HTML(_ html: String, filingDate: Date) throws -> [Form4Transaction] {
        // Parse HTML format (older filings)
        let doc = try SwiftSoup.parse(html)
        var transactions: [Form4Transaction] = []
        
        // Try to find the transaction table
        let tables = try doc.select("table")
        for table in tables {
            let rows = try table.select("tr")
            
            for row in rows {
                let cells = try row.select("td")
                if cells.count >= 6 {
                    // Basic parsing of table data
                    // This would need to be adjusted based on actual HTML structure
                    let shares = Double(try cells[2].text().replacingOccurrences(of: ",", with: "")) ?? 0
                    if shares > 0 {
                        transactions.append(Form4Transaction(
                            transactionDate: filingDate,
                            transactionCode: "P", // Default to purchase
                            shares: shares,
                            pricePerShare: nil,
                            sharesOwnedFollowing: 0,
                            isDirect: true,
                            isDerivative: false,
                            securityTitle: "Common Stock",
                            ownerName: "Unknown",
                            ownerRelationship: "Unknown"
                        ))
                    }
                }
            }
        }
        
        return transactions
    }
    
    // MARK: - Form 3 Parser (Initial Statement)
    
    private func parseForm3(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        
        var totalShares: Double = 0
        
        if xmlString.contains("<ownershipDocument>") {
            // Parse holdings
            let holdingPattern = "<sharesOwnedFollowingTransaction>(.*?)</sharesOwnedFollowingTransaction>"
            let matches = xmlString.groups(for: holdingPattern)
            
            for match in matches {
                let shares = Double(match[1]) ?? 0
                totalShares += shares
            }
            
            // If no transactions, look for initial holdings
            if totalShares == 0 {
                let initialPattern = "<numberOfShares>(.*?)</numberOfShares>"
                let initialMatches = xmlString.groups(for: initialPattern)
                for match in initialMatches {
                    let shares = Double(match[1]) ?? 0
                    totalShares += shares
                }
            }
        }
        
        return ParsedFilingData(
            formType: "3",
            filingDate: filing.filingDate,
            sharesAcquired: totalShares,
            sharesDisposed: 0,
            netShareChange: totalShares,
            totalSharesOwned: totalShares,
            transactions: [],
            rawData: ["initialHolding": totalShares],
            impactOnFloat: -totalShares // Initial holding reduces float
        )
    }
    
    // MARK: - Form 13F Parser (Institutional Holdings)
    
    private func parseForm13F(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        
        var totalShares: Double = 0
        var holdings: [Form13FHolding] = []
        
        if xmlString.contains("<informationTable>") {
            // Parse XML format 13F
            let infoTablePattern = "<infoTable>(.*?)</infoTable>"
            let matches = xmlString.groups(for: infoTablePattern)
            
            for match in matches {
                let holdingXML = match[1]
                
                let nameOfIssuer = extractXMLValue(holdingXML, tag: "nameOfIssuer") ?? ""
                let cusip = extractXMLValue(holdingXML, tag: "cusip") ?? ""
                let shares = Double(extractXMLValue(holdingXML, tag: "sshPrnamt") ?? "0") ?? 0
                let value = Double(extractXMLValue(holdingXML, tag: "value") ?? "0") ?? 0
                let putCall = extractXMLValue(holdingXML, tag: "putCall")
                
                // Only count if it's for the company we're analyzing
                // In practice, we'd need to match CUSIP or name
                if filing.symbol.lowercased() == nameOfIssuer.lowercased().prefix(4) {
                    totalShares += shares
                    
                    holdings.append(Form13FHolding(
                        nameOfIssuer: nameOfIssuer,
                        shares: shares,
                        value: value * 1000, // Value is in thousands
                        putCall: putCall,
                        investmentDiscretion: extractXMLValue(holdingXML, tag: "investmentDiscretion") ?? "SOLE",
                        votingAuthority: Form13FHolding.VotingAuthority(
                            sole: Double(extractXMLValue(holdingXML, tag: "votingAuthority_Sole") ?? "0") ?? shares,
                            shared: Double(extractXMLValue(holdingXML, tag: "votingAuthority_Shared") ?? "0") ?? 0,
                            none: Double(extractXMLValue(holdingXML, tag: "votingAuthority_None") ?? "0") ?? 0
                        )
                    ))
                }
            }
        }
        
        return ParsedFilingData(
            formType: "13F-HR",
            filingDate: filing.filingDate,
            sharesAcquired: totalShares,
            sharesDisposed: 0,
            netShareChange: totalShares,
            totalSharesOwned: totalShares,
            transactions: [],
            rawData: ["holdings": holdings.count, "totalValue": holdings.reduce(0) { $0 + $1.value }],
            impactOnFloat: -totalShares // Institutional ownership reduces float
        )
    }
    
    // MARK: - SC 13D/G Parser (5%+ Ownership)
    
    private func parseSC13(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let doc = try SwiftSoup.parse(htmlString)
        
        var sharesOwned: Double = 0
        var percentOwned: Double = 0
        
        // Look for common patterns in SC 13D/G filings
        let text = try doc.text()
        
        // Pattern: "beneficially owns X shares"
        let ownsPattern = "beneficially owns?\\s+([\\d,]+)\\s+shares?"
        if let match = text.range(of: ownsPattern, options: .regularExpression) {
            let numberStr = String(text[match]).replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "beneficially owns", with: "")
                .replacingOccurrences(of: "shares", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sharesOwned = Double(numberStr) ?? 0
        }
        
        // Pattern: "X% of the outstanding"
        let percentPattern = "([\\d.]+)%\\s+of\\s+the\\s+outstanding"
        if let match = text.range(of: percentPattern, options: .regularExpression) {
            let percentStr = String(text[match]).replacingOccurrences(of: "% of the outstanding", with: "")
            percentOwned = Double(percentStr) ?? 0
        }
        
        return ParsedFilingData(
            formType: filing.formType,
            filingDate: filing.filingDate,
            sharesAcquired: sharesOwned,
            sharesDisposed: 0,
            netShareChange: sharesOwned,
            totalSharesOwned: sharesOwned,
            transactions: [],
            rawData: ["percentOwned": percentOwned],
            impactOnFloat: -sharesOwned // Large holder reduces float
        )
    }
    
    // MARK: - DEF 14A Parser (Proxy Statement)
    
    private func parseDEF14A(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let doc = try SwiftSoup.parse(htmlString)
        
        let text = try doc.text()
        
        var sharesOutstanding: Double = 0
        var insiderOwnership: Double = 0
        
        // Look for shares outstanding
        let outstandingPattern = "([\\d,]+)\\s+shares?\\s+(?:of\\s+)?(?:common\\s+stock\\s+)?outstanding"
        if let match = text.range(of: outstandingPattern, options: [.regularExpression, .caseInsensitive]) {
            let numberStr = String(text[match])
                .replacingOccurrences(of: ",", with: "")
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined()
            sharesOutstanding = Double(numberStr) ?? 0
        }
        
        // Look for insider ownership percentages
        let insiderPattern = "(?:directors?|officers?|insiders?).*?own.*?([\\d.]+)%"
        if let match = text.range(of: insiderPattern, options: [.regularExpression, .caseInsensitive]) {
            let percentStr = String(text[match])
                .components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")))
                .joined()
            let percent = Double(percentStr) ?? 0
            insiderOwnership = sharesOutstanding * (percent / 100)
        }
        
        return ParsedFilingData(
            formType: "DEF 14A",
            filingDate: filing.filingDate,
            sharesAcquired: 0,
            sharesDisposed: 0,
            netShareChange: 0,
            totalSharesOwned: insiderOwnership,
            transactions: [],
            rawData: ["sharesOutstanding": sharesOutstanding, "insiderPercent": (insiderOwnership / sharesOutstanding) * 100],
            impactOnFloat: 0 // Proxy statement is informational
        )
    }
    
    // MARK: - 10-K/10-Q Parser
    
    private func parse10K10Q(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let doc = try SwiftSoup.parse(htmlString)
        
        let text = try doc.text()
        
        var sharesOutstanding: Double = 0
        
        // Look for shares outstanding in various formats
        let patterns = [
            "([\\d,]+)\\s+shares?\\s+(?:of\\s+)?(?:common\\s+stock\\s+)?(?:were\\s+)?outstanding",
            "common\\s+stock\\s+outstanding.*?([\\d,]+)\\s+shares?",
            "shares?\\s+outstanding.*?([\\d,]+)"
        ]
        
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let numberStr = String(text[match])
                    .replacingOccurrences(of: ",", with: "")
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .filter { !$0.isEmpty }
                    .last ?? ""
                
                if let shares = Double(numberStr), shares > 0 {
                    sharesOutstanding = shares
                    break
                }
            }
        }
        
        // If shares are in thousands or millions, adjust
        if sharesOutstanding > 0 && sharesOutstanding < 10000 {
            if text.contains("(in thousands)") || text.contains("thousands of shares") {
                sharesOutstanding *= 1000
            } else if text.contains("(in millions)") || text.contains("millions of shares") {
                sharesOutstanding *= 1_000_000
            }
        }
        
        return ParsedFilingData(
            formType: filing.formType,
            filingDate: filing.filingDate,
            sharesAcquired: 0,
            sharesDisposed: 0,
            netShareChange: 0,
            totalSharesOwned: 0,
            transactions: [],
            rawData: ["sharesOutstanding": sharesOutstanding],
            impactOnFloat: 0 // Base filing, no direct impact
        )
    }
    
    // MARK: - 8-K Parser
    
    private func parse8K(_ data: Data, filing: SECFiling) throws -> ParsedFilingData {
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let doc = try SwiftSoup.parse(htmlString)
        
        let text = try doc.text()
        
        var eventInfo: [String: Any] = [:]
        
        // Check for specific 8-K items that affect float
        if text.contains("Item 3.02") || text.contains("Unregistered Sales") {
            // Unregistered sales of equity securities
            let sharesPattern = "([\\d,]+)\\s+shares?\\s+of\\s+common\\s+stock"
            if let match = text.range(of: sharesPattern, options: .regularExpression) {
                let numberStr = String(text[match])
                    .replacingOccurrences(of: ",", with: "")
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                let shares = Double(numberStr) ?? 0
                eventInfo["unregisteredShares"] = shares
                
                return ParsedFilingData(
                    formType: "8-K",
                    filingDate: filing.filingDate,
                    sharesAcquired: shares,
                    sharesDisposed: 0,
                    netShareChange: shares,
                    totalSharesOwned: 0,
                    transactions: [],
                    rawData: eventInfo,
                    impactOnFloat: shares // New shares increase float
                )
            }
        }
        
        return ParsedFilingData(
            formType: "8-K",
            filingDate: filing.filingDate,
            sharesAcquired: 0,
            sharesDisposed: 0,
            netShareChange: 0,
            totalSharesOwned: 0,
            transactions: [],
            rawData: eventInfo,
            impactOnFloat: 0
        )
    }
    
    // MARK: - Helper Functions
    
    private func extractXMLValue(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        if let range = xml.range(of: pattern, options: .regularExpression) {
            let match = String(xml[range])
            return match
                .replacingOccurrences(of: "<\(tag)>", with: "")
                .replacingOccurrences(of: "</\(tag)>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "MM-dd-yyyy",
            "yyyyMMdd"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Parsed Filing Data Model

struct ParsedFilingData {
    let formType: String
    let filingDate: Date
    let sharesAcquired: Double
    let sharesDisposed: Double
    let netShareChange: Double
    let totalSharesOwned: Double?
    let transactions: [SECFilingParser.Form4Transaction]
    let rawData: [String: Any]
    let impactOnFloat: Double // Positive = increases float, Negative = decreases float
    
    var description: String {
        switch formType {
        case "4":
            if netShareChange > 0 {
                return "Insider acquired \(Int(sharesAcquired)) shares"
            } else if netShareChange < 0 {
                return "Insider sold \(Int(sharesDisposed)) shares"
            } else {
                return "Insider transaction (no net change)"
            }
        case "3":
            return "Initial insider holding: \(Int(sharesAcquired)) shares"
        case "13F-HR":
            return "Institutional holding: \(Int(sharesAcquired)) shares"
        case "SC 13G", "SC 13D":
            return "5%+ owner holds \(Int(sharesAcquired)) shares"
        default:
            return "\(formType) filing"
        }
    }
}

// MARK: - String Extension for Regex

extension String {
    func groups(for regexPattern: String) -> [[String]] {
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            return matches.map { match in
                (0..<match.numberOfRanges).map {
                    let rangeBounds = match.range(at: $0)
                    guard let range = Range(rangeBounds, in: self) else {
                        return ""
                    }
                    return String(self[range])
                }
            }
        } catch {
            return []
        }
    }
}