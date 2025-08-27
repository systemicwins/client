import Foundation
import Combine
import KeychainAccess

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = APIService.shared
    private let keychain = Keychain(service: "com.tradingplatform.client")
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Check if we're in development mode
        if ProcessInfo.processInfo.environment["TRADER_ENV"] == "development" {
            // Automatically use offline mode in development
            DispatchQueue.main.async { [weak self] in
                self?.loginOffline()
            }
        } else {
            checkStoredCredentials()
        }
    }
    
    // MARK: - Authentication State Management
    private func checkStoredCredentials() {
        // Check if we have a stored token
        if let token = keychain["auth_token"] {
            apiService.setAuthToken(token)
            // Validate token with server
            validateStoredToken()
        }
    }
    
    private func validateStoredToken() {
        // Set a reasonable timeout for the health check
        apiService.healthCheck()
            .timeout(.seconds(5), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .failure(let error):
                        // Token might be invalid or network unavailable, clear it
                        print("Token validation failed: \(error)")
                        self?.clearStoredToken()
                    case .finished:
                        break
                    }
                },
                receiveValue: { [weak self] _ in
                    // Token is valid, user is authenticated
                    self?.isAuthenticated = true
                }
            )
            .store(in: &cancellables)
    }
    
    private func clearStoredToken() {
        // Clear token but don't show as logged out if we never were logged in
        keychain["auth_token"] = nil
        apiService.clearAuthToken()
        isAuthenticated = false
    }
    
    // MARK: - Login
    func login(email: String, password: String) {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        apiService.login(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = self?.apiService.handleAPIError(error).localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.handleSuccessfulLogin(response)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Registration
    func register(email: String, password: String, name: String) {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        apiService.register(email: email, password: password, name: name)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        self?.errorMessage = self?.apiService.handleAPIError(error).localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.handleSuccessfulLogin(response)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Logout
    func logout() {
        isLoading = true
        
        // Call logout endpoint
        apiService.logout()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    self?.performLogout()
                },
                receiveValue: { [weak self] _ in
                    self?.performLogout()
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Helper Methods
    private func handleSuccessfulLogin(_ response: LoginResponse) {
        // Store auth token securely
        keychain["auth_token"] = response.token
        apiService.setAuthToken(response.token)
        
        // Update state
        currentUser = response.user
        isAuthenticated = true
        errorMessage = nil
        
        // Connect to WebSocket for real-time updates (non-blocking)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WebSocketService.shared.connect()
        }
    }
    
    private func performLogout() {
        // Clear stored credentials
        keychain["auth_token"] = nil
        apiService.clearAuthToken()
        
        // Disconnect WebSocket
        WebSocketService.shared.disconnect()
        
        // Update state
        currentUser = nil
        isAuthenticated = false
        isLoading = false
        errorMessage = nil
    }
    
    // MARK: - Validation Helpers
    func validateEmail(_ email: String) -> String? {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        if email.isEmpty {
            return "Email is required"
        } else if !emailPredicate.evaluate(with: email) {
            return "Please enter a valid email address"
        }
        
        return nil
    }
    
    func validatePassword(_ password: String) -> String? {
        if password.isEmpty {
            return "Password is required"
        } else if password.count < 8 {
            return "Password must be at least 8 characters long"
        }
        
        return nil
    }
    
    func validateName(_ name: String) -> String? {
        if name.isEmpty {
            return "Name is required"
        } else if name.count < 2 {
            return "Name must be at least 2 characters long"
        }
        
        return nil
    }
    
    // MARK: - Demo Login
    // MARK: - Offline Mode (for development/testing)
    private func loginOffline() {
        // Simulate successful offline login without network calls
        let demoUser = User(
            id: 999999,
            email: "offline@demo.com",
            name: "Offline User",
            createdAt: Date()
        )
        
        currentUser = demoUser
        isAuthenticated = true
        errorMessage = nil
        isLoading = false
        
        // Don't connect WebSocket in offline mode
        print("Logged in offline mode")
    }
}