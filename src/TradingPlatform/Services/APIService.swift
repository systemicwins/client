import Foundation
import Alamofire
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    
    private var baseURL: String
    private let session: Session
    private var authToken: String?
    
    // MARK: - Initialization
    private init() {
        self.baseURL = Self.ensureHTTPS(AppConfiguration.apiBaseURL)
        print("APIService initialized with baseURL: \(self.baseURL)")
        
        // Configure Alamofire session with custom settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        
        self.session = Session(configuration: configuration)
        
        // Load stored auth token
        loadStoredAuthToken()
    }
    
    // Update base URL
    static func updateBaseURL(_ newURL: String) {
        shared.baseURL = ensureHTTPS(newURL)
    }
    
    // MARK: - URL Security
    private static func ensureHTTPS(_ url: String) -> String {
        // Allow localhost connections to remain HTTP
        if url.contains("localhost") || url.contains("127.0.0.1") {
            if !url.contains("://") {
                return "http://\(url)"
            }
            return url
        }
        
        // If URL doesn't contain a protocol, add https://
        if !url.contains("://") {
            return "https://\(url)"
        }
        
        // If URL starts with http://, upgrade to https://
        if url.hasPrefix("http://") {
            return url.replacingOccurrences(of: "http://", with: "https://")
        }
        
        // Return URL as-is if it already uses https:// or other protocols
        return url
    }
    
    // MARK: - Authentication Management
    func setAuthToken(_ token: String) {
        self.authToken = token
        saveAuthToken(token)
    }
    
    func clearAuthToken() {
        self.authToken = nil
        removeStoredAuthToken()
    }
    
    private func loadStoredAuthToken() {
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            self.authToken = token
        }
    }
    
    private func saveAuthToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "auth_token")
    }
    
    private func removeStoredAuthToken() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }
    
    // MARK: - Headers
    private var defaultHeaders: HTTPHeaders {
        var headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        return headers
    }
    
    private var authenticatedHeaders: HTTPHeaders {
        var headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        return headers
    }
    
    // MARK: - Authentication Endpoints
    func login(email: String, password: String) -> AnyPublisher<LoginResponse, AFError> {
        let request = LoginRequest(email: email, password: password)
        let loginURL = "\(baseURL)/auth/login"
        
        print("Attempting login to: \(loginURL)")
        print("Login request: email=\(email)")
        
        return session.request(
            loginURL,
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: defaultHeaders
        )
        .validate()
        .responseData { response in
            print("Login response status: \(response.response?.statusCode ?? -1)")
            if let error = response.error {
                print("Login error: \(error)")
                if let underlyingError = error.underlyingError {
                    print("Underlying error: \(underlyingError)")
                }
            }
            if let data = response.data {
                let str = String(data: data, encoding: .utf8) ?? "no data"
                print("Response data: \(str)")
            }
        }
        .publishDecodable(type: LoginResponse.self, decoder: APIService.jsonDecoder)
        .value()
        .eraseToAnyPublisher()
    }
    
    func register(email: String, password: String, name: String) -> AnyPublisher<LoginResponse, AFError> {
        let request = RegisterRequest(email: email, password: password, name: name)
        
        return session.request(
            "\(baseURL)/auth/register",
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: LoginResponse.self, decoder: APIService.jsonDecoder)
        .value()
        .eraseToAnyPublisher()
    }
    
    func logout() -> AnyPublisher<EmptyResponse, AFError> {
        return session.request(
            "\(baseURL)/auth/logout",
            method: .post,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: EmptyResponse.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Trading Endpoints
    func getPositions() -> AnyPublisher<[Position], AFError> {
        return session.request(
            "\(baseURL)/positions",
            method: .get,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: [Position].self)
        .value()
        .eraseToAnyPublisher()
    }
    
    func executeTrade(symbol: String, side: String, quantity: Double) -> AnyPublisher<TradeResponse, AFError> {
        let request = TradeRequest(symbol: symbol, side: side, quantity: quantity)
        
        return session.request(
            "\(baseURL)/trade",
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: TradeResponse.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    
    // MARK: - Market Data Endpoints
    func getCandlestickData(symbol: String, timeframe: String = "5Min", limit: Int = 100) -> AnyPublisher<[CandlestickData], AFError> {
        let parameters: [String: Any] = [
            "timeframe": timeframe,
            "limit": limit
        ]
        
        return session.request(
            "\(baseURL)/candlestick/\(symbol)",
            method: .get,
            parameters: parameters,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: [CandlestickData].self, decoder: APIService.jsonDecoder)
        .value()
        .eraseToAnyPublisher()
    }
    
    func getCandlesticks(symbol: String, timeframe: String, from: Date, to: Date) -> AnyPublisher<[Candle], Error> {
        let fromTimestamp = Int(from.timeIntervalSince1970 * 1000) // Convert to milliseconds
        let toTimestamp = Int(to.timeIntervalSince1970 * 1000)
        
        // Map client timeframe to Polygon API format
        let polygonTimespan: String
        let multiplier: Int
        switch timeframe {
        case "1Min":
            polygonTimespan = "minute"
            multiplier = 1
        case "5Min":
            polygonTimespan = "minute"
            multiplier = 5
        case "15Min":
            polygonTimespan = "minute"
            multiplier = 15
        case "30Min":
            polygonTimespan = "minute"
            multiplier = 30
        case "1Hour":
            polygonTimespan = "hour"
            multiplier = 1
        default:
            polygonTimespan = "minute"
            multiplier = 1
        }
        
        let parameters: [String: Any] = [
            "symbol": symbol,
            "timeframe": polygonTimespan,
            "multiplier": multiplier,
            "from": fromTimestamp,
            "to": toTimestamp
        ]
        
        struct CandlestickAPIResponse: Codable {
            let success: Bool
            let candles: [CandleData]
            let lastCompleteCandle: String?
            let nextCandleStart: String?
            
            struct CandleData: Codable {
                let timestamp: Int
                let open: Double
                let high: Double
                let low: Double
                let close: Double
                let volume: Int
                let vwap: Double?
                let trades: Int?
            }
        }
        
        return session.request(
            "\(baseURL)/market/candlesticks",
            method: .get,
            parameters: parameters,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: CandlestickAPIResponse.self, decoder: APIService.jsonDecoder)
        .tryMap { response in
            guard let value = response.value else {
                throw URLError(.badServerResponse)
            }
            
            return value.candles.map { candleData in
                Candle(
                    timestamp: Date(timeIntervalSince1970: Double(candleData.timestamp) / 1000),
                    open: candleData.open,
                    high: candleData.high,
                    low: candleData.low,
                    close: candleData.close,
                    volume: candleData.volume
                )
            }
        }
        .mapError { $0 as Error }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Alpaca Credentials
    func getAlpacaCredentials() async throws -> AlpacaCredentialsResponse {
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                "\(baseURL)/user/alpaca-credentials",
                method: .get,
                headers: authenticatedHeaders
            )
            .validate()
            .responseDecodable(of: AlpacaCredentialsResponse.self) { response in
                switch response.result {
                case .success(let credentials):
                    continuation.resume(returning: credentials)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateAlpacaCredentials(apiKey: String, secretKey: String, paperTrading: Bool) async throws {
        let parameters = AlpacaCredentialsUpdate(
            api_key: apiKey,
            secret_key: secretKey,
            paper_trading: paperTrading
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                "\(baseURL)/user/alpaca-credentials",
                method: .post,
                parameters: parameters,
                encoder: JSONParameterEncoder.default,
                headers: authenticatedHeaders
            )
            .validate()
            .response { response in
                if let error = response.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func deleteAlpacaCredentials() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                "\(baseURL)/user/alpaca-credentials",
                method: .delete,
                headers: authenticatedHeaders
            )
            .validate()
            .response { response in
                if let error = response.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Health Check
    func healthCheck() async throws -> HealthResponse {
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                "\(baseURL)/health",
                method: .get,
                headers: defaultHeaders
            )
            .validate()
            .responseDecodable(of: HealthResponse.self) { response in
                switch response.result {
                case .success(let health):
                    continuation.resume(returning: health)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func healthCheck() -> AnyPublisher<HealthResponse, AFError> {
        return session.request(
            "\(baseURL)/health",
            method: .get,
            headers: defaultHeaders
        )
        .validate()
        .publishDecodable(type: HealthResponse.self)
        .value()
        .eraseToAnyPublisher()
    }
}

// MARK: - Supporting Types
struct EmptyResponse: Codable {}

struct HealthResponse: Codable {
    let status: String
    let timestamp: String
    let services: ServiceStatus
    
    struct ServiceStatus: Codable {
        let trading: Bool
        let marketData: Bool
        
        enum CodingKeys: String, CodingKey {
            case trading
            case marketData = "market_data"
        }
    }
}

struct AlpacaCredentialsResponse: Codable {
    let hasAPIKey: Bool
    let hasSecretKey: Bool
    let paperTrading: Bool
    
    enum CodingKeys: String, CodingKey {
        case hasAPIKey = "has_api_key"
        case hasSecretKey = "has_secret_key"
        case paperTrading = "paper_trading"
    }
}

struct AlpacaCredentialsUpdate: Codable {
    let api_key: String
    let secret_key: String
    let paper_trading: Bool
}

// MARK: - Error Handling Extension
extension APIService {
    func handleAPIError(_ error: AFError) -> APIError {
        return APIError(
            message: error.localizedDescription,
            code: error.responseCode ?? -1
        )
    }
}

// MARK: - Custom Date Formatter
extension APIService {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()
    
    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }()
    
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(dateFormatter)
        return encoder
    }()
}