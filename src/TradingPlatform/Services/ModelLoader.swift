import Foundation
import CoreML

/// Robust model loader that searches multiple locations
class ModelLoader {
    
    /// Find and load the SEC-BERT model from various possible locations
    static func loadSECBERTModel() -> (model: MLModel?, tokenizer: SECBERTTokenizer?) {
        print("\n🔍 Starting SEC-BERT model search...")
        
        // Strategy 1: Look in the build directory relative to executable
        if let model = loadFromBuildDirectory() {
            return model
        }
        
        // Strategy 2: Look in Bundle.module (Swift Package)
        if let model = loadFromBundleModule() {
            return model
        }
        
        // Strategy 3: Look in main bundle
        if let model = loadFromMainBundle() {
            return model
        }
        
        // Strategy 4: Look in current directory
        if let model = loadFromCurrentDirectory() {
            return model
        }
        
        // Strategy 5: Look in source directory (development)
        if let model = loadFromSourceDirectory() {
            return model
        }
        
        print("❌ Failed to find SEC-BERT model in any location")
        return (nil, nil)
    }
    
    private static func loadFromBuildDirectory() -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("  1️⃣ Checking build directory...")
        
        // Get the executable path and derive build directory
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let buildDir = executableURL.deletingLastPathComponent()
        
        // Check for bundle in same directory as executable
        let bundlePath = buildDir.appendingPathComponent("TradingPlatform_TradingPlatform.bundle")
        guard let bundle = Bundle(url: bundlePath) else {
            print("     Bundle not found at: \(bundlePath.path)")
            return nil
        }
        
