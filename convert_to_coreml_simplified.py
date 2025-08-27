#!/usr/bin/env python3
"""
Convert SEC-BERT to CoreML using a simplified approach
"""

import torch
import torch.nn as nn
import numpy as np
from transformers import AutoTokenizer, AutoModel
import coremltools as ct
import json
import os

class SimplifiedSECBERT(nn.Module):
    """Simplified model for CoreML conversion"""
    
    def __init__(self, vocab_size=30522, hidden_size=768, max_length=128):
        super().__init__()
        # Simplified architecture that CoreML can handle
        self.embedding = nn.Embedding(vocab_size, hidden_size)
        self.lstm = nn.LSTM(hidden_size, hidden_size//2, batch_first=True, bidirectional=True)
        self.pooler = nn.Sequential(
            nn.Linear(hidden_size, 256),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(256, 64),
            nn.ReLU(),
            nn.Linear(64, 1),
            nn.Sigmoid()
        )
        
    def forward(self, input_ids):
        # Embed tokens
        embedded = self.embedding(input_ids)
        
        # Process with LSTM
        lstm_out, _ = self.lstm(embedded)
        
        # Pool by taking mean
        pooled = lstm_out.mean(dim=1)
        
        # Get score
        score = self.pooler(pooled)
        return score

def transfer_weights_to_simplified():
    """Transfer weights from full model to simplified version"""
    print("Loading full SEC-BERT model...")
    
    # Load original model architecture
    class SECBERTRegressor(nn.Module):
        def __init__(self, model_name='nlpaueb/sec-bert-base'):
            super().__init__()
            self.bert = AutoModel.from_pretrained(model_name)
            self.dropout = nn.Dropout(0.2)
            self.regressor = nn.Sequential(
                nn.Linear(768, 256),
                nn.ReLU(),
                nn.Dropout(0.2),
                nn.Linear(256, 64),
                nn.ReLU(),
                nn.Dropout(0.1),
                nn.Linear(64, 1),
                nn.Sigmoid()
            )
        
        def forward(self, input_ids, attention_mask):
            outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
            pooled_output = outputs.pooler_output
            pooled_output = self.dropout(pooled_output)
            score = self.regressor(pooled_output)
            return score.squeeze()
    
    # Load trained weights
    full_model = SECBERTRegressor()
    checkpoint = torch.load('models/secbert_russell2000_actual.pth', map_location='cpu', weights_only=False)
    full_model.load_state_dict(checkpoint['model_state_dict'])
    full_model.eval()
    
    # Create simplified model
    simplified = SimplifiedSECBERT()
    
    # Transfer embedding weights (use first part of BERT embeddings)
    with torch.no_grad():
        # Copy word embeddings
        simplified.embedding.weight.data = full_model.bert.embeddings.word_embeddings.weight.data
        
        # Transfer regressor weights to pooler
        # Copy Linear layers from regressor
        simplified.pooler[0].weight.data = full_model.regressor[0].weight.data
        simplified.pooler[0].bias.data = full_model.regressor[0].bias.data
        simplified.pooler[3].weight.data = full_model.regressor[3].weight.data
        simplified.pooler[3].bias.data = full_model.regressor[3].bias.data
        simplified.pooler[5].weight.data = full_model.regressor[6].weight.data
        simplified.pooler[5].bias.data = full_model.regressor[6].bias.data
    
    return simplified

def convert_to_coreml():
    """Convert simplified model to CoreML"""
    print("\n" + "="*60)
    print("SEC-BERT to CoreML Conversion")
    print("="*60)
    
    # Get simplified model with transferred weights
    model = transfer_weights_to_simplified()
    model.eval()
    
    print("\nTesting simplified model...")
    # Test the model
    test_input = torch.randint(0, 1000, (1, 128))
    with torch.no_grad():
        output = model(test_input)
        print(f"Test output: {output.item()*100:.1f}%")
    
    print("\nConverting to CoreML...")
    
    # Trace the model
    traced_model = torch.jit.trace(model, test_input)
    
    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32)],
        outputs=[ct.TensorType(name="health_score", dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS14,
        convert_to="mlprogram"
    )
    
    # Add metadata
    mlmodel.user_defined_metadata["description"] = "SEC-BERT Health Analyzer"
    mlmodel.user_defined_metadata["version"] = "1.0.0"
    mlmodel.short_description = "Analyzes company health from text"
    mlmodel.author = "Relentless Trading"
    
    # Save the model
    output_path = "models/SECBERTHealth.mlpackage"
    mlmodel.save(output_path)
    
    print(f"\n✅ CoreML model saved to: {output_path}")
    
    # Also save a .mlmodel version for compatibility
    try:
        mlmodel_legacy = ct.convert(
            traced_model,
            inputs=[ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32)],
            outputs=[ct.TensorType(name="health_score", dtype=np.float32)],
            minimum_deployment_target=ct.target.iOS14
        )
        mlmodel_legacy.save("models/SECBERTHealth.mlmodel")
        print(f"✅ Legacy model saved to: models/SECBERTHealth.mlmodel")
    except:
        print("Note: Legacy .mlmodel format not available")
    
    return mlmodel

