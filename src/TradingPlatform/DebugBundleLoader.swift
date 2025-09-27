import Foundation
import CoreML

/// Debug helper to test bundle and model loading
class DebugBundleLoader {
    static func testModelLoading() {
        print("\n" + String(repeating: "=", count: 60))
        print("🔍 DEBUG: SEC-BERT Model Loading Test")
        print(String(repeating: "=", count: 60))
        
        // Test 1: Check main bundle
        print("\n1️⃣ Main Bundle:")
        print("   Path: \(Bundle.main.bundlePath)")
        print("   Executable: \(Bundle.main.executablePath ?? "none")")
        
        // Test 2: Check for model in main bundle
        print("\n2️⃣ Checking Main Bundle for model:")
        if let url = Bundle.main.url(forResource: "SECBERT", withExtension: "mlmodel") {
            print("   ✅ Found SECBERT.mlmodel: \(url.path)")
        } else if let url = Bundle.main.url(forResource: "SECBERT", withExtension: "mlmodelc") {
            print("   ✅ Found SECBERT.mlmodelc: \(url.path)")
        } else {
            print("   ❌ Model not found in main bundle")
        }
        
        // Test 3: Check Bundle.module
        print("\n3️⃣ Checking Bundle.module:")
        print("   Path: \(Bundle.module.bundlePath)")
        
        // Test 4: List Bundle.module contents
        print("\n4️⃣ Bundle.module contents:")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: Bundle.module.bundlePath) {
            for item in contents.prefix(10) {
                print("   - \(item)")
            }
        }
        
        // Test 5: Check for model in Bundle.module
        print("\n5️⃣ Checking Bundle.module for model:")
        if let url = Bundle.module.url(forResource: "SECBERT", withExtension: "mlmodel") {
            print("   ✅ Found SECBERT.mlmodel: \(url.lastPathComponent)")
            
            // Try to compile and load it
            do {
                print("   📦 Compiling model...")
                let compiledURL = try MLModel.compileModel(at: url)
                print("   ✅ Model compiled to: \(compiledURL.lastPathComponent)")
                
                let config = MLModelConfiguration()
                let model = try MLModel(contentsOf: compiledURL, configuration: config)
                print("   ✅ Model loads successfully!")
            } catch {
                print("   ❌ Model loading error: \(error)")
            }
        } else {
            print("   ❌ Model not found in Bundle.module")
        }
        
        // Test 6: Check for vocab files in Resources subdirectory
        print("\n6️⃣ Checking for vocabulary files:")
        if let vocabURL = Bundle.module.url(forResource: "Resources/secbert_vocab", withExtension: "json") {
            print("   ✅ Found vocab (with Resources/): \(vocabURL.lastPathComponent)")
        } else if let vocabURL = Bundle.module.url(forResource: "secbert_vocab", withExtension: "json") {
            print("   ✅ Found vocab (direct): \(vocabURL.lastPathComponent)")
        } else {
            print("   ❌ Vocabulary not found")
            
            // Try to find it in Resources subdirectory
            let resourcesPath = Bundle.module.bundleURL.appendingPathComponent("Resources")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcesPath.path) {
                print("   Resources/ contents:")
                for item in contents.prefix(5) {
                    print("     - \(item)")
                }
            }
        }
        
        print("\n" + String(repeating: "=", count: 60))
        print("\n")
    }
}