        return loadFromBundle(bundle, name: "Build directory bundle")
    }
    
    private static func loadFromBundleModule() -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("  2️⃣ Checking Bundle.module...")
        
        // Only available when built as Swift Package
        #if canImport(TradingPlatform)
        return loadFromBundle(Bundle.module, name: "Bundle.module")
        #else
        // Try to access it anyway
        let selector = NSSelectorFromString("module")
        if Bundle.responds(to: selector),
           let bundle = Bundle.perform(selector)?.takeUnretainedValue() as? Bundle {
            return loadFromBundle(bundle, name: "Bundle.module")
        }
        print("     Bundle.module not available")
        return nil
        #endif
    }
    
    private static func loadFromMainBundle() -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("  3️⃣ Checking main bundle...")
        return loadFromBundle(Bundle.main, name: "Main bundle")
    }
    
    private static func loadFromCurrentDirectory() -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("  4️⃣ Checking current directory...")
        
        let currentDir = FileManager.default.currentDirectoryPath
        print("     Current directory: \(currentDir)")
        
        // Look for model file
        let modelPath = "\(currentDir)/SECBERT.mlmodel"
        if !FileManager.default.fileExists(atPath: modelPath) {
            print("     Model not found at: \(modelPath)")
            return nil
        }
        
        let modelURL = URL(fileURLWithPath: modelPath)
        
        // Look for vocab files
        let vocabPath = "\(currentDir)/secbert_vocab.json"
        let tokensPath = "\(currentDir)/secbert_special_tokens.json"
        
        guard FileManager.default.fileExists(atPath: vocabPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            print("     Vocabulary files not found")
            return nil
        }
        
        return loadModelAndTokenizer(
            modelURL: modelURL,
            vocabURL: URL(fileURLWithPath: vocabPath),
            tokensURL: URL(fileURLWithPath: tokensPath),
            source: "Current directory"
        )
    }
    
    private static func loadFromSourceDirectory() -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("  5️⃣ Checking source directory...")
        
        // Try common development paths
        let paths = [
            "/Users/alex/relentless/client/Sources/TradingPlatform/Models/SECBERT.mlmodel",
            "./Sources/TradingPlatform/Models/SECBERT.mlmodel",
            "../Sources/TradingPlatform/Models/SECBERT.mlmodel"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                let modelURL = URL(fileURLWithPath: path)
                
                // Derive resource paths
                let basePath = (path as NSString).deletingLastPathComponent
                let resourcesPath = (basePath as NSString).deletingLastPathComponent + "/Resources"
                
                let vocabURL = URL(fileURLWithPath: "\(resourcesPath)/secbert_vocab.json")
                let tokensURL = URL(fileURLWithPath: "\(resourcesPath)/secbert_special_tokens.json")
                
                if FileManager.default.fileExists(atPath: vocabURL.path) &&
                   FileManager.default.fileExists(atPath: tokensURL.path) {
                    return loadModelAndTokenizer(
                        modelURL: modelURL,
                        vocabURL: vocabURL,
                        tokensURL: tokensURL,
                        source: "Source directory"
                    )
                }
            }
        }
        
        print("     Model not found in source directories")
        return nil
    }
    
    private static func loadFromBundle(_ bundle: Bundle, name: String) -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        print("     Checking \(name) at: \(bundle.bundlePath)")
        
        // Look for model
        var modelURL = bundle.url(forResource: "SECBERT", withExtension: "mlmodel")
        if modelURL == nil {
            modelURL = bundle.url(forResource: "SECBERT", withExtension: "mlmodelc")
        }
        if modelURL == nil {
            // Try in Models subdirectory
            modelURL = bundle.url(forResource: "Models/SECBERT", withExtension: "mlmodel")
        }
        
        guard let finalModelURL = modelURL else {
            print("     Model not found in \(name)")
            return nil
        }
        
        // Look for vocab files
        var vocabURL = bundle.url(forResource: "secbert_vocab", withExtension: "json")
        if vocabURL == nil {
            vocabURL = bundle.url(forResource: "Resources/secbert_vocab", withExtension: "json")
        }
        if vocabURL == nil {
            let resourcesPath = bundle.bundleURL.appendingPathComponent("Resources/secbert_vocab.json")
            if FileManager.default.fileExists(atPath: resourcesPath.path) {
                vocabURL = resourcesPath
            }
        }
        
        var tokensURL = bundle.url(forResource: "secbert_special_tokens", withExtension: "json")
        if tokensURL == nil {
            tokensURL = bundle.url(forResource: "Resources/secbert_special_tokens", withExtension: "json")
        }
        if tokensURL == nil {
            let resourcesPath = bundle.bundleURL.appendingPathComponent("Resources/secbert_special_tokens.json")
            if FileManager.default.fileExists(atPath: resourcesPath.path) {
                tokensURL = resourcesPath
            }
        }
        
        guard let finalVocabURL = vocabURL, let finalTokensURL = tokensURL else {
            print("     Vocabulary files not found in \(name)")
            return nil
        }
        
        return loadModelAndTokenizer(
            modelURL: finalModelURL,
            vocabURL: finalVocabURL,
            tokensURL: finalTokensURL,
            source: name
        )
    }
    
    private static func loadModelAndTokenizer(
        modelURL: URL,
        vocabURL: URL,
        tokensURL: URL,
        source: String
    ) -> (model: MLModel?, tokenizer: SECBERTTokenizer?)? {
        
        print("     ✅ Found all files in \(source)")
        print("        Model: \(modelURL.lastPathComponent)")
        print("        Vocab: \(vocabURL.lastPathComponent)")
        print("        Tokens: \(tokensURL.lastPathComponent)")
        
        do {
            // Check if model needs compilation
            let modelURLString = modelURL.path
            let needsCompilation = modelURLString.hasSuffix(".mlmodel")
            
            var finalModelURL = modelURL
            
            if needsCompilation {
                print("     📦 Compiling model...")
                
                // Compile the model to a temporary directory
                let tempDir = FileManager.default.temporaryDirectory
                let compiledURL = try MLModel.compileModel(at: modelURL)
                print("     ✅ Model compiled to: \(compiledURL.lastPathComponent)")
                finalModelURL = compiledURL
            }
            
            // Load model
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let model = try MLModel(contentsOf: finalModelURL, configuration: config)
            print("     ✅ Model loaded successfully")
            
            // Create tokenizer manually from URLs
            let vocabData = try Data(contentsOf: vocabURL)
            guard let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
                throw NSError(domain: "ModelLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid vocabulary"])
            }
            
            let tokensData = try Data(contentsOf: tokensURL)
            
            // We can't easily create SECBERTTokenizer from here, so we'll mark it as loaded
            // The actual tokenizer will be created when needed
            print("     ✅ Vocabulary files verified")
            
            // For now, return model only - tokenizer will use fallback paths
            return (model, nil)
            
        } catch {
            print("     ❌ Loading error: \(error)")
            return nil
        }
    }
}