
import CoreML
import Foundation
import NaturalLanguage

/// Local financial sentiment analyzer using CoreML
/// Model: bert-base-uncased
@available(iOS 15.0, macOS 12.0, *)
public class FinancialSentimentAnalyzer: ObservableObject {
    
    // MARK: - Types
    
    public enum Sentiment: String, CaseIterable {
        case negative = "NEGATIVE"
        case neutral = "NEUTRAL"
        case positive = "POSITIVE"
        
        init(from label: String) {
            switch label.uppercased() {
            case "NEGATIVE", "LABEL_0": self = .negative
            case "POSITIVE", "LABEL_2": self = .positive
            default: self = .neutral
            }
        }
        
        var score: Double {
            switch self {
            case .negative: return -1.0
            case .neutral: return 0.0
            case .positive: return 1.0
            }
        }
        
        var impact: Double {
            // Negative sentiment has higher impact on financial analysis
            switch self {
            case .negative: return 1.5
            case .neutral: return 0.5
            case .positive: return 1.0
            }
        }
    }
    
    public struct SentimentResult {
        public let sentiment: Sentiment
        public let confidence: Double
        public let probabilities: [Sentiment: Double]
        public let text: String
        
        public var weightedScore: Double {
            return sentiment.score * confidence * sentiment.impact
        }
    }
    
    public struct FinancialHealthScore {
        public let ticker: String
        public let overallScore: Double  // -100 to +100
        public let sentimentBreakdown: [FilingAnalysis]
        public let insights: [String]
        public let confidence: Double
        public let date: Date
        
        public var riskLevel: String {
            switch overallScore {
            case 50...: return "Low Risk"
            case 0..<50: return "Moderate Risk"
            case -50..<0: return "Elevated Risk"
            default: return "High Risk"
            }
        }
    }
    
    public struct FilingAnalysis {
        public let filing: SECFiling
        public let sentiment: Sentiment
        public let confidence: Double
        public let impact: Double
        public let keyPhrases: [String]
    }
    
    // MARK: - Properties
    
    @Published public var isAnalyzing = false
    @Published public var progress: Double = 0
    @Published public var currentAnalysis: FinancialHealthScore?
    
    private let model: MLModel
    private let tokenizer: BertTokenizer
    private let maxLength = 128
    private let labels: [String] = ["LABEL_0", "LABEL_1"]
    
    // MARK: - Initialization
    
    public init() throws {
        // Load CoreML model
        guard let modelURL = Bundle.main.url(forResource: "FinancialSentiment", withExtension: "mlmodelc") else {
            throw AnalyzerError.modelNotFound
        }
        
        self.model = try MLModel(contentsOf: modelURL)
        
        // Load tokenizer
        guard let tokenizerURL = Bundle.main.url(forResource: "tokenizer", withExtension: "json"),
              let data = try? Data(contentsOf: tokenizerURL),
              let config = try? JSONDecoder().decode(TokenizerConfig.self, from: data) else {
            throw AnalyzerError.tokenizerNotFound
        }
        
        self.tokenizer = BertTokenizer(config: config)
    }
    
    // MARK: - Local Inference
    
