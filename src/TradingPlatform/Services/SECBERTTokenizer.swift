import Foundation

class SECBERTTokenizer {
    var vocab: [String: Int] = [:]
    var reverseVocab: [Int: String] = [:]
    var specialTokens: SpecialTokens?
    
    struct SpecialTokens: Codable {
        let padToken: String
        let clsToken: String
        let sepToken: String
        let unkToken: String
        let maskToken: String?
        let padTokenId: Int
        let clsTokenId: Int
        let sepTokenId: Int
        let unkTokenId: Int
        
        // Custom coding keys to handle snake_case JSON
        enum CodingKeys: String, CodingKey {
            case padToken = "pad_token"
            case clsToken = "cls_token"
            case sepToken = "sep_token"
            case unkToken = "unk_token"
            case maskToken = "mask_token"
            case padTokenId = "pad_token_id"
            case clsTokenId = "cls_token_id"
            case sepTokenId = "sep_token_id"
            case unkTokenId = "unk_token_id"
        }
    }
    
    init() {
        // Empty init for manual configuration
    }
    
    init(loadFromBundle: Bool) throws {
        // First, try to find files in the build bundle (where they actually exist)
        var vocabURL: URL? = nil
        
        // Strategy 1: Check build directory bundle
        if let executableURL = Bundle.main.executableURL {
            let buildDir = executableURL.deletingLastPathComponent()
            let buildBundlePath = buildDir.appendingPathComponent("TradingPlatform_TradingPlatform.bundle")
            let buildVocabPath = buildBundlePath.appendingPathComponent("secbert_vocab.json")
            
            if FileManager.default.fileExists(atPath: buildVocabPath.path) {
                vocabURL = buildVocabPath
                print("✅ Found vocab in build bundle: \(buildVocabPath.path)")
            }
        }
        
        // Strategy 2: Try Bundle.main and Bundle.module for Swift Package
        if vocabURL == nil {
            vocabURL = Bundle.main.url(forResource: "secbert_vocab", withExtension: "json")
        }
        if vocabURL == nil {
            vocabURL = Bundle.module.url(forResource: "secbert_vocab", withExtension: "json")
        }
        if vocabURL == nil {
            // Try at bundle root
            let bundleVocab = Bundle.module.bundleURL.appendingPathComponent("secbert_vocab.json")
            if FileManager.default.fileExists(atPath: bundleVocab.path) {
                vocabURL = bundleVocab
            }
        }
        if vocabURL == nil {
            // Try in Resources subdirectory
            vocabURL = Bundle.module.url(forResource: "Resources/secbert_vocab", withExtension: "json")
        }
        if vocabURL == nil {
            // Try as a direct path in Resources
            let resourcesURL = Bundle.module.bundleURL.appendingPathComponent("Resources/secbert_vocab.json")
            if FileManager.default.fileExists(atPath: resourcesURL.path) {
                vocabURL = resourcesURL
            }
        }
        
        guard let finalVocabURL = vocabURL,
              let vocabData = try? Data(contentsOf: finalVocabURL),
              let vocabDict = try? JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
            print("❌ SEC-BERT vocabulary not found")
            print("  Searched in: \(Bundle.main.bundlePath)")
            print("  And: \(Bundle.module.bundlePath)")
            throw TokenizerError.vocabNotFound
        }
        
        self.vocab = vocabDict
        self.reverseVocab = Dictionary(uniqueKeysWithValues: vocabDict.map { ($1, $0) })
        
        // Load special tokens
        var tokensURL: URL? = nil
        
        // Strategy 1: Check build directory bundle
        if let executableURL = Bundle.main.executableURL {
            let buildDir = executableURL.deletingLastPathComponent()
            let buildBundlePath = buildDir.appendingPathComponent("TradingPlatform_TradingPlatform.bundle")
            let buildTokensPath = buildBundlePath.appendingPathComponent("secbert_special_tokens.json")
            
            if FileManager.default.fileExists(atPath: buildTokensPath.path) {
                tokensURL = buildTokensPath
                print("✅ Found special tokens in build bundle: \(buildTokensPath.path)")
            }
        }
        
        // Strategy 2: Try other locations as fallback
        if tokensURL == nil {
            tokensURL = Bundle.main.url(forResource: "secbert_special_tokens", withExtension: "json")
        }
        if tokensURL == nil {
            tokensURL = Bundle.module.url(forResource: "secbert_special_tokens", withExtension: "json")
        }
        if tokensURL == nil {
            // Try at bundle root
            let bundleTokens = Bundle.module.bundleURL.appendingPathComponent("secbert_special_tokens.json")
            if FileManager.default.fileExists(atPath: bundleTokens.path) {
                tokensURL = bundleTokens
            }
        }
        if tokensURL == nil {
            // Try in Resources subdirectory
            tokensURL = Bundle.module.url(forResource: "Resources/secbert_special_tokens", withExtension: "json")
        }
        if tokensURL == nil {
            // Try as a direct path in Resources
            let resourcesURL = Bundle.module.bundleURL.appendingPathComponent("Resources/secbert_special_tokens.json")
            if FileManager.default.fileExists(atPath: resourcesURL.path) {
                tokensURL = resourcesURL
            }
        }
        
        guard let finalTokensURL = tokensURL,
              let tokensData = try? Data(contentsOf: finalTokensURL) else {
            print("❌ SEC-BERT special tokens not found")
            throw TokenizerError.specialTokensNotFound
        }
        
        self.specialTokens = try JSONDecoder().decode(SpecialTokens.self, from: tokensData)
        print("✅ SEC-BERT tokenizer loaded: \(vocab.count) tokens")
    }
    
    func tokenize(_ text: String, maxLength: Int = 512) -> TokenizerOutput {
        guard let specialTokens = specialTokens else {
            // Return empty output if not configured
            return TokenizerOutput(inputIds: [], attentionMask: [])
        }
        
        // Simple word-level tokenization (BERT uses WordPiece in practice)
        let words = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        
        // Convert to token IDs
        var tokenIds: [Int] = [specialTokens.clsTokenId] // Start with [CLS]
        
        for word in words {
            if tokenIds.count >= maxLength - 1 { break } // Leave room for [SEP]
            
            if let tokenId = vocab[word] {
                tokenIds.append(tokenId)
            } else {
                tokenIds.append(specialTokens.unkTokenId)
            }
        }
        
        tokenIds.append(specialTokens.sepTokenId) // End with [SEP]
        
        // Pad or truncate to maxLength
        let paddingLength = maxLength - tokenIds.count
        if paddingLength > 0 {
            tokenIds.append(contentsOf: Array(repeating: specialTokens.padTokenId, count: paddingLength))
        } else if tokenIds.count > maxLength {
            tokenIds = Array(tokenIds.prefix(maxLength))
        }
        
        // Create attention mask (1 for real tokens, 0 for padding)
        let attentionMask = tokenIds.map { $0 != specialTokens.padTokenId ? 1 : 0 }
        
        return TokenizerOutput(inputIds: tokenIds, attentionMask: attentionMask)
    }
    
    struct TokenizerOutput {
        let inputIds: [Int]
        let attentionMask: [Int]
    }
    
    enum TokenizerError: Error {
        case vocabNotFound
        case specialTokensNotFound
    }
}