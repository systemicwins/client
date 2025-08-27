import Foundation
import TradingPlatform

public struct TestLogin {
    public static func test() {
        print("\n=== Testing Login JSON Parsing ===")
        
        let jsonString = """
        {
            "token": "test-token-123",
            "user": {
                "id": 1,
                "email": "demo@example.com",
                "name": "Demo User",
                "created_at": "2024-01-01T00:00:00Z"
            }
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        do {
            let response = try APIService.jsonDecoder.decode(LoginResponse.self, from: jsonData)
            print("✅ Successfully decoded LoginResponse:")
            print("  Token: \(response.token)")
            print("  User ID: \(response.user.id)")
            print("  Email: \(response.user.email)")
            print("  Name: \(response.user.name)")
            if let createdAt = response.user.createdAt {
                print("  Created: \(createdAt)")
            }
            print("\n✅ JSON parsing works correctly!")
        } catch {
            print("❌ Failed to decode: \(error)")
            print("Error details: \(String(describing: error))")
        }
        
        print("\n=== Testing Live Login ===")
        print("Attempting to login with demo@example.com...")
        let authManager = AuthenticationManager.shared
        authManager.login(email: "demo@example.com", password: "demo")
        
        // Give it a moment to complete
        Thread.sleep(forTimeInterval: 2.0)
        
        if authManager.isAuthenticated {
            print("✅ Login successful!")
            if let user = authManager.currentUser {
                print("  Logged in as: \(user.name) (\(user.email))")
            }
        } else {
            print("❌ Login failed")
            if let error = authManager.errorMessage {
                print("  Error: \(error)")
            }
        }
    }
}