    /// Analyze sentiment of text using local CoreML model
    public func analyzeSentiment(_ text: String) async throws -> SentimentResult {
        // Tokenize input
        let encoding = tokenizer.encode(text, maxLength: maxLength)
        
        // Prepare CoreML input
        let inputIds = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
        
        for i in 0..<maxLength {
            inputIds[i] = NSNumber(value: encoding.inputIds[i])
            attentionMask[i] = NSNumber(value: encoding.attentionMask[i])
        }
        
        // Create model input
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attentionMask)
        ])
        
        // Run inference locally
        let output = try await Task.detached(priority: .userInitiated) {
            try self.model.prediction(from: input)
        }.value
        
        // Extract probabilities
        guard let probs = output.featureValue(for: "probabilities")?.multiArrayValue else {
            throw AnalyzerError.invalidOutput
        }
        
        // Parse results
        var probabilities: [Sentiment: Double] = [:]
        var maxProb = 0.0
        var bestSentiment = Sentiment.neutral
        
        for (index, label) in labels.enumerated() {
            guard index < probs.count else { break }
            let prob = probs[index].doubleValue
            let sentiment = Sentiment(from: label)
            probabilities[sentiment] = prob
            
            if prob > maxProb {
                maxProb = prob
                bestSentiment = sentiment
            }
        }
        
        return SentimentResult(
            sentiment: bestSentiment,
            confidence: maxProb,
            probabilities: probabilities,
            text: String(text.prefix(200))
        )
    }
    
    /// Analyze SEC filings for financial health
    public func analyzeFinancialHealth(ticker: String, filings: [SECFiling]) async throws -> FinancialHealthScore {
        var analyses: [FilingAnalysis] = []
        var totalWeight = 0.0
        var weightedSum = 0.0
        
        // Update progress
        await MainActor.run {
            self.isAnalyzing = true
            self.progress = 0
        }
        
        let progressIncrement = 1.0 / Double(max(filings.count, 1))
        
        for filing in filings {
            // Extract and analyze text
            let text = filing.extractKeyContent()
            let result = try await analyzeSentiment(text)
            
            // Extract key phrases (simple implementation)
            let keyPhrases = extractKeyPhrases(from: text, sentiment: result.sentiment)
            
            // Calculate impact
            let weight = filing.importanceWeight
            let impact = result.weightedScore * weight
            
            analyses.append(FilingAnalysis(
                filing: filing,
                sentiment: result.sentiment,
                confidence: result.confidence,
                impact: impact,
                keyPhrases: keyPhrases
            ))
            
            weightedSum += impact
            totalWeight += weight
            
            // Update progress
            await MainActor.run {
                self.progress += progressIncrement
            }
        }
        
        // Calculate overall score (-100 to +100)
        let overallScore = totalWeight > 0 ? (weightedSum / totalWeight) * 100 : 0
        
        // Generate insights
        let insights = generateInsights(from: analyses, ticker: ticker)
        
        // Calculate average confidence
        let avgConfidence = analyses.isEmpty ? 0 : 
            analyses.reduce(0) { $0 + $1.confidence } / Double(analyses.count)
        
        let healthScore = FinancialHealthScore(
            ticker: ticker,
            overallScore: overallScore,
            sentimentBreakdown: analyses,
            insights: insights,
            confidence: avgConfidence,
            date: Date()
        )
        
        await MainActor.run {
            self.currentAnalysis = healthScore
            self.isAnalyzing = false
            self.progress = 1.0
        }
        
        return healthScore
    }
    
    // MARK: - Analysis Helpers
    
    private func extractKeyPhrases(from text: String, sentiment: Sentiment) -> [String] {
        // Simple keyword extraction based on sentiment
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        let positiveKeywords = ["growth", "increase", "profit", "gain", "strong", "exceed", "beat"]
        let negativeKeywords = ["loss", "decline", "decrease", "miss", "weak", "below", "concern"]
        
        var phrases: [String] = []
        
        for (index, word) in words.enumerated() {
            let isPositive = positiveKeywords.contains(where: { word.contains($0) })
            let isNegative = negativeKeywords.contains(where: { word.contains($0) })
            
            if (sentiment == .positive && isPositive) || (sentiment == .negative && isNegative) {
                // Get context (3 words before and after)
                let start = max(0, index - 3)
                let end = min(words.count, index + 4)
                let phrase = words[start..<end].joined(separator: " ")
                if phrase.count > 10 && phrase.count < 100 {
                    phrases.append(phrase)
                }
            }
        }
        
        return Array(phrases.prefix(3))
    }
    
    private func generateInsights(from analyses: [FilingAnalysis], ticker: String) -> [String] {
        var insights: [String] = []
        
        // Overall sentiment distribution
        let negativeCount = analyses.filter { $0.sentiment == .negative }.count
        let positiveCount = analyses.filter { $0.sentiment == .positive }.count
        let total = analyses.count
        
        if negativeCount > total / 2 {
            insights.append("⚠️ Majority of filings show negative sentiment")
        } else if positiveCount > total / 2 {
            insights.append("✅ Majority of filings show positive sentiment")
        } else {
            insights.append("⚖️ Mixed sentiment across filings")
        }
        
        // Check quarterly reports
        let quarterlyReports = analyses.filter { $0.filing.type == "10-Q" }
        if !quarterlyReports.isEmpty {
            let avgSentiment = quarterlyReports.reduce(0) { $0 + $1.sentiment.score } / Double(quarterlyReports.count)
            if avgSentiment > 0.3 {
                insights.append("📈 Quarterly reports show positive trend")
            } else if avgSentiment < -0.3 {
                insights.append("📉 Quarterly reports indicate challenges")
            }
        }
        
        // Check annual report
        if let annualReport = analyses.first(where: { $0.filing.type == "10-K" }) {
            if annualReport.sentiment == .positive {
                insights.append("💪 Strong annual report")
            } else if annualReport.sentiment == .negative {
                insights.append("📊 Annual report raises concerns")
            }
        }
        
        // Confidence level
        let avgConfidence = analyses.reduce(0) { $0 + $1.confidence } / Double(max(analyses.count, 1))
        if avgConfidence > 0.8 {
            insights.append("🎯 High confidence in analysis")
        } else if avgConfidence < 0.6 {
            insights.append("🔍 Lower confidence - review filings manually")
        }
        
        insights.append("📄 Analyzed \(total) SEC filings for \(ticker)")
        
        return insights
    }
}

