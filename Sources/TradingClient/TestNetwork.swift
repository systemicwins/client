import Foundation
import Alamofire

public class TestNetwork {
    public static func test() {
        DispatchQueue.global().async {
            print("\n=== Testing Network Connection ===")
            print("Testing API endpoint: https://api.relentless.market/health")
            
            // First test with URLSession
            let url = URL(string: "https://api.relentless.market/health")!
            let semaphore = DispatchSemaphore(value: 0)
            
            print("\n1. Testing with URLSession...")
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("   URLSession Error: \(error)")
                    print("   Error Domain: \((error as NSError).domain)")
                    print("   Error Code: \((error as NSError).code)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("   URLSession Success! Status: \(httpResponse.statusCode)")
                }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
            
            // Then test with Alamofire
            print("\n2. Testing with Alamofire...")
            AF.request("https://api.relentless.market/health")
                .validate()
                .response { response in
                    if let error = response.error {
                        print("   Alamofire Error: \(error)")
                        if let underlyingError = error.underlyingError {
                            print("   Underlying: \(underlyingError)")
                            print("   Underlying Domain: \((underlyingError as NSError).domain)")
                            print("   Underlying Code: \((underlyingError as NSError).code)")
                        }
                    } else {
                        print("   Alamofire Success! Status: \(response.response?.statusCode ?? -1)")
                    }
                    semaphore.signal()
                }
            _ = semaphore.wait(timeout: .now() + 10)
            
            print("\n=== Test Complete ===\n")
        }
    }
}