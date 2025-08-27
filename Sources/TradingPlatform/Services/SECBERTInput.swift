import CoreML

/// Input provider for SEC-BERT CoreML model
class SECBERTInput: NSObject, MLFeatureProvider {
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