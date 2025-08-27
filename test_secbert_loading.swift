#!/usr/bin/env swift

import Foundation
import CoreML

// Test if SEC-BERT model loads properly

print("Testing SEC-BERT Model Loading")
print("=" + String(repeating: "=", count: 50))

// Check bundle paths
let mainBundle = Bundle.main
print("\nMain bundle path: \(mainBundle.bundlePath)")

// Look for the module bundle
let moduleBundlePath = mainBundle.bundleURL.appendingPathComponent("TradingPlatform_TradingPlatform.bundle")
print("Module bundle path: \(moduleBundlePath.path)")
print("Module bundle exists: \(FileManager.default.fileExists(atPath: moduleBundlePath.path))")

if let moduleBundle = Bundle(path: moduleBundlePath.path) {
    print("\n✅ Module bundle loaded successfully")
    
    // Check for model
    if let modelURL = moduleBundle.url(forResource: "SECBERT", withExtension: "mlmodel") {
        print("✅ Found SECBERT.mlmodel at: \(modelURL.lastPathComponent)")
        
        // Try to load it
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            print("✅ SEC-BERT model loaded successfully!")
            print("   Model description: \(model.modelDescription)")
        } catch {
            print("❌ Failed to load model: \(error)")
        }
    } else {
        print("❌ SECBERT.mlmodel not found in module bundle")
    }
    
    // Check for vocab files
    if let vocabURL = moduleBundle.url(forResource: "secbert_vocab", withExtension: "json", subdirectory: "Resources") {
        print("✅ Found vocabulary file")
    } else {
        print("❌ Vocabulary file not found")
    }
    
    if let tokensURL = moduleBundle.url(forResource: "secbert_special_tokens", withExtension: "json", subdirectory: "Resources") {
        print("✅ Found special tokens file")
    } else {
        print("❌ Special tokens file not found")
    }
} else {
    print("❌ Could not load module bundle")
}

print("\n" + String(repeating: "=", count: 50))
print("Test complete")