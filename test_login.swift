import Foundation
import TradingPlatform

// Test JSON parsing with the correct decoder
let jsonString = """
{
    "token": "test-token",
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
} catch {
    print("❌ Failed to decode: \(error)")
}