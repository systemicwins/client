import Foundation
import SwiftSoup

/// Robust extractor for SEC filing content sections
class SECFilingContentExtractor {
    
    /// Sections mapped to the 4 scoring axes
    struct ExtractedSections {
        var managementOutlook: [String] = []     // For Management Outlook score
        var riskAssessment: [String] = []        // For Risk Assessment score
        var financialPerformance: [String] = []  // For Financial Performance score
        var operationalHealth: [String] = []     // For Operational Health score
        
        var isEmpty: Bool {
            return managementOutlook.isEmpty && 
                   riskAssessment.isEmpty && 
                   financialPerformance.isEmpty && 
                   operationalHealth.isEmpty
        }
    }
    
    /// Extract sections from filing content based on form type
    static func extractSections(from content: String, formType: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Clean the content
        let cleanedContent = cleanHTML(content)
        
        // Extract based on form type
        switch formType.uppercased() {
        case "10-K", "10-K/A":
            sections = extract10KSections(from: cleanedContent)
        case "10-Q", "10-Q/A":
            sections = extract10QSections(from: cleanedContent)
        case "8-K":
            sections = extract8KSections(from: cleanedContent)
        case "DEF 14A", "DEFM14A":
            sections = extractProxyStatementSections(from: cleanedContent)
        case "20-F":
            sections = extract20FSections(from: cleanedContent)
        case "S-1", "S-1/A":
            sections = extractS1Sections(from: cleanedContent)
        default:
            // Generic extraction for other filing types
            sections = extractGenericSections(from: cleanedContent)
        }
        
        // If structured extraction failed, try paragraph-based extraction
        if sections.isEmpty {
            sections = extractByParagraphAnalysis(from: cleanedContent)
        }
        
        return sections
    }
    
    // MARK: - 10-K Annual Report Extraction
    
    private static func extract10KSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Management Outlook - Item 7 MD&A
        let mdaPatterns = [
            "item 7\\.\\s*management['']?s discussion and analysis",
            "management['']?s discussion and analysis of financial condition",
            "md&a of financial condition and results",
            "overview and outlook",
            "executive overview",
            "business outlook"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: mdaPatterns, maxLength: 5000)
        
        // Risk Assessment - Item 1A Risk Factors
        let riskPatterns = [
            "item 1a\\.\\s*risk factors",
            "risks? relating to our business",
            "risks? and uncertainties",
            "factors that may affect",
            "cautionary note regarding forward",
            "critical accounting policies and estimates"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 5000)
        
        // Financial Performance - Item 8 Financial Statements
        let financialPatterns = [
            "item 8\\.\\s*financial statements",
            "consolidated statements? of (?:operations?|income|comprehensive income)",
            "results of operations",
            "revenue recognition",
            "financial results",
            "quarterly financial data"
        ]
        sections.financialPerformance = extractMultipleMatches(from: content, patterns: financialPatterns, maxLength: 5000)
        
        // Operational Health - Item 1 Business & Item 2 Properties
        let operationalPatterns = [
            "item 1\\.\\s*business",
            "item 2\\.\\s*properties",
            "our business",
            "business strategy",
            "competitive strengths",
            "operations overview",
            "operational highlights",
            "segment information"
        ]
        sections.operationalHealth = extractMultipleMatches(from: content, patterns: operationalPatterns, maxLength: 5000)
        
