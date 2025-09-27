import Foundation
import CoreML

/// Fine-tuned SEC-BERT model for health score prediction
/// This model is trained on Russell 2000 SEC filings to predict company health (0-100%)
class SECBERTHealthModel {
    
    private var healthModel: MLModel?
    private var tokenizer: SECBERTTokenizer?
    private let maxSequenceLength = 512
    
    init() {
        loadFineTunedModel()
    }
    
    private func loadFineTunedModel() {
        print("\n🔄 Loading fine-tuned SEC-BERT health model...")
        
        // Try to load the fine-tuned model
        if let modelURL = Bundle.module.url(forResource: "SECBERT_Russell2000_Health", withExtension: "mlmodel") {
            do {
                // Check if model needs compilation
                if modelURL.pathExtension == "mlmodel" {
                    print("📦 Compiling fine-tuned model...")
                    let compiledURL = try MLModel.compileModel(at: modelURL)
                    
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndNeuralEngine
                    healthModel = try MLModel(contentsOf: compiledURL, configuration: config)
                    print("✅ Fine-tuned model loaded successfully")
                } else {
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndNeuralEngine
                    healthModel = try MLModel(contentsOf: modelURL, configuration: config)
                    print("✅ Fine-tuned model loaded successfully")
                }
                
                // Load tokenizer
                tokenizer = try SECBERTTokenizer(loadFromBundle: true)
                print("✅ Tokenizer loaded for fine-tuned model")
                
            } catch {
                print("❌ Failed to load fine-tuned model: \(error)")
                print("ℹ️ Falling back to keyword-based scoring")
            }
        } else {
            print("ℹ️ Fine-tuned model not found. Using keyword-based scoring.")
            print("   To enable ML scoring, run finetune_secbert_russell2000.py")
        }
    }
    
    /// Predict health score using fine-tuned SEC-BERT model
    func predictHealthScore(text: String) -> (score: Double, confidence: Double)? {
        guard let model = healthModel, let tokenizer = tokenizer else {
            return nil
        }
        
        do {
            // Tokenize the input text
            let tokens = tokenizer.tokenize(text, maxLength: maxSequenceLength)
            
            // Prepare inputs for CoreML
            let inputIds = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxSequenceLength)], dataType: .int32)
            
            for i in 0..<tokens.inputIds.count {
                inputIds[i] = NSNumber(value: tokens.inputIds[i])
                attentionMask[i] = NSNumber(value: tokens.attentionMask[i])
            }
            
            // Create model input
            let input = SECBERTHealthInput(input_ids: inputIds, attention_mask: attentionMask)
            
            // Run inference
            let output = try model.prediction(from: input)
            
            // Extract health score (model outputs 0-1, convert to 0-100)
            if let healthScore = output.featureValue(for: "health_score")?.doubleValue {
                let score = healthScore * 100.0
                
                // Calculate confidence based on how decisive the score is
                // Scores close to 50% have lower confidence
                let distanceFromMiddle = abs(score - 50.0)
                let confidence = min(distanceFromMiddle / 30.0, 1.0)
                
                return (score: score, confidence: confidence)
            }
            
        } catch {
            print("❌ Health prediction error: \(error)")
        }
        
        return nil
    }
    
    /// Analyze SEC filing and return comprehensive health assessment
    func analyzeFilingHealth(filingText: String, symbol: String) -> HealthAssessment {
        // Try ML-based prediction first
        if let mlPrediction = predictHealthScore(text: filingText) {
            print("🤖 Using fine-tuned ML model for health scoring")
            
            // Generate insights based on ML score
            let insights = generateMLInsights(
                score: mlPrediction.score,
                confidence: mlPrediction.confidence,
                symbol: symbol
            )
            
            return HealthAssessment(
                score: mlPrediction.score,
                confidence: mlPrediction.confidence,
                insights: insights,
                method: .machineLearning
            )
        }
        
        // Fallback to keyword-based scoring
        print("📝 Using keyword-based scoring (ML model not available)")
        let keywordResult = CompanyHealthScorer.calculateHealthScore(
            filingText: filingText,
            symbol: symbol
        )
        
        return HealthAssessment(
            score: keywordResult.score,
            confidence: keywordResult.confidence,
            insights: keywordResult.insights,
            method: .keywordBased
        )
    }
    
    private func generateMLInsights(score: Double, confidence: Double, symbol: String) -> [String] {
        var insights: [String] = []
        
        // Add score-based insights
        switch score {
        case 85...100:
            insights.append("🏆 Top-tier health (Russell 2000 leader level)")
            insights.append("Strong alignment with high-performing companies")
        case 70..<85:
            insights.append("💪 Strong health indicators")
            insights.append("Above-average Russell 2000 performance signals")
        case 55..<70:
            insights.append("📊 Solid health metrics")
            insights.append("Typical Russell 2000 company profile")
        case 40..<55:
            insights.append("⚡ Mixed health indicators")
            insights.append("Below Russell 2000 average")
        case 25..<40:
            insights.append("⚠️ Weak health signals")
            insights.append("Significant underperformance indicators")
        default:
            insights.append("🚨 Poor health indicators")
            insights.append("Critical concerns identified")
        }
        
        // Add confidence insight
        if confidence > 0.8 {
            insights.append("High confidence prediction (ML model)")
        } else if confidence > 0.6 {
            insights.append("Moderate confidence prediction (ML model)")
        } else {
            insights.append("Lower confidence - mixed signals")
        }
        
        // Add company classification if known
        let (tier, _) = Russell2000Calibration.classifyCompany(symbol: symbol)
        switch tier {
        case .smallCap:
            insights.append("Small-cap company profile")
        case .midCap:
            insights.append("Mid-cap company profile")
        case .largeCap, .megaCap:
            insights.append("Large-cap company profile")
        default:
            break
        }
        
        return insights
    }
    
    struct HealthAssessment {
        let score: Double
        let confidence: Double
        let insights: [String]
        let method: ScoringMethod
        
        enum ScoringMethod {
            case machineLearning
            case keywordBased
        }
    }
}

/// Input format for the fine-tuned health model
class SECBERTHealthInput: NSObject, MLFeatureProvider {
    var input_ids: MLMultiArray
    var attention_mask: MLMultiArray
    
    var featureNames: Set<String> {
        return ["input_ids", "attention_mask"]
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "input_ids":
            return MLFeatureValue(multiArray: input_ids)
        case "attention_mask":
            return MLFeatureValue(multiArray: attention_mask)
        default:
            return nil
        }
    }
    
    init(input_ids: MLMultiArray, attention_mask: MLMultiArray) {
        self.input_ids = input_ids
        self.attention_mask = attention_mask
        super.init()
    }
}