#!/usr/bin/env python3
"""
Convert the fine-tuned PyTorch model to CoreML format
Run this locally on macOS after training completes on olympus
"""

import torch
import torch.nn as nn
import coremltools as ct
import json
import numpy as np
import os
from transformers import AutoModel

class SECBERTHealthPredictor(nn.Module):
    """SEC-BERT model fine-tuned for health score prediction"""
    
    def __init__(self, base_model_name='nlpaueb/sec-bert-base'):
        super().__init__()
        self.bert = AutoModel.from_pretrained(base_model_name)
        self.dropout = nn.Dropout(0.1)
        
        # Regression head for health score (0-1)
        self.regressor = nn.Sequential(
            nn.Linear(768, 256),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(256, 64),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(64, 1),
            nn.Sigmoid()  # Output 0-1 range
        )
    
    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        pooled_output = outputs.pooler_output  # [CLS] token representation
        output = self.dropout(pooled_output)
        score = self.regressor(output)
        return score.squeeze()

def convert_pytorch_to_coreml():
    """Convert PyTorch model to CoreML"""
    
    print("🔄 Converting PyTorch model to CoreML...")
    
    # Check if model file exists
    model_path = 'secbert_health_final.pt'
    if not os.path.exists(model_path):
        print(f"❌ Model file not found: {model_path}")
        print("   Please transfer the model from olympus first:")
        print("   scp olympus:~/relentless/finetune/secbert_health_final.pt .")
        return
    
    # Load the trained model
    print("📂 Loading trained model...")
    checkpoint = torch.load(model_path, map_location='cpu')
    
    # Initialize model architecture
    model = SECBERTHealthPredictor()
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    
    print("✅ Model loaded successfully")
    
    # Create sample input for tracing
    sample_input_ids = torch.randint(0, 1000, (1, 512))
    sample_attention_mask = torch.ones(1, 512, dtype=torch.long)
    
    # Trace the model
    print("🔧 Tracing model for CoreML conversion...")
    traced_model = torch.jit.trace(
        model,
        (sample_input_ids, sample_attention_mask)
    )
    
    # Convert to CoreML
    print("🔄 Converting to CoreML format...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 512), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, 512), dtype=np.int32)
        ],
        outputs=[
            ct.TensorType(name="health_score", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.macOS13
    )
    
    # Add metadata
    mlmodel.author = "SEC-BERT Russell 2000 Fine-tuned"
    mlmodel.short_description = "SEC-BERT fine-tuned on Russell 2000 companies for health scoring"
    mlmodel.version = "2.0"
    
    # Add custom metadata for health score ranges
    mlmodel.user_defined_metadata["health_ranges"] = json.dumps({
        "excellent": [85, 100],
        "strong": [70, 85],
        "good": [55, 70],
        "fair": [40, 55],
        "weak": [25, 40],
        "poor": [0, 25]
    })
    
    # Add training metrics if available
    if 'mae' in checkpoint:
        mlmodel.user_defined_metadata["training_mae"] = str(checkpoint['mae'])
    if 'val_loss' in checkpoint:
        mlmodel.user_defined_metadata["validation_loss"] = str(checkpoint['val_loss'])
    
    # Save model
    output_path = "SECBERT_Russell2000_Health.mlmodel"
    mlmodel.save(output_path)
    
    print(f"✅ CoreML model saved as {output_path}")
    print(f"📦 Model size: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")
    
    # Also check for vocabulary files
    vocab_files = ['secbert_health_vocab.json', 'secbert_health_special_tokens.json']
    missing_files = [f for f in vocab_files if not os.path.exists(f)]
    
    if missing_files:
        print(f"\n⚠️ Missing vocabulary files: {missing_files}")
        print("   Transfer them from olympus:")
        for f in missing_files:
            print(f"   scp olympus:~/relentless/finetune/{f} .")
    else:
        print("\n✅ All required files present")
    
    print("\n📋 Next steps:")
    print("1. Move model and vocab files to the app:")
    print("   mv SECBERT_Russell2000_Health.mlmodel Sources/TradingPlatform/Models/")
    print("   mv secbert_health_vocab.json Sources/TradingPlatform/Resources/")
    print("   mv secbert_health_special_tokens.json Sources/TradingPlatform/Resources/")
    print("2. Build and test the app with the new model")

def test_coreml_model():
    """Test the converted CoreML model"""
    
    model_path = "SECBERT_Russell2000_Health.mlmodel"
    if not os.path.exists(model_path):
        print("❌ CoreML model not found. Run conversion first.")
        return
    
    print("\n🧪 Testing CoreML model...")
    
    import coremltools
    model = coremltools.models.MLModel(model_path)
    
    print(f"Model description: {model.short_description}")
    print(f"Author: {model.author}")
    print(f"Version: {model.version}")
    
    # Test with dummy input
    test_input = {
        'input_ids': np.random.randint(0, 1000, (1, 512), dtype=np.int32),
        'attention_mask': np.ones((1, 512), dtype=np.int32)
    }
    
    try:
        output = model.predict(test_input)
        health_score = output['health_score'][0] * 100  # Convert to percentage
        print(f"\n✅ Model inference successful!")
        print(f"   Sample health score: {health_score:.1f}%")
    except Exception as e:
        print(f"❌ Model inference failed: {e}")

if __name__ == "__main__":
    convert_pytorch_to_coreml()
    test_coreml_model()