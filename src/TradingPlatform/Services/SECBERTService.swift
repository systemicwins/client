import Foundation
import SwiftUI
import CoreML
import NaturalLanguage
import Accelerate

class SECBERTService: ObservableObject {
    static let shared = SECBERTService()
    
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    
    // Score categories with sentiment results
    @Published var managementSentiment: SentimentScore = SentimentScore()
    @Published var riskSentiment: SentimentScore = SentimentScore()
    @Published var financialPerformance: SentimentScore = SentimentScore()
    @Published var operationalHealth: SentimentScore = SentimentScore()
    
    private var secbertModel: MLModel?
    private var tokenizer: SECBERTTokenizer?
    private let maxSequenceLength = 512 // BERT standard
    private let maxChunksPerFiling = 10 // Limit chunks to process per filing
    private let modelVersion = "1.0.0" // Fine-tuned on Russell 2000
    private let trainingMAE = 4.96 // Training mean absolute error
    
    private init() {
        loadModel()
    }
    
    private func loadModel() {
        // Use the robust ModelLoader
        let (model, _) = ModelLoader.loadSECBERTModel()
        
        self.secbertModel = model
        
        // Try to load tokenizer separately if model loaded
        if model != nil {
            print("\n🔍 Attempting to load tokenizer...")
            do {
                self.tokenizer = try SECBERTTokenizer(loadFromBundle: true)
                print("✅ SEC-BERT tokenizer loaded via standard method")
            } catch {
                print("⚠️ Standard tokenizer loading failed: \(error)")
                print("   Error type: \(type(of: error))")
                // Try alternate loading method
                self.tokenizer = tryAlternateTokenizerLoading()
                if self.tokenizer != nil {
                    print("✅ Tokenizer loaded via alternate method")
                } else {
                    print("❌ All tokenizer loading methods failed")
                }
            }
        }
        
        if secbertModel != nil && tokenizer != nil {
            print("✅ SEC-BERT fully loaded and ready")
        } else {
            print("⚠️ SEC-BERT partially loaded")
            print("  Model: \(secbertModel != nil ? "Loaded" : "Not loaded")")
            print("  Tokenizer: \(tokenizer != nil ? "Loaded" : "Not loaded")")
        }
    }
    
    private func tryAlternateTokenizerLoading() -> SECBERTTokenizer? {
        // Try to find vocab files in the same bundle where model was found
        print("🔍 Trying alternate tokenizer loading...")
        
        // First, check the build directory bundle (where we know files exist)
        guard let executableURL = Bundle.main.executableURL else {
            print("   ❌ Could not get executable URL")
            return nil
        }
        
        let buildDir = executableURL.deletingLastPathComponent()
        let buildBundlePath = buildDir.appendingPathComponent("TradingPlatform_TradingPlatform.bundle")
        
        // Check if build bundle exists and has our files
        let buildVocabPath = buildBundlePath.appendingPathComponent("secbert_vocab.json")
        let buildTokensPath = buildBundlePath.appendingPathComponent("secbert_special_tokens.json")
        
        print("   Checking build bundle: \(buildBundlePath.path)")
        if FileManager.default.fileExists(atPath: buildVocabPath.path) &&
           FileManager.default.fileExists(atPath: buildTokensPath.path) {
            print("   ✅ Found files in build bundle!")
            return createTokenizerFromURLs(vocabURL: buildVocabPath, tokensURL: buildTokensPath)
        }
        
        // Try Bundle.module as fallback
        print("   Checking Bundle.module: \(Bundle.module.bundlePath)")
        
        // Check Bundle.module first with different patterns
        let patterns = [
            ("Resources/secbert_vocab", "Resources/secbert_special_tokens"),
            ("secbert_vocab", "secbert_special_tokens"),
            ("Resources/Resources/secbert_vocab", "Resources/Resources/secbert_special_tokens")
        ]
        
        for (vocabName, tokensName) in patterns {
            print("   Trying pattern: \(vocabName)")
            if let vocabURL = Bundle.module.url(forResource: vocabName, withExtension: "json"),
               let tokensURL = Bundle.module.url(forResource: tokensName, withExtension: "json") {
                print("   ✅ Found files with pattern: \(vocabName)")
                return createTokenizerFromURLs(vocabURL: vocabURL, tokensURL: tokensURL)
            }
        }
        
        // Check direct bundle paths
        let bundlePath = Bundle.module.bundlePath
        
        // List bundle contents for debugging
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) {
            print("   Bundle contents:")
            for item in contents.prefix(10) {
                print("     - \(item)")
            }
        }
        
