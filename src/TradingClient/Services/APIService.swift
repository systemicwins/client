import Foundation
import Alamofire
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    
    private let baseURL: String
    private var authToken: String?
    
    private init() {
        // Load base URL from environment or use default
        let rawURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "api.relentless.market"
        self.baseURL = Self.ensureHTTPS(rawURL)
        print("APIService initialized with baseURL: \(self.baseURL)")
    }
    
    // MARK: - URL Security
    private static func ensureHTTPS(_ url: String) -> String {
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
    
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    func clearAuthToken() {
        self.authToken = nil
    }
    
    private var headers: HTTPHeaders {
        var headers: HTTPHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        
        return headers
    }
    
    // MARK: - Authentication
    func login(email: String, password: String) -> AnyPublisher<LoginResponse, AFError> {
        let request = LoginRequest(email: email, password: password)
        let loginURL = "\(baseURL)/auth/login"
        
        print("Attempting login to: \(loginURL)")
        print("Login request: email=\(email)")
        
        return AF.request(
            loginURL,
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )
        .responseData { response in
            print("Response status code: \(response.response?.statusCode ?? -1)")
            if let data = response.data {
                let str = String(data: data, encoding: .utf8) ?? "no data"
                print("Response data: \(str)")
            }
            if let error = response.error {
                print("Response error: \(error)")
            }
        }
        .publishDecodable(type: LoginResponse.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    func logout() -> AnyPublisher<APIResponse<String>, AFError> {
        return AF.request(
            "\(baseURL)/auth/logout",
            method: .post,
            headers: headers
        )
        .publishDecodable(type: APIResponse<String>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Account Info
    func getAccountInfo() -> AnyPublisher<APIResponse<AccountInfo>, AFError> {
        return AF.request(
            "\(baseURL)/account",
            method: .get,
            headers: headers
        )
        .publishDecodable(type: APIResponse<AccountInfo>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Positions
    func getPositions() -> AnyPublisher<APIResponse<[Position]>, AFError> {
        return AF.request(
            "\(baseURL)/positions",
            method: .get,
            headers: headers
        )
        .publishDecodable(type: APIResponse<[Position]>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Orders
    func getOrders() -> AnyPublisher<APIResponse<[Order]>, AFError> {
        return AF.request(
            "\(baseURL)/orders",
            method: .get,
            headers: headers
        )
        .publishDecodable(type: APIResponse<[Order]>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    func placeOrder(symbol: String, quantity: Double, side: String, orderType: String, limitPrice: Double? = nil) -> AnyPublisher<APIResponse<Order>, AFError> {
        var parameters: [String: Any] = [
            "symbol": symbol,
            "qty": quantity,
            "side": side,
            "type": orderType,
            "time_in_force": "day"
        ]
        
        if let limitPrice = limitPrice {
            parameters["limit_price"] = limitPrice
        }
        
        return AF.request(
            "\(baseURL)/orders",
            method: .post,
            parameters: parameters,
            encoding: JSONEncoding.default,
            headers: headers
        )
        .publishDecodable(type: APIResponse<Order>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Gap Scanner
    func getGapOpportunities() -> AnyPublisher<APIResponse<[GapOpportunity]>, AFError> {
        return AF.request(
            "\(baseURL)/gaps",
            method: .get,
            headers: headers
        )
        .publishDecodable(type: APIResponse<[GapOpportunity]>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Performance Data
    func getPerformanceData(period: String = "1M") -> AnyPublisher<APIResponse<[Trade]>, AFError> {
        return AF.request(
            "\(baseURL)/performance",
            method: .get,
            parameters: ["period": period],
            headers: headers
        )
        .publishDecodable(type: APIResponse<[Trade]>.self)
        .value()
        .eraseToAnyPublisher()
    }
    
    // MARK: - Market Data
    func getQuote(symbol: String) -> AnyPublisher<String, AFError> {
        return AF.request(
            "\(baseURL)/quote/\(symbol)",
            method: .get,
            headers: headers
        )
        .publishString()
        .value()
        .eraseToAnyPublisher()
    }
}