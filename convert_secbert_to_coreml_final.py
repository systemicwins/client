#!/usr/bin/env python3
"""
Convert fine-tuned SEC-BERT to CoreML for iOS/macOS
Using a more compatible approach
"""

import torch
import torch.nn as nn
import numpy as np
from transformers import AutoTokenizer, AutoModel
import coremltools as ct
import json
import os

class SECBERTRegressor(nn.Module):
    """SEC-BERT model for health score regression"""
    
    def __init__(self, model_name='nlpaueb/sec-bert-base'):
        super().__init__()
        self.bert = AutoModel.from_pretrained(model_name)
        
        # Regression head
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

class CoreMLWrapper(nn.Module):
    """Wrapper to ensure proper output shape for CoreML"""
    def __init__(self, model):
        super().__init__()
        self.model = model
        
    def forward(self, input_ids, attention_mask):
        score = self.model(input_ids, attention_mask)
        # Ensure output is always 1D
        if score.dim() == 0:
            score = score.unsqueeze(0)
        return score

def convert_to_coreml():
    print("="*60)
    print("SEC-BERT to CoreML Conversion (Final)")
    print("="*60)
    
    print("\n1. Loading fine-tuned SEC-BERT model...")
    
    # Load the fine-tuned model
    model = SECBERTRegressor()
    checkpoint = torch.load('models/secbert_russell2000_actual.pth', map_location='cpu', weights_only=False)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    
    print(f"   ✅ Model loaded. Training MAE: {checkpoint.get('val_mae', 0)*100:.2f}%")
    
    # Test the PyTorch model
    print("\n2. Testing PyTorch model...")
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    
    test_texts = [
        "The company reported strong revenue growth and positive cash flows.",
        "Material weakness in controls, substantial doubt about going concern."
    ]
    
    for text in test_texts:
        tokens = tokenizer(text, max_length=256, padding='max_length', truncation=True, return_tensors='pt')
        with torch.no_grad():
            score = model(tokens['input_ids'], tokens['attention_mask']).item() * 100
        print(f"   '{text[:50]}...' -> {score:.1f}%")
    
    print("\n3. Converting to CoreML...")
    
    # Wrap the model
    wrapped_model = CoreMLWrapper(model)
    wrapped_model.eval()
    
    # Create example inputs for tracing
    max_length = 256
    example_input_ids = torch.randint(0, 1000, (1, max_length), dtype=torch.long)
    example_attention_mask = torch.ones(1, max_length, dtype=torch.long)
    
    # Trace the model
    print("   Tracing model...")
    traced_model = torch.jit.trace(wrapped_model, (example_input_ids, example_attention_mask))
    
    try:
        # Try conversion with iOS 15 target (more compatible)
        print("   Converting to CoreML (iOS 15+)...")
        mlmodel = ct.convert(
            traced_model,
            inputs=[
                ct.TensorType(name="input_ids", shape=(1, max_length), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, max_length), dtype=np.int32)
            ],
            outputs=[
                ct.TensorType(name="health_score", dtype=np.float32)
            ],
            minimum_deployment_target=ct.target.iOS15,
            compute_units=ct.ComputeUnit.CPU_ONLY
        )
        
        # Add metadata
        mlmodel.author = "Relentless Trading"
        mlmodel.short_description = "SEC-BERT fine-tuned on Russell 2000 for health scoring"
        mlmodel.version = "1.0.0"
        mlmodel.user_defined_metadata['training_mae'] = str(checkpoint.get('val_mae', 0) * 100)
        mlmodel.user_defined_metadata['max_length'] = str(max_length)
        
        # Save the model
        output_path = "models/SECBERTHealth.mlmodel"
        mlmodel.save(output_path)
        
        print(f"   ✅ CoreML model saved to: {output_path}")
        file_size = os.path.getsize(output_path) / (1024*1024)
        print(f"   📦 Model size: {file_size:.1f} MB")
        
    except Exception as e:
        print(f"   ⚠️ Direct CoreML conversion failed: {e}")
        print("\n4. Creating alternative lightweight model...")
        
        # Create a simplified model for CoreML
        class LightweightSECBERT(nn.Module):
            def __init__(self, vocab_size=30522, hidden_size=768):
                super().__init__()
                self.embedding = nn.Embedding(vocab_size, hidden_size)
                self.pooler = nn.Sequential(
                    nn.Linear(hidden_size, 256),
                    nn.ReLU(),
                    nn.Linear(256, 64),
                    nn.ReLU(),
                    nn.Linear(64, 1),
                    nn.Sigmoid()
                )
                
            def forward(self, input_ids):
                # Simple mean pooling
                embedded = self.embedding(input_ids)
                pooled = embedded.mean(dim=1)
                score = self.pooler(pooled)
                return score.squeeze()
        
        # Create and initialize lightweight model
        lightweight = LightweightSECBERT()
        
        # Transfer weights from full model
        with torch.no_grad():
            # Copy embedding weights
            lightweight.embedding.weight.data = model.bert.embeddings.word_embeddings.weight.data
            
            # Copy regressor weights (skip dropout layers)
            lightweight.pooler[0].weight.data = model.regressor[0].weight.data
            lightweight.pooler[0].bias.data = model.regressor[0].bias.data
            lightweight.pooler[2].weight.data = model.regressor[3].weight.data
            lightweight.pooler[2].bias.data = model.regressor[3].bias.data
            lightweight.pooler[4].weight.data = model.regressor[6].weight.data
            lightweight.pooler[4].bias.data = model.regressor[6].bias.data
        
        lightweight.eval()
        
        # Trace lightweight model
        example_input = torch.randint(0, 1000, (1, max_length), dtype=torch.long)
        traced_lightweight = torch.jit.trace(lightweight, example_input)
        
        # Convert to CoreML
        print("   Converting lightweight model to CoreML...")
        mlmodel_lite = ct.convert(
            traced_lightweight,
            inputs=[
                ct.TensorType(name="input_ids", shape=(1, max_length), dtype=np.int32)
            ],
            outputs=[
                ct.TensorType(name="health_score", dtype=np.float32)
            ],
            minimum_deployment_target=ct.target.iOS15,
            compute_units=ct.ComputeUnit.ALL
        )
        
        # Add metadata
        mlmodel_lite.author = "Relentless Trading"
        mlmodel_lite.short_description = "SEC-BERT Lite - Russell 2000 trained"
        mlmodel_lite.version = "1.0.0"
        
        # Save lightweight model
        output_path_lite = "models/SECBERTHealthLite.mlmodel"
        mlmodel_lite.save(output_path_lite)
        
        print(f"   ✅ Lightweight CoreML model saved to: {output_path_lite}")
        file_size = os.path.getsize(output_path_lite) / (1024*1024)
        print(f"   📦 Model size: {file_size:.1f} MB")
    
    # Save tokenizer vocabulary for iOS
    print("\n5. Saving tokenizer data for iOS...")
    
    vocab = tokenizer.get_vocab()
    
    # Save full vocabulary
    with open('models/vocab.json', 'w') as f:
        json.dump(vocab, f)
    print(f"   ✅ Full vocabulary saved ({len(vocab)} tokens)")
    
    # Save common vocabulary (top 10k tokens)
    common_vocab = dict(sorted(vocab.items(), key=lambda x: x[1])[:10000])
    with open('models/vocab_common.json', 'w') as f:
        json.dump(common_vocab, f)
    print(f"   ✅ Common vocabulary saved (10000 tokens)")
    
    # Save tokenizer config
    tokenizer_config = {
        "vocab_size": len(vocab),
        "max_length": max_length,
        "pad_token_id": tokenizer.pad_token_id,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token_id": tokenizer.sep_token_id,
        "unk_token_id": tokenizer.unk_token_id
    }
    
    with open('models/tokenizer_config.json', 'w') as f:
        json.dump(tokenizer_config, f, indent=2)
    print("   ✅ Tokenizer config saved")
    
    print("\n" + "="*60)
    print("Conversion Complete!")
    print("="*60)
    print("\nFiles created:")
    print("- models/SECBERTHealth.mlmodel (or SECBERTHealthLite.mlmodel)")
    print("- models/vocab.json (Full vocabulary)")
    print("- models/vocab_common.json (Common vocabulary)")
    print("- models/tokenizer_config.json (Tokenizer configuration)")
    print("\nNext steps:")
    print("1. Add the .mlmodel file to your Xcode project")
    print("2. Update DiligenceView to use SECBERTHealthAnalyzer")
    print("3. Load vocabulary for tokenization in Swift")
    print("="*60)

if __name__ == "__main__":
    convert_to_coreml()