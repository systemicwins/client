#!/usr/bin/env python3
"""
Convert FinBERT model to CoreML for use in Swift
FinBERT is a BERT model fine-tuned on financial text for sentiment analysis
"""

import os
import sys
import numpy as np
import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import coremltools.proto.FeatureTypes_pb2 as ft

def download_finbert():
    """Download FinBERT model from HuggingFace"""
    print("📥 Downloading FinBERT model from HuggingFace...")
    
    # ProsusAI/finbert is the most popular financial sentiment BERT model
    model_name = "ProsusAI/finbert"
    
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSequenceClassification.from_pretrained(model_name)
    
    print("✅ FinBERT model downloaded successfully")
    return tokenizer, model

def create_sample_input():
    """Create sample input for model tracing"""
    # BERT typically uses 512 as max sequence length
    max_length = 512
    
    # Create dummy input tensors
    input_ids = torch.randint(0, 1000, (1, max_length))
    attention_mask = torch.ones(1, max_length, dtype=torch.long)
    
    return {
        "input_ids": input_ids,
        "attention_mask": attention_mask
    }

def convert_to_coreml(model, tokenizer):
    """Convert PyTorch FinBERT model to CoreML"""
    print("🔄 Converting to CoreML format...")
    
    # Set model to evaluation mode
    model.eval()
    
    # Create sample inputs for tracing
    sample_inputs = create_sample_input()
    
    # Create a wrapper that returns only the logits
    class FinBERTWrapper(torch.nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
        
        def forward(self, input_ids, attention_mask):
            outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
            return outputs.logits
    
    wrapped_model = FinBERTWrapper(model)
    wrapped_model.eval()
    
    # Trace the wrapped model
    traced_model = torch.jit.trace(
        wrapped_model, 
        (sample_inputs["input_ids"], sample_inputs["attention_mask"]),
        strict=False
    )
    
    # Define input types for CoreML
    inputs = [
        ct.TensorType(
            name="input_ids",
            shape=(1, 512),  # batch_size=1, sequence_length=512
            dtype=np.int32
        ),
        ct.TensorType(
            name="attention_mask", 
            shape=(1, 512),
            dtype=np.int32
        )
    ]
    
    # Define output type - FinBERT outputs 3 classes: positive, negative, neutral
    outputs = [
        ct.TensorType(
            name="sentiment_scores",
            dtype=np.float32
        )
    ]
    
    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=inputs,
        outputs=outputs,
        convert_to="neuralnetwork",  # Use Neural Network format to avoid BlobWriter issue
    )
    
    # Add metadata
    mlmodel.author = "ProsusAI (converted for Relentless Trading)"
    mlmodel.short_description = "FinBERT: Financial sentiment analysis model"
    mlmodel.version = "1.0"
    
    # Add class labels
    class_labels = ["negative", "neutral", "positive"]
    mlmodel.user_defined_metadata["classes"] = str(class_labels)
    
    print("✅ CoreML conversion complete")
    return mlmodel

def save_tokenizer_vocab(tokenizer, output_dir):
    """Save tokenizer vocabulary for Swift"""
    print("💾 Saving tokenizer vocabulary...")
    
    vocab_file = os.path.join(output_dir, "finbert_vocab.json")
    
    # Get vocabulary
    vocab = tokenizer.get_vocab()
    
    # Save vocabulary as JSON
    import json
    with open(vocab_file, 'w') as f:
        json.dump(vocab, f, indent=2)
    
    # Also save special tokens info
    special_tokens = {
        "pad_token": tokenizer.pad_token,
        "cls_token": tokenizer.cls_token,
        "sep_token": tokenizer.sep_token,
        "unk_token": tokenizer.unk_token,
        "mask_token": tokenizer.mask_token,
        "pad_token_id": tokenizer.pad_token_id,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token_id": tokenizer.sep_token_id,
        "unk_token_id": tokenizer.unk_token_id,
    }
    
    special_file = os.path.join(output_dir, "finbert_special_tokens.json")
    with open(special_file, 'w') as f:
        json.dump(special_tokens, f, indent=2)
    
    print(f"✅ Vocabulary saved to {vocab_file}")
    print(f"✅ Special tokens saved to {special_file}")

def test_model(mlmodel, tokenizer):
    """Test the CoreML model with sample financial text"""
    print("\n🧪 Testing CoreML model...")
    
    test_texts = [
        "Revenue increased by 25% year-over-year, exceeding analyst expectations.",
        "The company faces significant headwinds due to supply chain disruptions.",
        "Quarterly earnings remained stable compared to the previous period."
    ]
    
    for text in test_texts:
        print(f"\nText: '{text[:60]}...'")
        
        # Tokenize (simplified - in production use proper tokenization)
        tokens = tokenizer.encode_plus(
            text,
            max_length=512,
            padding='max_length',
            truncation=True,
            return_tensors='np'
        )
        
        # Prepare input
        input_data = {
            'input_ids': tokens['input_ids'].astype(np.int32),
            'attention_mask': tokens['attention_mask'].astype(np.int32)
        }
        
        try:
            # Run prediction
            prediction = mlmodel.predict(input_data)
            
            if 'sentiment_scores' in prediction:
                scores = prediction['sentiment_scores'][0]
                # Softmax to get probabilities
                probs = np.exp(scores) / np.sum(np.exp(scores))
                
                labels = ['negative', 'neutral', 'positive']
                for label, prob in zip(labels, probs):
                    print(f"  {label}: {prob:.3f}")
        except Exception as e:
            print(f"  Prediction error: {e}")

def main():
    """Main conversion pipeline"""
    print("🚀 FinBERT to CoreML Converter")
    print("=" * 50)
    
    # Check dependencies
    try:
        import coremltools
        import transformers
    except ImportError as e:
        print(f"❌ Missing dependency: {e}")
        print("\nInstall with:")
        print("pip install coremltools transformers torch")
        sys.exit(1)
    
    # Create output directory
    output_dir = "FinBERT_CoreML"
    os.makedirs(output_dir, exist_ok=True)
    
    # Download and convert
    tokenizer, pytorch_model = download_finbert()
    
    # Convert to CoreML
    coreml_model = convert_to_coreml(pytorch_model, tokenizer)
    
    # Save model as .mlmodel instead of .mlpackage
    model_path = os.path.join(output_dir, "FinBERT.mlmodel")
    coreml_model.save(model_path)
    print(f"✅ Model saved to {model_path}")
    
    # Save tokenizer vocabulary
    save_tokenizer_vocab(tokenizer, output_dir)
    
    # Test the model
    test_model(coreml_model, tokenizer)
    
    print("\n" + "=" * 50)
    print("✅ Conversion complete!")
    print(f"📁 Output directory: {output_dir}/")
    print("\nNext steps:")
    print("1. Add FinBERT.mlmodel to your Xcode project")
    print("2. Copy finbert_vocab.json to your app bundle")
    print("3. Use FinBERTService.swift to load and run the model")

if __name__ == "__main__":
    main()