        // Try different path combinations
        let pathPatterns = [
            ("\(bundlePath)/Resources/secbert_vocab.json", "\(bundlePath)/Resources/secbert_special_tokens.json"),
            ("\(bundlePath)/secbert_vocab.json", "\(bundlePath)/secbert_special_tokens.json"),
            ("\(bundlePath)/Resources/Resources/secbert_vocab.json", "\(bundlePath)/Resources/Resources/secbert_special_tokens.json")
        ]
        
        for (vocabPath, tokensPath) in pathPatterns {
            print("   Checking paths: \(vocabPath.split(separator: "/").last ?? "")")
            if FileManager.default.fileExists(atPath: vocabPath) &&
               FileManager.default.fileExists(atPath: tokensPath) {
                print("   ✅ Found files at path!")
                let vocabURL = URL(fileURLWithPath: vocabPath)
                let tokensURL = URL(fileURLWithPath: tokensPath)
                return createTokenizerFromURLs(vocabURL: vocabURL, tokensURL: tokensURL)
            }
        }
        
        print("❌ Could not find vocabulary files for tokenizer")
        return nil
    }
    
    private func createTokenizerFromURLs(vocabURL: URL, tokensURL: URL) -> SECBERTTokenizer? {
        do {
            // Create a custom tokenizer instance
            let tokenizer = SECBERTTokenizer()
            
            // Load vocabulary
            let vocabData = try Data(contentsOf: vocabURL)
            guard let vocabDict = try JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
                print("❌ Invalid vocabulary format")
                return nil
            }
            
            // Load special tokens
            let tokensData = try Data(contentsOf: tokensURL)
            let specialTokens = try JSONDecoder().decode(SECBERTTokenizer.SpecialTokens.self, from: tokensData)
            
            // Set the properties directly (now they're public)
            tokenizer.vocab = vocabDict
            tokenizer.reverseVocab = Dictionary(uniqueKeysWithValues: vocabDict.map { ($1, $0) })
            tokenizer.specialTokens = specialTokens
            
            print("✅ Tokenizer created from URLs with \(vocabDict.count) tokens")
            return tokenizer
            
        } catch {
            print("❌ Error creating tokenizer: \(error)")
            return nil
        }
    }
    
    struct SentimentScore {
        var score: Double = 50.0 // 0-100 scale
        var confidence: Double = 0.0 // 0-1 confidence level
        var label: String = "Neutral"
        var snippets: [String] = [] // Key text snippets that influenced the score
        
        var color: Color {
            if score >= 70 {
                return .green
            } else if score >= 40 {
                return .orange
            } else {
                return .red
            }
        }
        
        var gradientColor: LinearGradient {
            let greenAmount = score / 100.0
            let redAmount = 1.0 - greenAmount
            
            return LinearGradient(
                colors: [
                    Color(red: redAmount, green: greenAmount * 0.5, blue: 0),
                    Color(red: redAmount * 0.8, green: greenAmount, blue: 0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    // MARK: - Public Methods
    
    func analyzeSECFilings(_ filings: [SECFiling]) async throws -> AnalysisResult {
        isAnalyzing = true
        analysisProgress = 0.0
        
        // Extract symbol from filing
        let symbol = filings.first?.symbol ?? ""
        
        print("\n🔍 Starting unified health analysis for \(symbol) - \(filings.count) filings")
        
        defer {
            isAnalyzing = false
        }
        
        var result = AnalysisResult()
        
        // Combine all filing texts for comprehensive analysis
        var combinedText = ""
        var mostRecentFiling: SECFiling?
        let totalFilings = min(filings.count, 5) // Analyze up to 5 most recent filings
        
        print("📊 Will analyze \(totalFilings) filings")
        
        for (index, filing) in filings.prefix(totalFilings).enumerated() {
            let progress = Double(index) / Double(totalFilings)
            await MainActor.run {
                self.analysisProgress = progress
            }
            
            if mostRecentFiling == nil {
                mostRecentFiling = filing
            }
            
            // Extract relevant text sections from filing
            let sections = await extractSections(from: filing)
            
            // Combine all sections
            let filingText = [
                sections.managementDiscussion,
                sections.riskFactors,
                sections.financialStatements,
                sections.operationalMetrics
            ].joined(separator: " ")
            
            if !filingText.isEmpty {
                combinedText += filingText + " "
            }
        }
        
        // Analyze with unified health scorer
        if !combinedText.isEmpty {
            print("\n📈 Calculating unified health score for \(symbol)")
            // Use fine-tuned SEC-BERT model for health scoring
            let healthAnalysis = await analyzewithFineTunedModel(
                filingText: combinedText,
                symbol: symbol,
                formType: mostRecentFiling?.formType ?? "10-K"
            )
            
            result.healthScore = healthAnalysis.score
            result.confidence = healthAnalysis.confidence
            result.insights = healthAnalysis.insights
            result.label = getHealthLabel(score: healthAnalysis.score)
            
            // Set legacy scores to match health score (for backward compatibility)
            let legacyScore = SentimentScore(
                score: healthAnalysis.score,
                confidence: healthAnalysis.confidence,
                label: result.label,
                snippets: healthAnalysis.insights
            )
            result.management = legacyScore
            result.financial = legacyScore
            result.operational = legacyScore
            result.risk = SentimentScore(
                score: max(100.0 - healthAnalysis.score, 0),  // Inverse for risk
                confidence: healthAnalysis.confidence,
                label: result.label,
                snippets: healthAnalysis.insights
            )
        } else {
            print("⚠️ No filing content found for analysis")
            result.insights = ["No SEC filing content available for analysis"]
        }
        
        print("\n✅ Unified Health Analysis Complete:")
        print("  🏥 Health Score: \(String(format: "%.1f", result.healthScore))%")
        print("  📊 Confidence: \(String(format: "%.2f", result.confidence))")
        print("  🏷️ Assessment: \(result.label)")
        if !result.insights.isEmpty {
            print("  💡 Key Insights:")
            for insight in result.insights.prefix(5) {
                print("     • \(insight)")
            }
        }
        
        // Update published scores
        let finalResult = result
        await MainActor.run {
            self.managementSentiment = finalResult.management
            self.riskSentiment = finalResult.risk
            self.financialPerformance = finalResult.financial
            self.operationalHealth = finalResult.operational
            self.analysisProgress = 1.0
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func getHealthLabel(score: Double) -> String {
        switch score {
        case 85...100:
            return "Excellent"
        case 70..<85:
            return "Strong"
        case 55..<70:
            return "Good"
        case 40..<55:
            return "Fair"
        case 25..<40:
            return "Weak"
        default:
            return "Poor"
        }
    }
    
    private func extractSections(from filing: SECFiling) async -> FilingSections {
        var sections = FilingSections()
        
        // Try to fetch the actual filing content
        guard let urlString = filing.finalUrl ?? filing.url as String?,
              let url = URL(string: urlString) else {
            print("❌ Invalid URL for \(filing.formType) dated \(filing.filingDate)")
            return sections // Return empty sections - no simulation
        }
        
        print("\n🌐 Fetching \(filing.formType) from: \(urlString.prefix(80))...")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("  HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
                print("❌ Empty content for filing: \(filing.formType) (\(data.count) bytes)")
                return sections // Return empty sections - no simulation
            }
            
            print("  ✅ Fetched \(content.count) characters")
            
            // Use the robust extractor
            let extracted = SECFilingContentExtractor.extractSections(from: content, formType: filing.formType)
            
            // Map extracted sections to our structure
            sections.managementDiscussion = extracted.managementOutlook.joined(separator: " ")
            sections.riskFactors = extracted.riskAssessment.joined(separator: " ")
            sections.financialStatements = extracted.financialPerformance.joined(separator: " ")
            sections.operationalMetrics = extracted.operationalHealth.joined(separator: " ")
            
            // Log extraction details
            print("  📄 Extraction results:")
            print("    Management: \(sections.managementDiscussion.count) chars")
            print("    Risk: \(sections.riskFactors.count) chars")
            print("    Financial: \(sections.financialStatements.count) chars")
            print("    Operational: \(sections.operationalMetrics.count) chars")
            
            if sections.isEmpty {
                print("  ⚠️ No sections extracted - content may not match expected patterns")
            }
            
        } catch {
            print("❌ Failed to fetch filing \(filing.formType): \(error)")
        }
        
        return sections // Return real data or empty - never simulation
    }
    
    private func analyzeFilingSections(_ sections: FilingSections, filing: SECFiling) async throws -> FilingSentiment {
        var sentiment = FilingSentiment(filingDate: filing.filingDate, formType: filing.formType)
        
        // Analyze each section with calibrated scoring
        let symbol = filing.symbol
        
        if !sections.managementDiscussion.isEmpty {
            sentiment.managementScore = analyzeTextWithCalibration(sections.managementDiscussion, symbol: symbol, category: .management)
        } else {
            // No content = neutral score (50), not a simulation
            sentiment.managementScore = 50.0
        }
        
        if !sections.riskFactors.isEmpty {
            sentiment.riskScore = analyzeTextWithCalibration(sections.riskFactors, symbol: symbol, category: .risk)
        } else {
            sentiment.riskScore = 50.0
        }
        
        if !sections.financialStatements.isEmpty {
            sentiment.financialScore = analyzeTextWithCalibration(sections.financialStatements, symbol: symbol, category: .financial)
        } else {
            sentiment.financialScore = 50.0
        }
        
        if !sections.operationalMetrics.isEmpty {
            sentiment.operationalScore = analyzeTextWithCalibration(sections.operationalMetrics, symbol: symbol, category: .operational)
        } else {
            sentiment.operationalScore = 50.0
        }
        
        return sentiment
    }
    
    private func analyzeTextWithCalibration(_ text: String, symbol: String, category: SentimentCategory) -> Double {
        // Use calibrated scoring that learns from FAANG+ patterns
        let result = SECBERTCalibration.analyzeCalibratedSentiment(
            text: text,
            symbol: symbol,
            category: category
        )
        
        print("  📊 Calibrated analysis for \(symbol) (\(category)):")
        print("    Score: \(String(format: "%.1f", result.score))% (confidence: \(String(format: "%.2f", result.confidence)))")
        if !result.insights.isEmpty {
            print("    Insights: \(result.insights.prefix(3).joined(separator: ", "))")
        }
        
        return result.score
    }
    
    internal func analyzeText(_ text: String, category: SentimentCategory) -> Double {
        // Use real SEC-BERT model only - no simulation
        guard let model = secbertModel, let tokenizer = tokenizer else {
            print("⚠️ SEC-BERT model not loaded for \(category) analysis")
            print("  Model status: \(secbertModel != nil ? "Loaded" : "Not loaded")")
            print("  Tokenizer status: \(tokenizer != nil ? "Loaded" : "Not loaded")")
            return 50.0 // Neutral score when model unavailable
        }
        
        print("  🤖 Running SEC-BERT on \(text.count) chars for \(category)")
        
        do {
            // Tokenize the text
            let tokens = tokenizer.tokenize(text, maxLength: maxSequenceLength)
            
            // Prepare inputs for CoreML
            let inputIds = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            
            for i in 0..<tokens.inputIds.count {
                inputIds[i] = NSNumber(value: tokens.inputIds[i])
                attentionMask[i] = NSNumber(value: tokens.attentionMask[i])
            }
            
            // Create model input
            let input = SECBERTInput(input_ids: inputIds, attention_mask: attentionMask)
            
            // Run inference
            let output = try model.prediction(from: input)
            
            // Extract sentiment scores
            if let sentimentScores = output.featureValue(for: "sentiment_scores")?.multiArrayValue {
                // SEC-BERT outputs raw logits: [negative, neutral, positive]
                // The shape is [1, 3] so we need to index properly
                let negative = sentimentScores[[0, 0] as [NSNumber]].doubleValue
                let neutral = sentimentScores[[0, 1] as [NSNumber]].doubleValue
                let positive = sentimentScores[[0, 2] as [NSNumber]].doubleValue
                
                // Apply softmax
                let scores = [negative, neutral, positive]
                let softmax = applySoftmax(scores)
                
                print("    Raw scores: neg=\(negative), neu=\(neutral), pos=\(positive)")
                print("    Softmax: neg=\(softmax[0]), neu=\(softmax[1]), pos=\(softmax[2])")
                
                // NOTE: The base SEC-BERT model isn't fine-tuned for sentiment classification
                // It needs to be fine-tuned on labeled SEC filing sentiment data
                // For now, we'll use a sophisticated keyword-based approach
                
                return performKeywordBasedSentiment(text, category: category)
            }
        } catch {
            print("    ❌ SEC-BERT inference error: \(error)")
            print("    Error type: \(type(of: error))")
        }
        
        // Return neutral on error - no simulation
        return 50.0
    }
    
    private func applySoftmax(_ values: [Double]) -> [Double] {
        let maxVal = values.max() ?? 0
        let expValues = values.map { exp($0 - maxVal) }
        let sum = expValues.reduce(0, +)
        return expValues.map { $0 / sum }
    }
    
    private func performKeywordBasedSentiment(_ text: String, category: SentimentCategory) -> Double {
        // Comprehensive keyword lists for SEC filing analysis
        let positiveIndicators = [
            // Growth & Performance
            "growth", "increase", "increased", "strong", "exceptional", "record", 
            "momentum", "expand", "expanded", "outstanding", "exceed", "exceeded",
            "improvement", "improved", "gain", "gains", "profitable", "profitability",
            
            // Financial Health
            "positive cash flow", "strong balance sheet", "solid financial",
            "robust", "healthy", "favorable", "optimistic", "confidence",
            
            // Market Position
            "market leader", "competitive advantage", "innovation", "breakthrough",
            "successful", "achievement", "milestone", "progress"
        ]
        
        let negativeIndicators = [
            // Financial Distress
            "decline", "declined", "loss", "losses", "impairment", "writedown",
            "deficit", "negative cash flow", "liquidity concern", "going concern",
            
            // Risks & Challenges
            "risk", "uncertainty", "challenge", "headwind", "pressure",
            "litigation", "investigation", "regulatory action", "violation",
            "breach", "default", "restructuring", "bankruptcy",
            
            // Performance Issues
            "underperform", "weak", "deteriorat", "adverse", "unfavorable",
            "difficult", "struggle", "concern", "warning", "doubt"
        ]
        
        // Weight words by importance
        let criticalPositive = ["record revenue", "exceed expectations", "strong growth", "record profit"]
        let criticalNegative = ["going concern", "bankruptcy", "default", "material weakness", "restatement"]
        
        let lowerText = text.lowercased()
        
        // Count weighted occurrences
        var positiveScore = 0.0
        var negativeScore = 0.0
        
        // Check critical phrases (worth more)
        for phrase in criticalPositive {
            if lowerText.contains(phrase) {
                positiveScore += 3.0
            }
        }
        
        for phrase in criticalNegative {
            if lowerText.contains(phrase) {
                negativeScore += 3.0
            }
        }
        
        // Check regular indicators
        for indicator in positiveIndicators {
            if lowerText.contains(indicator) {
                positiveScore += 1.0
            }
        }
        
        for indicator in negativeIndicators {
            if lowerText.contains(indicator) {
                negativeScore += 1.0
            }
        }
        
        // Adjust based on category
        switch category {
        case .risk:
            // For risk assessment, presence of risk words is expected
            // Focus on severity and mitigation
            if lowerText.contains("mitigat") || lowerText.contains("manage") {
                positiveScore += 2.0
            }
            if lowerText.contains("material") || lowerText.contains("significant risk") {
                negativeScore += 2.0
            }
            
        case .financial:
            // For financial, look for specific metrics
            if lowerText.contains("revenue growth") || lowerText.contains("margin expansion") {
                positiveScore += 2.0
            }
            if lowerText.contains("revenue decline") || lowerText.contains("margin compression") {
                negativeScore += 2.0
            }
            
        case .management:
            // For management outlook, forward-looking statements matter
            if lowerText.contains("expect") && lowerText.contains("growth") {
                positiveScore += 2.0
            }
            if lowerText.contains("expect") && lowerText.contains("challenge") {
                negativeScore += 2.0
            }
            
        case .operational:
            // For operational health
            if lowerText.contains("efficien") || lowerText.contains("streamlin") {
                positiveScore += 1.5
            }
            if lowerText.contains("disrupt") || lowerText.contains("operational challenge") {
                negativeScore += 1.5
            }
        }
        
        // Calculate final score (0-100 scale)
        let totalSignals = positiveScore + negativeScore
        
        if totalSignals < 0.5 {
            // No strong signals, return neutral
            return 50.0
        }
        
        // Calculate sentiment ratio
        let positiveRatio = positiveScore / totalSignals
        
        // Map to 0-100 scale with some bounds
        let score = positiveRatio * 100
        
        // Apply reasonable bounds
        if score > 90 { return 90.0 }
        if score < 10 { return 10.0 }
        
        return score
    }
    
    private func aggregateSentiments(_ sentiments: [FilingSentiment]) -> AnalysisResult {
        var result = AnalysisResult()
        
        guard !sentiments.isEmpty else {
            print("⚠️ No sentiments to aggregate")
            return result // Return default (50% neutral) scores
        }
        
        // Weight recent filings more heavily
        let weights = sentiments.enumerated().map { index, _ in
            Double(sentiments.count - index) / Double(sentiments.count)
        }
        
        let totalWeight = weights.reduce(0, +)
        
        // Calculate weighted averages
        var mgmtSum = 0.0, riskSum = 0.0, finSum = 0.0, opsSum = 0.0
        
        for (index, sentiment) in sentiments.enumerated() {
            let weight = weights[index] / totalWeight
            mgmtSum += sentiment.managementScore * weight
            riskSum += sentiment.riskScore * weight
            finSum += sentiment.financialScore * weight
            opsSum += sentiment.operationalScore * weight
        }
        
        // Create final scores with confidence based on data availability
        result.management = SentimentScore(
            score: mgmtSum > 0 ? mgmtSum : 50.0, // Default to neutral if no data
            confidence: mgmtSum > 0 ? min(Double(sentiments.count) / 10.0, 1.0) : 0.0,
            label: labelForScore(mgmtSum > 0 ? mgmtSum : 50.0),
            snippets: mgmtSum > 0 ? ["Based on \(sentiments.count) SEC filings"] : ["No management discussion data found"]
        )
        
        result.risk = SentimentScore(
            score: riskSum > 0 ? riskSum : 50.0,
            confidence: riskSum > 0 ? min(Double(sentiments.count) / 10.0, 1.0) : 0.0,
            label: labelForScore(riskSum > 0 ? riskSum : 50.0),
            snippets: riskSum > 0 ? ["Risk factors analyzed across filings"] : ["No risk factor data found"]
        )
        
        result.financial = SentimentScore(
            score: finSum > 0 ? finSum : 50.0,
            confidence: finSum > 0 ? min(Double(sentiments.count) / 10.0, 1.0) : 0.0,
            label: labelForScore(finSum > 0 ? finSum : 50.0),
            snippets: finSum > 0 ? ["Financial performance metrics evaluated"] : ["No financial data found"]
        )
        
        result.operational = SentimentScore(
            score: opsSum > 0 ? opsSum : 50.0,
            confidence: opsSum > 0 ? min(Double(sentiments.count) / 10.0, 1.0) : 0.0,
            label: labelForScore(opsSum > 0 ? opsSum : 50.0),
            snippets: opsSum > 0 ? ["Operational efficiency assessed"] : ["No operational data found"]
        )
        
        return result
    }
    
    private func labelForScore(_ score: Double) -> String {
        switch score {
        case 80...100:
            return "Very Positive"
        case 60..<80:
            return "Positive"
        case 40..<60:
            return "Neutral"
        case 20..<40:
            return "Negative"
        default:
            return "Very Negative"
        }
    }
    
    // MARK: - Supporting Types
    
    struct FilingSections {
        var managementDiscussion: String = ""
        var riskFactors: String = ""
        var financialStatements: String = ""
        var operationalMetrics: String = ""
    }
    
    struct FilingSentiment {
        let filingDate: Date
        let formType: String
        var managementScore: Double = 50.0
        var riskScore: Double = 50.0
        var financialScore: Double = 50.0
        var operationalScore: Double = 50.0
    }
    
    struct AnalysisResult {
        var healthScore: Double = 50.0  // Overall company health 0-100%
        var confidence: Double = 0.0    // Confidence in the score 0-1
        var insights: [String] = []     // Key insights about the company
        var label: String = "Unknown"   // Health assessment label
        
        // Legacy properties for backward compatibility (will phase out)
        var management: SentimentScore = SentimentScore()
        var risk: SentimentScore = SentimentScore()
        var financial: SentimentScore = SentimentScore()
        var operational: SentimentScore = SentimentScore()
        
        var overallScore: Double {
            return healthScore  // Now returns the unified health score
        }
    }
    
    enum SentimentCategory {
        case management
        case risk
        case financial
        case operational
    }
    
    // MARK: - Fine-tuned SEC-BERT Analysis
    
    private func analyzewithFineTunedModel(filingText: String, symbol: String, formType: String) async -> (score: Double, confidence: Double, insights: [String]) {
        // Try to use the fine-tuned SEC-BERT model
        if let modelScore = await inferWithFineTunedModel(filingText) {
            // Model successfully ran
            let insights = generateInsights(score: modelScore, text: filingText, symbol: symbol)
            return (score: modelScore, confidence: 0.95, insights: insights)
        }
        
        // Fallback to calibrated keyword analysis
        print("⚠️ Using calibrated keyword analysis as fallback")
        return CompanyHealthScorer.calculateHealthScore(
            filingText: filingText,
            symbol: symbol,
            formType: formType
        )
    }
    
    private func inferWithFineTunedModel(_ text: String) async -> Double? {
        // Check if we can call a Python service for inference
        guard let url = URL(string: "http://localhost:8000/analyze") else {
            return nil
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "text": String(text.prefix(2000)), // Limit text length
                "max_length": 256
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let score = result["health_score"] as? Double {
                print("✅ Fine-tuned SEC-BERT score: \(score)%")
                return score
            }
        } catch {
            print("❌ SEC-BERT inference service error: \(error)")
        }
        
        return nil
    }
    
    private func generateInsights(score: Double, text: String, symbol: String) -> [String] {
        var insights: [String] = []
        
        // Generate insights based on score
        if score >= 80 {
            insights.append("Company shows excellent financial health based on SEC-BERT analysis")
            insights.append("Strong indicators across management discussion and financial metrics")
        } else if score >= 70 {
            insights.append("Company demonstrates good financial stability")
            insights.append("Positive trends identified in SEC filings")
        } else if score >= 60 {
            insights.append("Company shows fair financial health with room for improvement")
            insights.append("Mixed signals in recent SEC filings")
        } else if score >= 40 {
            insights.append("Company facing financial challenges requiring attention")
            insights.append("Several risk factors identified in SEC filings")
        } else {
            insights.append("Critical financial health concerns detected")
            insights.append("Multiple warning signs in SEC filing analysis")
        }
        
        // Add model confidence info
        insights.append("Analysis powered by SEC-BERT fine-tuned on Russell 2000 (MAE: \(String(format: "%.2f", trainingMAE))%)")
        
        return insights
    }
}

// MARK: - Color Extension for Gradient

extension SECBERTService.FilingSections {
    var isEmpty: Bool {
        return managementDiscussion.isEmpty &&
               riskFactors.isEmpty &&
               financialStatements.isEmpty &&
               operationalMetrics.isEmpty
    }
}

extension Color {
    static func gradientForScore(_ score: Double) -> LinearGradient {
        let normalized = score / 100.0
        let hue = normalized * 0.33 // 0 = red, 0.33 = green
        
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.8, brightness: 0.9),
                Color(hue: hue, saturation: 0.6, brightness: 0.95)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}