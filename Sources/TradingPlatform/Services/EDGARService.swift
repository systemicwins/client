import Foundation
import SwiftUI

// Service to fetch SEC EDGAR filings with full content from our API
class EDGARService: ObservableObject {
    static let shared = EDGARService()
    
    private let baseURL = "https://relentless-trading-api-1008761209426.us-east1.run.app/api/edgar"
    private let session = URLSession.shared
    
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0.0
    @Published var error: String?
    
    // MARK: - Models
    
    struct EDGARFiling: Codable {
        let type: String
        let filingDate: String
        let acceptedDate: String
        let contentUrl: String?
        let wordCount: Int?
        let hasFullContent: Bool
        let sections: [String]
        
        enum CodingKeys: String, CodingKey {
            case type
            case filingDate
            case acceptedDate
            case contentUrl
            case wordCount
            case hasFullContent
            case sections
        }
    }
    
    struct EDGARFilingsResponse: Codable {
        let success: Bool
        let data: FilingsData?
        let error: String?
    }
    
    struct FilingsData: Codable {
        let ticker: String
        let totalFilings: Int
        let filings: [EDGARFiling]
    }
    
    struct CompanyInfo: Codable {
        let ticker: String
        let companyName: String
        let cik: String
        let sic: String?
        let sicDescription: String?
        let exchanges: [String]
        let totalFilings: Int?
    }
    
    struct CompanyInfoResponse: Codable {
        let success: Bool
        let data: CompanyInfo?
        let error: String?
    }
    
    struct SearchRequest: Codable {
        let terms: [String]
        let filingTypes: [String]?
        let limit: Int?
        
        enum CodingKeys: String, CodingKey {
            case terms
            case filingTypes = "filing_types"
            case limit
        }
    }
    
    struct SearchResult: Codable {
        let type: String
        let filingDate: String
        let matchCount: Int
        let contexts: [String]?
        let relevance: Double?
        
        enum CodingKeys: String, CodingKey {
            case type
            case filingDate
            case matchCount
            case contexts
            case relevance
        }
    }
    
    struct SearchResponse: Codable {
        let success: Bool
        let data: SearchData?
        let error: String?
    }
    
    struct SearchData: Codable {
        let ticker: String
        let searchTerms: [String]
        let totalResults: Int
        let results: [SearchResult]
        
        enum CodingKeys: String, CodingKey {
            case ticker
            case searchTerms = "search_terms"
            case totalResults = "total_results"
            case results
        }
    }
    
    struct InsiderTransaction: Codable {
        let filingDate: String
        let reportingName: String
        let reportingCik: String
        let reportingTitle: String?
        let transactionDate: String
        let transactionType: String
        let shares: Double
        let pricePerShare: Double?
        let totalValue: Double?
        let sharesOwned: Double?
        
        enum CodingKeys: String, CodingKey {
            case filingDate
            case reportingName
            case reportingCik
            case reportingTitle
            case transactionDate
            case transactionType
            case shares
            case pricePerShare
            case totalValue
            case sharesOwned
        }
    }
    
    struct InsiderSummary: Codable {
        let totalTransactions: Int
        let uniqueInsiders: Int
        let totalBought: Double
        let totalSold: Double
        let netShares: Double
        let totalValueBought: Double
        let totalValueSold: Double
        
        enum CodingKeys: String, CodingKey {
            case totalTransactions = "total_transactions"
            case uniqueInsiders = "unique_insiders"
            case totalBought = "total_bought"
            case totalSold = "total_sold"
            case netShares = "net_shares"
            case totalValueBought = "total_value_bought"
            case totalValueSold = "total_value_sold"
        }
    }
    
    struct InsiderResponse: Codable {
        let success: Bool
        let data: InsiderData?
        let error: String?
    }
    
    struct InsiderData: Codable {
        let ticker: String
        let transactions: [InsiderTransaction]
        let summary: InsiderSummary
    }
    
    struct RAGRequest: Codable {
        let query: String
        let ticker: String
        let maxResults: Int?
        
        enum CodingKeys: String, CodingKey {
            case query
            case ticker
            case maxResults = "max_results"
        }
    }
    
    struct RAGResponse: Codable {
        let success: Bool
        let data: RAGData?
        let error: String?
    }
    
    struct RAGData: Codable {
        let query: String
        let ticker: String
        let relevantFilings: [RelevantFiling]?
        let answer: String?
        
        enum CodingKeys: String, CodingKey {
            case query
            case ticker
            case relevantFilings = "relevant_filings"
            case answer
        }
    }
    
    struct RelevantFiling: Codable {
        let type: String
        let date: String
        let relevance: Double
        let excerpt: String?
    }
    
    // MARK: - Public Methods
    
    /// Fetch SEC EDGAR filings for past N years with full content
    func fetchFilingsByYears(for symbol: String, years: Int = 5, types: [String] = ["10-K", "10-Q", "8-K", "DEF 14A"], includeFullContent: Bool = true) async throws -> [EDGARFiling] {
        let typesParam = types.joined(separator: ",")
        let endpoint = "\(baseURL)/\(symbol)/fetch-years?years=\(years)&types=\(typesParam)&fullContent=\(includeFullContent)"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        await MainActor.run {
            self.isLoading = true
            self.loadingProgress = 0.0
            self.error = nil
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
                self.loadingProgress = 1.0
            }
        }
        
