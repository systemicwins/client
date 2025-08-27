#!/usr/bin/env swift

import Foundation

// Test FMP API for OPAD SEC filings
let apiKey = "BiNbCLiPPz7LmMkDuMAfB6Bdj0AJTMxO"
let symbol = "OPAD"
let urlString = "https://financialmodelingprep.com/api/v3/sec_filings/\(symbol)?apikey=\(apiKey)&limit=500"

print("Fetching SEC filings for \(symbol)...")

let url = URL(string: urlString)!
let task = URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print("Error: \(error)")
        exit(1)
    }
    
    guard let data = data else {
        print("No data received")
        exit(1)
    }
    
    do {
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            // Calculate 5 years ago date
            let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date())!
            
            // Filter filings from past 5 years
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            var filingCounts: [String: Int] = [:]
            var totalFilings = 0
            
            for filing in json {
                if let dateString = filing["fillingDate"] as? String,
                   let formType = filing["type"] as? String,
                   let date = dateFormatter.date(from: dateString),
                   date >= fiveYearsAgo {
                    totalFilings += 1
                    filingCounts[formType, default: 0] += 1
                }
            }
            
            print("\n=== SEC FILINGS FOR \(symbol) (Past 5 Years) ===")
            print("Total filings: \(totalFilings)")
            print("\nBreakdown by type:")
            for (type, count) in filingCounts.sorted(by: { $0.value > $1.value }) {
                print("  \(type): \(count)")
            }
            
            // Show most recent filings
            print("\nMost recent 5 filings:")
            for (index, filing) in json.prefix(5).enumerated() {
                if let date = filing["fillingDate"] as? String,
                   let type = filing["type"] as? String,
                   let link = filing["link"] as? String {
                    print("  \(index + 1). \(date) - \(type)")
                    print("     \(link)")
                }
            }
            
        } else {
            print("Failed to parse JSON response")
        }
    } catch {
        print("JSON parsing error: \(error)")
    }
    
    exit(0)
}

task.resume()
RunLoop.main.run()