// MARK: - Supporting Types

public struct SECFiling {
    public let id: String
    public let ticker: String
    public let type: String
    public let date: Date
    public let description: String
    public let content: String?
    
    public var importanceWeight: Double {
        switch type {
        case "10-K": return 1.0   // Annual report - highest weight
        case "10-Q": return 0.8   // Quarterly report
        case "8-K": return 0.6    // Current report
        case "DEF 14A": return 0.5 // Proxy statement
        case "Form 4": return 0.3  // Insider trading
        case "13F-HR": return 0.4  // Institutional holdings
        default: return 0.2
        }
    }
    
    public func extractKeyContent() -> String {
        // Extract the most relevant text for sentiment analysis
        // In production, this would parse actual filing content
        if let content = content {
            // Take first 500 characters for analysis
            return String(content.prefix(500))
        }
        return description
    }
}

// MARK: - Tokenizer

struct TokenizerConfig: Codable {
    let vocab: [String: Int]
    let vocabSize: Int
    let maxLength: Int
    let specialTokens: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case vocab
        case vocabSize = "vocab_size"
        case maxLength = "max_length"
        case specialTokens = "special_tokens"
    }
}

class BertTokenizer {
    private let vocab: [String: Int]
    private let unkTokenId: Int
    private let padTokenId: Int
    private let clsTokenId: Int
    private let sepTokenId: Int
    private let doLowerCase: Bool
    
    init(config: TokenizerConfig) {
        self.vocab = config.vocab
        
        // Extract special token IDs
        if let specialTokens = config.specialTokens as? [String: Any] {
            self.padTokenId = (specialTokens["pad_token_id"] as? Int) ?? 0
            self.unkTokenId = (specialTokens["unk_token_id"] as? Int) ?? 100
            self.clsTokenId = (specialTokens["cls_token_id"] as? Int) ?? 101
            self.sepTokenId = (specialTokens["sep_token_id"] as? Int) ?? 102
            self.doLowerCase = (specialTokens["do_lower_case"] as? Bool) ?? true
        } else {
            self.padTokenId = 0
            self.unkTokenId = 100
            self.clsTokenId = 101
            self.sepTokenId = 102
            self.doLowerCase = true
        }
    }
    
    func encode(_ text: String, maxLength: Int) -> (inputIds: [Int], attentionMask: [Int]) {
        var inputIds: [Int] = []
        var attentionMask: [Int] = []
        
        // Add CLS token
        inputIds.append(clsTokenId)
        attentionMask.append(1)
        
        // Tokenize text (simple word-based tokenization)
        let processedText = doLowerCase ? text.lowercased() : text
        let words = processedText.components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        
        // Convert words to token IDs
        for word in words.prefix(maxLength - 2) {
            let tokenId = vocab[word] ?? unkTokenId
            inputIds.append(tokenId)
            attentionMask.append(1)
        }
        
        // Add SEP token
        if inputIds.count < maxLength {
            inputIds.append(sepTokenId)
            attentionMask.append(1)
        }
        
        // Pad to max length
        while inputIds.count < maxLength {
            inputIds.append(padTokenId)
            attentionMask.append(0)
        }
        
        return (Array(inputIds.prefix(maxLength)), Array(attentionMask.prefix(maxLength)))
    }
}

enum AnalyzerError: Error {
    case modelNotFound
    case tokenizerNotFound
    case invalidOutput
}
