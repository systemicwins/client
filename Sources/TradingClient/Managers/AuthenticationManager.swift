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
        checkStoredCredentials()
    }
    
    private func checkStoredCredentials() {
        if let token = keychain["auth_token"] {
            apiService.setAuthToken(token)
            isAuthenticated = true
            // TODO: Validate token with server
        }
    }
    
    func login(email: String, password: String) {
        isLoading = true
        errorMessage = nil
        
        apiService.login(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        print("Login error: \(error)")
                        print("Error description: \(error.localizedDescription)")
                        self?.errorMessage = "Could not connect to server"  // Generic error for UI
                    }
                },
                receiveValue: { [weak self] response in
                    print("Login response received: success=\(response.success), hasToken=\(response.token != nil), hasUser=\(response.user != nil)")
                    if response.success, let token = response.token, let user = response.user {
                        print("Login successful for user: \(user.username)")

                        // Check account type and allow free retail access
                        let isRetailAccount = user.isRetail
                        let isProAccount = user.isPro

                        print("User account type: retail=\(isRetailAccount), pro=\(isProAccount)")

                        // Allow retail users free access
                        if isRetailAccount {
                            print("Retail user logged in - granting free access")
                        } else if isProAccount {
                            print("Pro user logged in - full access granted")
                        } else {
                            print("Unknown account type: \(user.roleName ?? "unknown")")
                        }

                        self?.keychain["auth_token"] = token
                        self?.apiService.setAuthToken(token)
                        self?.currentUser = user
                        self?.isAuthenticated = true
                        self?.errorMessage = nil
                    } else {
                        print("Login failed: \(response.message ?? "Unknown error")")
                        self?.errorMessage = response.message ?? "Login failed"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func logout() {
        isLoading = true
        
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
    
    private func performLogout() {
        keychain["auth_token"] = nil
        apiService.clearAuthToken()
        currentUser = nil
        isAuthenticated = false
        isLoading = false
        errorMessage = nil
    }
}