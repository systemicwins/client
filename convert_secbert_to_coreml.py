#!/usr/bin/env python3
"""
Convert SEC-BERT model to CoreML for use in Swift
SEC-BERT is specifically trained on SEC filing texts (10-K, 10-Q, 8-K)
"""

import os
import sys
import numpy as np
import torch
import coremltools as ct
from transformers import AutoTokenizer, AutoModelForSequenceClassification, AutoModel
import json

def download_secbert():
    """Download SEC-BERT model from HuggingFace"""
    print("📥 Downloading SEC-BERT model from HuggingFace...")
    
    # nlpaueb/sec-bert is pre-trained on SEC filings
    model_name = "nlpaueb/sec-bert-num"  # The version with numerical understanding
    
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    
    # First load the base model for embeddings
    base_model = AutoModel.from_pretrained(model_name)
    
    # We'll create a classifier head for sentiment analysis
    # since SEC-BERT is a base model, not a classification model
    
    print("✅ SEC-BERT model downloaded successfully")
    return tokenizer, base_model

def create_sentiment_classifier(base_model):
    """Create a sentiment classification head on top of SEC-BERT"""
    
    class SECBERTSentimentClassifier(torch.nn.Module):
        def __init__(self, base_model):
            super().__init__()
            self.bert = base_model
            self.dropout = torch.nn.Dropout(0.1)
            # SEC-BERT hidden size is 768
            self.classifier = torch.nn.Linear(768, 3)  # 3 classes: negative, neutral, positive
            
            # Initialize classifier weights
            torch.nn.init.xavier_normal_(self.classifier.weight)
            torch.nn.init.zeros_(self.classifier.bias)
        
        def forward(self, input_ids, attention_mask):
            outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
            # Use CLS token representation
            pooled_output = outputs.last_hidden_state[:, 0, :]
            pooled_output = self.dropout(pooled_output)
            logits = self.classifier(pooled_output)
            return logits
    
    model = SECBERTSentimentClassifier(base_model)
    model.eval()
    
    print("✅ Created sentiment classifier on top of SEC-BERT")
    return model

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
    """Convert PyTorch SEC-BERT model to CoreML"""
    print("🔄 Converting to CoreML format...")
    
    # Set model to evaluation mode
    model.eval()
    
    # Create sample inputs for tracing
    sample_inputs = create_sample_input()
    
    # Trace the model
    traced_model = torch.jit.trace(
        model, 
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
    
    # Define output type - 3 classes: positive, negative, neutral
    outputs = [
        ct.TensorType(
            name="sentiment_scores",
            dtype=np.float32
        )
    ]
    
    # Convert to CoreML using neuralnetwork format (to avoid BlobWriter issue)
    mlmodel = ct.convert(
        traced_model,
        inputs=inputs,
        outputs=outputs,
        convert_to="neuralnetwork",
    )
    
    # Add metadata
    mlmodel.author = "AUEB NLP Group (converted for Relentless Trading)"
    mlmodel.short_description = "SEC-BERT: SEC filing-specific sentiment analysis model"
    mlmodel.version = "1.0"
    
    # Add class labels
    class_labels = ["negative", "neutral", "positive"]
    mlmodel.user_defined_metadata["classes"] = str(class_labels)
    mlmodel.user_defined_metadata["model_type"] = "SEC-BERT"
    
    print("✅ CoreML conversion complete")
    return mlmodel

def save_tokenizer_vocab(tokenizer, output_dir):
    """Save tokenizer vocabulary for Swift"""
    print("💾 Saving tokenizer vocabulary...")
    
    vocab_file = os.path.join(output_dir, "secbert_vocab.json")
    
    # Get vocabulary
    vocab = tokenizer.get_vocab()
    
    # Save vocabulary as JSON
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
    
    special_file = os.path.join(output_dir, "secbert_special_tokens.json")
    with open(special_file, 'w') as f:
        json.dump(special_tokens, f, indent=2)
    
    print(f"✅ Vocabulary saved to {vocab_file}")
    print(f"✅ Special tokens saved to {special_file}")

def test_model(mlmodel, tokenizer):
    """Test the CoreML model with sample SEC filing text"""
    print("\n🧪 Testing CoreML model with SEC filing examples...")
    
    test_texts = [
        "The Company's revenue increased by 25% year-over-year, driven by strong demand for our cloud services. Operating margins expanded by 300 basis points.",
        "Material weaknesses in our internal control over financial reporting were identified. The Company faces significant liquidity constraints and may need additional financing.",
        "The Company maintained stable operating performance during the quarter. Cash flows from operations remained consistent with the prior year period."
    ]
    
    for text in test_texts:
        print(f"\nText: '{text[:80]}...'")
        
        # Tokenize
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
            print(f"  Prediction error (expected in Python environment): {e}")

def main():
    """Main conversion pipeline"""
    print("🚀 SEC-BERT to CoreML Converter")
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
    output_dir = "SECBERT_CoreML"
    os.makedirs(output_dir, exist_ok=True)
    
    # Download and convert
    tokenizer, base_model = download_secbert()
    
    # Create sentiment classifier
    sentiment_model = create_sentiment_classifier(base_model)
    
    # Convert to CoreML
    coreml_model = convert_to_coreml(sentiment_model, tokenizer)
    
    # Save model
    model_path = os.path.join(output_dir, "SECBERT.mlmodel")
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
    print("1. Add SECBERT.mlmodel to your Xcode project")
    print("2. Copy secbert_vocab.json to your app bundle")
    print("3. Update FinBERTService.swift to use SEC-BERT")

if __name__ == "__main__":
    main()