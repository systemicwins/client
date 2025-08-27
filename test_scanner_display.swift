#!/usr/bin/env swift

import Foundation

// Test the full scanner flow: login -> get gappers -> verify count
print("=== Testing Scanner Display Flow ===\n")

// Step 1: Login
print("1. Logging in...")
let loginURL = URL(string: "https://api.relentless.market/auth/login")!
var loginRequest = URLRequest(url: loginURL)
loginRequest.httpMethod = "POST"
loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
loginRequest.httpBody = try! JSONEncoder().encode(["email": "demo@example.com", "password": "demo"])

let semaphore = DispatchSemaphore(value: 0)
var authToken: String?

URLSession.shared.dataTask(with: loginRequest) { data, response, error in
    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let token = json["token"] as? String {
        authToken = token
        print("   ✅ Login successful")
    } else {
        print("   ❌ Login failed")
    }
    semaphore.signal()
}.resume()

semaphore.wait()

// Step 2: Get gappers (simulating what StockScannerManager does)
print("\n2. Loading gappers from /gappers endpoint...")
let gappersURL = URL(string: "https://api.relentless.market/gappers")!
var gappersRequest = URLRequest(url: gappersURL)
gappersRequest.timeoutInterval = 30

let semaphore2 = DispatchSemaphore(value: 0)

URLSession.shared.dataTask(with: gappersRequest) { data, response, error in
    if let httpResponse = response as? HTTPURLResponse {
        print("   HTTP Status: \(httpResponse.statusCode)")
    }
    
    if let data = data {
        print("   Received \(data.count) bytes")
        
        // Try to parse as GappersResponse format
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let count = json["count"] as? Int {
                print("   ✅ Response has count: \(count)")
            }
            if let gappers = json["gappers"] as? [[String: Any]] {
                print("   ✅ Gappers array has \(gappers.count) items")
                
                // Show first 5 gappers
                print("\n   First 5 gappers:")
                for (index, gapper) in gappers.prefix(5).enumerated() {
                    if let ticker = gapper["ticker"] as? String,
                       let price = gapper["price"] as? Double,
                       let gapPercent = gapper["gap_percent"] as? Double {
                        print("   \(index + 1). \(ticker): $\(String(format: "%.2f", price)) (+\(String(format: "%.1f", gapPercent))%)")
                    }
                }
                
                print("\n   ✅ Gappers are successfully returned by API")
                print("   ⚠️  These should appear in the Swift app's Scanner tab")
            } else {
                print("   ❌ No 'gappers' array in response")
            }
        } else {
            print("   ❌ Failed to parse JSON")
        }
    } else if let error = error {
        print("   ❌ Error: \(error)")
    }
    semaphore2.signal()
}.resume()

semaphore2.wait()

print("\n=== Test Complete ===")
print("\nTo verify in the Swift app:")
print("1. Launch the app: .build/arm64-apple-macosx/debug/TradingPlatform")
print("2. Login with demo@example.com / demo")
print("3. Click on the 'Scanner' tab in the sidebar")
print("4. The gappers should appear automatically")
print("5. If not visible, click 'Refresh' button")