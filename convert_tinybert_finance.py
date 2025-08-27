#!/usr/bin/env python3
"""
Convert a lightweight financial sentiment model to CoreML
Using TinyBERT or MobileBERT for efficient on-device inference
"""

import os
import json
import torch
import torch.nn as nn
import numpy as np

def create_lightweight_model():
    """Create a lightweight sentiment model that will work with CoreML"""
    
    print("🚀 Creating lightweight financial sentiment model...")
    
    # Try to use a pre-trained small model first
    try:
        from transformers import AutoTokenizer, AutoModelForSequenceClassification
        
        # Try several lightweight models
        models_to_try = [
            "philschmid/MobileBERT-sst2",  # MobileBERT is very small
            "huawei-noah/TinyBERT_General_4L_312D",  # TinyBERT 4 layers
            "google/mobilebert-uncased",  # Google's MobileBERT
            "prajjwal1/bert-tiny",  # Tiny BERT (2 layers)
        ]
        
        model_loaded = False
        for model_name in models_to_try:
            try:
                print(f"Trying {model_name}...")
                tokenizer = AutoTokenizer.from_pretrained(model_name)
                model = AutoModelForSequenceClassification.from_pretrained(
                    model_name, 
                    num_labels=3,  # negative, neutral, positive
                    ignore_mismatched_sizes=True
                )
                model_loaded = True
                print(f"✅ Loaded {model_name}")
                break
            except Exception as e:
                print(f"  Failed: {e}")
                continue
        
        if not model_loaded:
            raise Exception("No pre-trained model could be loaded")
            
    except Exception as e:
        print(f"Failed to load pre-trained model: {e}")
        print("Creating custom lightweight model...")
        model, tokenizer = create_custom_lightweight_model()
    
    return model, tokenizer

def create_custom_lightweight_model():
    """Create a custom lightweight model from scratch"""
    
    class TinyFinancialSentimentModel(nn.Module):
        def __init__(self, vocab_size=5000, hidden_size=64, num_classes=3):
            super().__init__()
            # Very small architecture
            self.embedding = nn.Embedding(vocab_size, hidden_size)
            self.gru = nn.GRU(hidden_size, hidden_size, batch_first=True)
            self.attention = nn.Linear(hidden_size, 1)
            self.classifier = nn.Linear(hidden_size, num_classes)
            self.dropout = nn.Dropout(0.1)
            
        def forward(self, input_ids, attention_mask):
            # Embed
            embedded = self.embedding(input_ids)
            
            # GRU encoding
            output, _ = self.gru(embedded)
            
            # Simple attention pooling
            attention_weights = torch.softmax(self.attention(output), dim=1)
            weighted = torch.sum(output * attention_weights, dim=1)
            
            # Classify
            logits = self.classifier(self.dropout(weighted))
            
            return logits
    
    model = TinyFinancialSentimentModel()
    
    # Create a simple tokenizer
    class SimpleTokenizer:
        def __init__(self):
            self.vocab_size = 5000
            self.model_max_length = 128
            self.pad_token = "[PAD]"
            self.unk_token = "[UNK]"
            
        def get_vocab(self):
            # Create basic vocabulary
            vocab = {"[PAD]": 0, "[UNK]": 1, "[CLS]": 2, "[SEP]": 3}
            
            # Add financial terms
            financial_terms = [
                "revenue", "profit", "loss", "earnings", "growth", "decline",
                "increase", "decrease", "rise", "fall", "gain", "drop",
                "positive", "negative", "neutral", "strong", "weak",
                "quarter", "annual", "report", "guidance", "forecast",
                "beat", "miss", "exceed", "below", "above", "expectations"
            ]
            
            for i, term in enumerate(financial_terms):
                vocab[term] = i + 4
                
            return vocab
    
    tokenizer = SimpleTokenizer()
    
    return model, tokenizer

def convert_to_coreml_simple(model, tokenizer):
    """Convert the model to CoreML using simple approach"""
    
    import coremltools as ct
    
    print("🔄 Converting to CoreML...")
    
    # Wrap model to output only logits
    class ModelWrapper(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
            
        def forward(self, input_ids, attention_mask):
            if hasattr(self.model, 'forward'):
                output = self.model(input_ids, attention_mask)
                if hasattr(output, 'logits'):
                    return output.logits
                return output
            return self.model(input_ids, attention_mask)
    
    wrapped = ModelWrapper(model)
    wrapped.eval()
    
    # Create example input
    max_length = 128
    example_input_ids = torch.randint(0, 1000, (1, max_length), dtype=torch.long)
    example_attention_mask = torch.ones(1, max_length, dtype=torch.float32)
    
    # Trace the model
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, (example_input_ids, example_attention_mask))
    
    # Convert to CoreML
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[
                ct.TensorType(name="input_ids", shape=(1, max_length), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, max_length), dtype=np.float32)
            ],
            outputs=[ct.TensorType(name="logits", dtype=np.float32)],
            convert_to="neuralnetwork",  # Use neuralnetwork for compatibility
            minimum_deployment_target=ct.target.iOS15
        )
        
        # Add metadata
        mlmodel.author = "Relentless Trading"
        mlmodel.short_description = "Lightweight financial sentiment analysis"
        mlmodel.version = "1.0"
        
        return mlmodel
        
    except Exception as e:
        print(f"CoreML conversion error: {e}")
        # Try with ML Program instead
        try:
            mlmodel = ct.convert(
                traced,
                inputs=[
                    ct.TensorType(name="input_ids", shape=(ct.RangeDim(1, 1), max_length), dtype=np.int32),
                    ct.TensorType(name="attention_mask", shape=(ct.RangeDim(1, 1), max_length), dtype=np.float32)
                ],
                convert_to="mlprogram",
                minimum_deployment_target=ct.target.iOS16
            )
            return mlmodel
        except Exception as e2:
            print(f"ML Program conversion also failed: {e2}")
            return None