        let (data, response) = try await session.data(from: url)
        
        // Update progress
        await MainActor.run {
            self.loadingProgress = 0.5
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run {
                self.error = errorMessage
            }
            throw NSError(domain: "EDGAR", code: httpResponse.statusCode, 
                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(EDGARFilingsResponse.self, from: data)
        
        await MainActor.run {
            self.loadingProgress = 1.0
        }
        
        if let filingsData = apiResponse.data {
            return filingsData.filings
        } else {
            let errorMsg = apiResponse.error ?? "No filings data available"
            await MainActor.run {
                self.error = errorMsg
            }
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    /// Fetch and store recent SEC EDGAR filings with full content
    func fetchAndStoreFilings(for symbol: String, types: [String] = ["10-K", "10-Q", "8-K"], limit: Int = 20) async throws -> [EDGARFiling] {
        let typesParam = types.joined(separator: ",")
        let endpoint = "\(baseURL)/\(symbol)/fetch?types=\(typesParam)&limit=\(limit)"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        await MainActor.run {
            self.isLoading = true
            self.loadingProgress = 0.0
            self.error = nil
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
                self.loadingProgress = 1.0
            }
        }
        
        let (data, response) = try await session.data(from: url)
        
        // Update progress
        await MainActor.run {
            self.loadingProgress = 0.5
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            await MainActor.run {
                self.error = errorMessage
            }
            throw NSError(domain: "EDGAR", code: httpResponse.statusCode, 
                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(EDGARFilingsResponse.self, from: data)
        
        await MainActor.run {
            self.loadingProgress = 1.0
        }
        
        if let filingsData = apiResponse.data {
            return filingsData.filings
        } else {
            let errorMsg = apiResponse.error ?? "No filings data available"
            await MainActor.run {
                self.error = errorMsg
            }
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }
    
    /// Get company information from SEC EDGAR
    func getCompanyInfo(for symbol: String) async throws -> CompanyInfo {
        let endpoint = "\(baseURL)/\(symbol)/info"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(CompanyInfoResponse.self, from: data)
        
        if let companyInfo = apiResponse.data {
            return companyInfo
        } else {
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "Company info not found"])
        }
    }
    
    /// Search for specific terms in SEC filings
    func searchFilings(for symbol: String, terms: [String], filingTypes: [String]? = nil, limit: Int = 10) async throws -> [SearchResult] {
        let endpoint = "\(baseURL)/\(symbol)/search"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let searchRequest = SearchRequest(terms: terms, filingTypes: filingTypes, limit: limit)
        request.httpBody = try JSONEncoder().encode(searchRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(SearchResponse.self, from: data)
        
        if let searchData = apiResponse.data {
            return searchData.results
        } else {
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "No search results found"])
        }
    }
    
    /// Get insider transactions from Form 4 filings
    func getInsiderTransactions(for symbol: String, days: Int = 30) async throws -> InsiderData {
        let endpoint = "\(baseURL)/\(symbol)/insider-transactions?days=\(days)"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(InsiderResponse.self, from: data)
        
        if let insiderData = apiResponse.data {
            return insiderData
        } else {
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "No insider transactions found"])
        }
    }
    
    /// Perform RAG query on SEC filings
    func performRAGQuery(query: String, ticker: String, maxResults: Int = 5) async throws -> RAGData {
        let endpoint = "\(baseURL)/rag"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let ragRequest = RAGRequest(query: query, ticker: ticker, maxResults: maxResults)
        request.httpBody = try JSONEncoder().encode(ragRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(RAGResponse.self, from: data)
        
        if let ragData = apiResponse.data {
            return ragData
        } else {
            throw NSError(domain: "EDGAR", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "RAG query failed"])
        }
    }
    
    /// Convert EDGAR filing to the existing SECFiling model for compatibility
    func convertToSECFiling(_ edgarFiling: EDGARFiling, symbol: String) -> SECFiling {
        // Parse dates from string format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let filingDate = dateFormatter.date(from: edgarFiling.filingDate) ?? Date()
        let acceptedDate = dateFormatter.date(from: edgarFiling.acceptedDate) ?? Date()
        
        return SECFiling(
            symbol: symbol,
            filingDate: filingDate,
            formType: edgarFiling.type,
            accessionNumber: nil,  // Not available from EDGAR API response
            fileNumber: nil,       // Not available from EDGAR API response
            filmNumber: nil,       // Not available from EDGAR API response
            reportDate: nil,       // Not available from EDGAR API response
            acceptedDate: acceptedDate,
            url: edgarFiling.contentUrl ?? "",
            finalUrl: edgarFiling.contentUrl,
            financialData: nil,    // Not parsed from EDGAR API
            cachedDate: nil,
            localFilePath: nil
        )
    }
}