import Foundation
import SwiftUI

// Service to fetch real tradeable float data from FMP API
class SECFilingsService: ObservableObject {
    static let shared = SECFilingsService()
    
    private let baseURL = "https://relentless-trading-api-1008761209426.us-east1.run.app/api"
    private let session = URLSession.shared
    
    // MARK: - Models
    
    struct FloatData: Codable {
        let ticker: String
        let sharesOutstanding: Double
        let floatShares: Double
        let tradeableFloat: Double
        let tradeableFloatMillions: Double
        let insiderPercent: Double
        let institutionalPercent: Double
        let marketCap: Double
        let avgVolume: Double
        let price: Double
        let lastUpdated: String
        let dataQuality: String
        
        enum CodingKeys: String, CodingKey {
            case ticker
            case sharesOutstanding = "shares_outstanding"
            case floatShares = "float_shares"
            case tradeableFloat = "tradeable_float"
            case tradeableFloatMillions = "tradeable_float_millions"
            case insiderPercent = "insider_percent"
            case institutionalPercent = "institutional_percent"
            case marketCap = "market_cap"
            case avgVolume = "avg_volume"
            case price
            case lastUpdated = "last_updated"
            case dataQuality = "data_quality"
        }
    }
    
    struct FloatHistoryResponse: Codable {
        let ticker: String
        let currentFloat: Double
        let sharesOutstanding: Double
        let history: [FloatDataPoint]
        let events: [FloatEvent]
        
        enum CodingKeys: String, CodingKey {
            case ticker
            case currentFloat = "current_float"
            case sharesOutstanding = "shares_outstanding"
            case history
            case events
        }
    }
    
    struct FloatEvent: Codable {
        let date: String
        let formType: String
        let description: String
        let sharesAffected: Double
        let impactType: String
        let filings: [Filing]?
        
        enum CodingKeys: String, CodingKey {
            case date
            case formType = "form_type"
            case description
            case sharesAffected = "shares_affected"
            case impactType = "impact_type"
            case filings
        }
    }
    
    struct Filing: Codable {
        let date: String
        let formType: String
        let description: String
        let sharesAffected: Double
        let impactType: String
    }
    
    struct APIResponse<T: Codable>: Codable {
        let success: Bool
        let data: T?
        let error: String?
    }
    
    struct ErrorResponse: Codable {
        let success: Bool
        let error: String
        let ticker: String?
    }
    
    // MARK: - Public Methods
    
    /// Fetch tradeable float history from FMP - REAL DATA ONLY
    func fetchFloatHistory(for symbol: String, days: Int = 7) async throws -> [FloatDataPoint] {
        let endpoint = "\(baseURL)/sec/float-history/\(symbol)?days=\(days)"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw NSError(domain: "FMP", code: httpResponse.statusCode, 
                            userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        // Use custom date decoder that handles fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            // Fallback to standard ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        
        let apiResponse = try decoder.decode(APIResponse<FloatHistoryResponse>.self, from: data)
        
        if let floatHistory = apiResponse.data {
            return floatHistory.history
        } else {
            throw NSError(domain: "FMP", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "No float data available for \(symbol)"])
        }
    }
    
    /// Get current tradeable float data from FMP
    func fetchCurrentFloat(for symbol: String) async throws -> FloatData {
        let endpoint = "\(baseURL)/stock/\(symbol)/float"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw NSError(domain: "FMP", code: httpResponse.statusCode, 
                            userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(APIResponse<FloatData>.self, from: data)
        
        if let floatData = apiResponse.data {
            return floatData
        } else {
            throw NSError(domain: "FMP", code: 404, 
                        userInfo: [NSLocalizedDescriptionKey: apiResponse.error ?? "No float data available for \(symbol)"])
        }
    }
    
    /// Fetch SEC filings that affect float
    func fetchFloatAffectingFilings(for symbol: String, days: Int = 7) async throws -> [FloatEvent] {
        let endpoint = "\(baseURL)/sec/filings/\(symbol)?days=\(days)"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw NSError(domain: "FMP", code: httpResponse.statusCode, 
                            userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }
            throw URLError(.badServerResponse)
        }
        
        struct FilingsResponse: Codable {
            let success: Bool
            let data: [FloatEvent]
            let count: Int
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(FilingsResponse.self, from: data)
        
        return apiResponse.data
    }
    
    /// Batch fetch float data for multiple tickers
    func fetchFloatBatch(for tickers: [String]) async throws -> [String: FloatData] {
        let endpoint = "\(baseURL)/stock/float/batch"
        
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["tickers": tickers]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw NSError(domain: "FMP", code: httpResponse.statusCode, 
                            userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }
            throw URLError(.badServerResponse)
        }
        
        struct BatchResponse: Codable {
            let success: Bool
            let data: [String: FloatData]
            let errors: [BatchError]?
        }
        
        struct BatchError: Codable {
            let ticker: String
            let error: String
        }
        
        let decoder = JSONDecoder()
        let batchResponse = try decoder.decode(BatchResponse.self, from: data)
        
        if let errors = batchResponse.errors, !errors.isEmpty {
            print("Float batch fetch had errors for: \(errors.map { $0.ticker }.joined(separator: ", "))")
        }
        
        return batchResponse.data
    }
}