def main():
    print("=" * 60)
    print("Financial Sentiment Model to CoreML Converter")
    print("=" * 60)
    
    # Check for coremltools
    try:
        import coremltools as ct
        print(f"✅ CoreML Tools version: {ct.__version__}")
    except ImportError:
        print("❌ Installing coremltools...")
        os.system("pip3 install coremltools")
        import coremltools as ct
    
    # Create output directory
    output_dir = "/Users/alex/relentless/client/Models"
    os.makedirs(output_dir, exist_ok=True)
    
    # Create or load model
    model, tokenizer = create_lightweight_model()
    
    # Save tokenizer config
    print("📝 Saving tokenizer configuration...")
    tokenizer_config = {
        "vocab": tokenizer.get_vocab() if hasattr(tokenizer, 'get_vocab') else {"[PAD]": 0, "[UNK]": 1},
        "max_length": getattr(tokenizer, 'model_max_length', 128),
        "pad_token": getattr(tokenizer, 'pad_token', "[PAD]"),
        "unk_token": getattr(tokenizer, 'unk_token', "[UNK]"),
    }
    
    with open(os.path.join(output_dir, "tokenizer_config.json"), 'w') as f:
        json.dump(tokenizer_config, f, indent=2)
    print(f"✅ Tokenizer saved to {output_dir}/tokenizer_config.json")
    
    # Convert to CoreML
    mlmodel = convert_to_coreml_simple(model, tokenizer)
    
    if mlmodel:
        # Save the model
        model_path = os.path.join(output_dir, "TinyFinancialSentiment.mlmodel")
        mlmodel.save(model_path)
        print(f"✅ CoreML model saved to {model_path}")
        
        # Create Swift implementation
        create_swift_code(output_dir)
        
        print("\n" + "=" * 60)
        print("✨ SUCCESS! Model converted to CoreML")
        print("=" * 60)
        print("\nNext steps:")
        print("1. Add TinyFinancialSentiment.mlmodel to your Xcode project")
        print("2. Add tokenizer_config.json as a resource")
        print("3. Use LocalFinancialAnalyzer.swift for inference")
        
    else:
        print("\n❌ Failed to convert model to CoreML")
        print("Try installing: pip3 install --upgrade coremltools")

def create_swift_code(output_dir):
    """Create Swift implementation for the model"""
    
    swift_code = '''
import CoreML
import Foundation

/// Local financial sentiment analyzer using CoreML
public class LocalFinancialAnalyzer {
    
    private let model: MLModel
    private let tokenizer: SimpleTokenizer
    
    public init() throws {
        // Load CoreML model
        guard let modelURL = Bundle.main.url(forResource: "TinyFinancialSentiment", withExtension: "mlmodel") else {
            throw AnalyzerError.modelNotFound
        }
        self.model = try MLModel(contentsOf: modelURL)
        
        // Load tokenizer
        guard let tokenizerURL = Bundle.main.url(forResource: "tokenizer_config", withExtension: "json"),
              let data = try? Data(contentsOf: tokenizerURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalyzerError.tokenizerNotFound
        }
        
        self.tokenizer = SimpleTokenizer(config: config)
    }
    
    public func analyzeSentiment(_ text: String) throws -> SentimentResult {
        // Tokenize
        let (inputIds, attentionMask) = tokenizer.encode(text)
        
        // Prepare input
        let inputArray = try MLMultiArray(shape: [1, 128], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, 128], dataType: .float32)
        
        for i in 0..<128 {
            inputArray[i] = NSNumber(value: inputIds[i])
            maskArray[i] = NSNumber(value: attentionMask[i])
        }
        
        // Run inference
        let input = MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputArray,
            "attention_mask": maskArray
        ])
        
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw AnalyzerError.inferenceFailed
        }
        
        // Process output
        let probs = softmax(logits)
        let sentiment = Sentiment.allCases[probs.argmax()]
        
        return SentimentResult(
            sentiment: sentiment,
            confidence: probs[sentiment.rawValue],
            text: String(text.prefix(100))
        )
    }
}

public enum Sentiment: Int, CaseIterable {
    case negative = 0
    case neutral = 1
    case positive = 2
}

public struct SentimentResult {
    public let sentiment: Sentiment
    public let confidence: Double
    public let text: String
}

enum AnalyzerError: Error {
    case modelNotFound
    case tokenizerNotFound
    case inferenceFailed
}
'''
    
    with open(os.path.join(output_dir, "LocalFinancialAnalyzer.swift"), 'w') as f:
        f.write(swift_code)
    
    print(f"✅ Swift code saved to {output_dir}/LocalFinancialAnalyzer.swift")

if __name__ == "__main__":
    main()