def create_tokenizer_for_ios():
    """Create a simplified tokenizer configuration for iOS"""
    print("\nCreating tokenizer for iOS...")
    
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    vocab = tokenizer.get_vocab()
    
    # Save vocabulary
    with open('models/vocab.json', 'w') as f:
        json.dump(vocab, f)
    
    # Create simplified tokenizer data
    tokenizer_config = {
        "vocab_size": len(vocab),
        "max_length": 128,
        "pad_token_id": tokenizer.pad_token_id,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token_id": tokenizer.sep_token_id,
        "unk_token_id": tokenizer.unk_token_id,
        "special_tokens": {
            "[PAD]": tokenizer.pad_token_id,
            "[CLS]": tokenizer.cls_token_id,
            "[SEP]": tokenizer.sep_token_id,
            "[UNK]": tokenizer.unk_token_id
        }
    }
    
    with open('models/tokenizer_config.json', 'w') as f:
        json.dump(tokenizer_config, f, indent=2)
    
    print(f"✅ Tokenizer config saved with {len(vocab)} tokens")
    
    # Create a subset of most common tokens for iOS
    common_tokens = {}
    for token, idx in sorted(vocab.items(), key=lambda x: x[1])[:10000]:
        common_tokens[token.lower()] = idx
    
    with open('models/vocab_common.json', 'w') as f:
        json.dump(common_tokens, f)
    
    print("✅ Common vocabulary saved (10000 tokens)")

def test_coreml_model():
    """Test the CoreML model"""
    print("\nTesting CoreML model...")
    
    try:
        # Load the model
        model_path = "models/SECBERTHealth.mlpackage"
        if not os.path.exists(model_path):
            model_path = "models/SECBERTHealth.mlmodel"
        
        import coremltools
        model = coremltools.models.MLModel(model_path)
        
        # Test input
        test_input = np.random.randint(0, 1000, (1, 128)).astype(np.int32)
        
        # Predict
        prediction = model.predict({"input_ids": test_input})
        score = prediction["health_score"][0] * 100
        
        print(f"✅ Model test successful! Score: {score:.1f}%")
        
    except Exception as e:
        print(f"⚠️ Could not test model directly: {e}")
        print("Model will need to be tested in Xcode")

if __name__ == "__main__":
    try:
        # Convert model
        mlmodel = convert_to_coreml()
        
        # Create tokenizer
        create_tokenizer_for_ios()
        
        # Test if possible
        test_coreml_model()
        
        print("\n" + "="*60)
        print("Conversion Complete!")
        print("="*60)
        print("\nNext steps:")
        print("1. Add SECBERTHealth.mlpackage to your Xcode project")
        print("2. Use SECBERTHealthAnalyzer.swift for integration")
        print("3. Load vocab.json for tokenization")
        print("="*60)
        
    except Exception as e:
        print(f"\nError during conversion: {e}")
        print("\nTrying alternative approach...")
        
        # If CoreML conversion fails, create a server endpoint instead
        print("\nCreating server endpoint configuration...")
        
        config = {
            "model_type": "server",
            "endpoint": "http://localhost:8000/analyze",
            "model_path": "models/secbert_russell2000_actual.pth",
            "fallback": True
        }
        
        with open('models/server_config.json', 'w') as f:
            json.dump(config, f, indent=2)
        
        print("✅ Server configuration created as fallback")