        return sections
    }
    
    // MARK: - 10-Q Quarterly Report Extraction
    
    private static func extract10QSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Management Outlook - Item 2 MD&A (different item number than 10-K)
        let mdaPatterns = [
            "item 2\\.\\s*management['']?s discussion",
            "management['']?s discussion and analysis",
            "quarterly update",
            "three months ended",
            "nine months ended",
            "outlook for"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: mdaPatterns, maxLength: 4000)
        
        // Risk Assessment - Item 1A or Part II Item 1A
        let riskPatterns = [
            "item 1a\\.\\s*risk factors",
            "part ii.*item 1a",
            "material changes in.*risk",
            "new risk factors",
            "updated risk factors"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 4000)
        
        // Financial Performance - Item 1 Financial Statements
        let financialPatterns = [
            "item 1\\.\\s*financial statements",
            "condensed consolidated statements",
            "unaudited.*financial statements",
            "quarterly results",
            "three months ended.*revenue"
        ]
        sections.financialPerformance = extractMultipleMatches(from: content, patterns: financialPatterns, maxLength: 4000)
        
        // Operational Health - Recent developments and operations discussion
        let operationalPatterns = [
            "recent developments",
            "operational update",
            "business update",
            "segment results",
            "key performance indicators"
        ]
        sections.operationalHealth = extractMultipleMatches(from: content, patterns: operationalPatterns, maxLength: 4000)
        
        return sections
    }
    
    // MARK: - 8-K Current Report Extraction
    
    private static func extract8KSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // 8-K items that relate to each scoring axis
        
        // Management Outlook - Forward-looking items
        let managementPatterns = [
            "item 2\\.01.*acquisition",
            "item 2\\.02.*results of operations",
            "item 7\\.01.*regulation fd",
            "item 8\\.01.*other events",
            "guidance",
            "reaffirm",
            "outlook"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: managementPatterns, maxLength: 3000)
        
        // Risk Assessment - Material changes
        let riskPatterns = [
            "item 1\\.01.*bankruptcy",
            "item 1\\.02.*termination",
            "item 2\\.04.*triggering events",
            "item 2\\.05.*costs associated",
            "item 2\\.06.*material impairments",
            "item 4\\.02.*non-reliance"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 3000)
        
        // Financial Performance - Results and financial changes
        let financialPatterns = [
            "item 2\\.02.*results of operations",
            "earnings release",
            "financial results",
            "preliminary.*results",
            "revenue.*quarter"
        ]
        sections.financialPerformance = extractMultipleMatches(from: content, patterns: financialPatterns, maxLength: 3000)
        
        // Operational Health - Business changes
        let operationalPatterns = [
            "item 5\\.02.*departure of directors",
            "item 5\\.03.*amendments to articles",
            "item 1\\.03.*notice of delisting",
            "operational.*update",
            "restructuring"
        ]
        sections.operationalHealth = extractMultipleMatches(from: content, patterns: operationalPatterns, maxLength: 3000)
        
        return sections
    }
    
    // MARK: - DEF 14A Proxy Statement Extraction
    
    private static func extractProxyStatementSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Management Outlook - Executive compensation discussion
        let managementPatterns = [
            "compensation discussion and analysis",
            "cd&a",
            "letter to shareholders",
            "ceo letter",
            "business highlights",
            "company performance"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: managementPatterns, maxLength: 4000)
        
        // Risk Assessment - Governance and risk oversight
        let riskPatterns = [
            "risk oversight",
            "board.*risk management",
            "enterprise risk",
            "cybersecurity risk",
            "audit committee report"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 4000)
        
        // Financial Performance - Performance metrics
        let financialPatterns = [
            "performance metrics",
            "financial performance",
            "tsr performance",
            "peer group comparison",
            "say.*on.*pay"
        ]
        sections.financialPerformance = extractMultipleMatches(from: content, patterns: financialPatterns, maxLength: 4000)
        
        // Operational Health - Governance structure
        let operationalPatterns = [
            "corporate governance",
            "board composition",
            "director nominees",
            "board leadership",
            "shareholder proposals"
        ]
        sections.operationalHealth = extractMultipleMatches(from: content, patterns: operationalPatterns, maxLength: 4000)
        
        return sections
    }
    
    // MARK: - 20-F Foreign Private Issuer Extraction
    
    private static func extract20FSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Similar to 10-K but with different item numbers
        let mdaPatterns = [
            "item 5\\.\\s*operating and financial review",
            "operating results",
            "management discussion"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: mdaPatterns, maxLength: 4000)
        
        let riskPatterns = [
            "item 3\\.\\s*key information.*risk factors",
            "item 3d\\.\\s*risk factors",
            "risk factors"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 4000)
        
        return sections
    }
    
    // MARK: - S-1 Registration Statement Extraction
    
    private static func extractS1Sections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        let managementPatterns = [
            "prospectus summary",
            "our company",
            "our mission",
            "investment highlights"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: managementPatterns, maxLength: 4000)
        
        let riskPatterns = [
            "risk factors",
            "investing.*involves.*risk",
            "special note regarding"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 4000)
        
        return sections
    }
    
    // MARK: - Generic Section Extraction
    
    private static func extractGenericSections(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        // Generic patterns that work across filing types
        let managementPatterns = [
            "management.*(?:discussion|analysis|outlook|view)",
            "executive.*(?:summary|overview|commentary)",
            "ceo.*(?:letter|message|statement)",
            "strategic.*(?:priorities|initiatives|plan)"
        ]
        sections.managementOutlook = extractMultipleMatches(from: content, patterns: managementPatterns, maxLength: 3000)
        
        let riskPatterns = [
            "risk.*factor",
            "uncertaint",
            "cautionary.*statement",
            "forward.*looking.*statement"
        ]
        sections.riskAssessment = extractMultipleMatches(from: content, patterns: riskPatterns, maxLength: 3000)
        
        let financialPatterns = [
            "financial.*(?:result|performance|condition|statement)",
            "revenue",
            "earnings",
            "operating.*income"
        ]
        sections.financialPerformance = extractMultipleMatches(from: content, patterns: financialPatterns, maxLength: 3000)
        
        let operationalPatterns = [
            "business.*(?:overview|description|operations)",
            "segment.*(?:information|results|performance)",
            "operational.*(?:highlights|metrics|kpis)"
        ]
        sections.operationalHealth = extractMultipleMatches(from: content, patterns: operationalPatterns, maxLength: 3000)
        
        return sections
    }
    
    // MARK: - Paragraph-Based Analysis (Fallback)
    
    private static func extractByParagraphAnalysis(from content: String) -> ExtractedSections {
        var sections = ExtractedSections()
        
        let paragraphs = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 100 } // Only substantial paragraphs
        
        for paragraph in paragraphs.prefix(500) { // Analyze first 500 paragraphs
            let lower = paragraph.lowercased()
            
            // Management Outlook indicators
            if matchesManagementOutlook(lower) && sections.managementOutlook.joined().count < 5000 {
                sections.managementOutlook.append(paragraph)
            }
            
            // Risk Assessment indicators
            if matchesRiskAssessment(lower) && sections.riskAssessment.joined().count < 5000 {
                sections.riskAssessment.append(paragraph)
            }
            
            // Financial Performance indicators
            if matchesFinancialPerformance(lower) && sections.financialPerformance.joined().count < 5000 {
                sections.financialPerformance.append(paragraph)
            }
            
            // Operational Health indicators
            if matchesOperationalHealth(lower) && sections.operationalHealth.joined().count < 5000 {
                sections.operationalHealth.append(paragraph)
            }
        }
        
        return sections
    }
    
    // MARK: - Content Matching Functions
    
    private static func matchesManagementOutlook(_ text: String) -> Bool {
        let keywords = [
            "we believe", "we expect", "we anticipate", "we plan",
            "outlook", "guidance", "forecast", "projection",
            "strategy", "initiative", "opportunity", "growth",
            "confident", "optimistic", "positioned", "momentum"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    private static func matchesRiskAssessment(_ text: String) -> Bool {
        let keywords = [
            "risk", "uncertainty", "volatility", "adverse",
            "may not", "could harm", "might fail", "no assurance",
            "challenge", "threat", "exposure", "vulnerability",
            "contingenc", "litigation", "regulatory", "compliance"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    private static func matchesFinancialPerformance(_ text: String) -> Bool {
        let keywords = [
            "revenue", "sales", "earnings", "income", "profit",
            "margin", "cash flow", "ebitda", "eps", "growth rate",
            "quarter", "year-over-year", "yoy", "basis points",
            "financial results", "operating results"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    private static func matchesOperationalHealth(_ text: String) -> Bool {
        let keywords = [
            "operation", "efficiency", "productivity", "utilization",
            "capacity", "throughput", "yield", "performance",
            "customer", "client", "user", "subscriber", "retention",
            "churn", "acquisition", "engagement", "satisfaction"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    // MARK: - Helper Functions
    
    private static func extractMultipleMatches(from content: String, patterns: [String], maxLength: Int) -> [String] {
        var extractedTexts: [String] = []
        let lowercased = content.lowercased()
        
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                let matches = regex.matches(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased))
                
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let startIdx = range.lowerBound
                        var endIdx = content.index(startIdx, offsetBy: maxLength, limitedBy: content.endIndex) ?? content.endIndex
                        
                        // Try to end at sentence boundary
                        if let periodRange = content[startIdx..<endIdx].lastIndex(of: ".") {
                            endIdx = content.index(after: periodRange)
                        }
                        
                        let extractedText = String(content[startIdx..<endIdx])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if extractedText.count > 200 { // Minimum meaningful length
                            extractedTexts.append(extractedText)
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return extractedTexts
    }
    
    private static func cleanHTML(_ html: String) -> String {
        // Remove HTML tags but preserve text
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Remove script and style elements
            try doc.select("script").remove()
            try doc.select("style").remove()
            try doc.select("header").remove()
            try doc.select("footer").remove()
            
            // Get text content
            let text = try doc.text()
            
            // Clean up whitespace
            return text
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        } catch {
            // If HTML parsing fails, do basic cleanup
            return html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
    }
}