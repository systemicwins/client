#!/usr/bin/env python3
"""
Convert fine-tuned SEC-BERT model to CoreML for iOS deployment
"""

import torch
import torch.nn as nn
import coremltools as ct
import numpy as np
from transformers import AutoTokenizer, AutoModel
import json
import os

class SECBERTRegressor(nn.Module):
    """SEC-BERT model for health score regression - must match training architecture"""
    
    def __init__(self, model_name='nlpaueb/sec-bert-base'):
        super().__init__()
        self.bert = AutoModel.from_pretrained(model_name)
        
        # Regression head - must match training architecture exactly
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

def convert_to_coreml():
    print("="*60)
    print("SEC-BERT to CoreML Converter")
    print("="*60)
    
    print("\n1. Loading fine-tuned SEC-BERT model...")
    
    # Initialize model
    model = SECBERTRegressor()
    
    # Load fine-tuned weights
    checkpoint = torch.load('models/secbert_russell2000_actual.pth', map_location='cpu')
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    
    print(f"   ✅ Model loaded. Training MAE: {checkpoint.get('val_mae', 0)*100:.2f}%")
    
    # Test PyTorch model first
    print("\n2. Testing PyTorch model...")
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    
    test_texts = [
        "Strong revenue growth and positive cash flows",
        "Material weakness in internal controls, going concern doubt"
    ]
    
    for text in test_texts:
        tokens = tokenizer(text, max_length=256, padding='max_length', truncation=True, return_tensors='pt')
        with torch.no_grad():
            score = model(tokens['input_ids'], tokens['attention_mask']).item() * 100
        print(f"   '{text[:40]}...' -> {score:.1f}%")
    
    print("\n3. Converting to CoreML...")
    
    # Create wrapper for CoreML conversion
    class CoreMLWrapper(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model
            
        def forward(self, input_ids, attention_mask):
            # Ensure proper dimensions
            score = self.model(input_ids, attention_mask)
            if score.dim() == 0:
                score = score.unsqueeze(0)
            return score
    
    wrapped_model = CoreMLWrapper(model)
    wrapped_model.eval()
    
    # Prepare example inputs
    max_length = 256
    example_input_ids = torch.randint(0, 1000, (1, max_length))
    example_attention_mask = torch.ones(1, max_length)
    
    # Trace model
    traced_model = torch.jit.trace(wrapped_model, (example_input_ids, example_attention_mask))
    
    # Convert to CoreML
    try:
        coreml_model = ct.convert(
            traced_model,
            inputs=[
                ct.TensorType(name="input_ids", shape=(1, max_length), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, max_length), dtype=np.int32)
            ],
            outputs=[ct.TensorType(name="health_score", dtype=np.float32)],
            compute_units=ct.ComputeUnit.CPU_ONLY,  # Start with CPU only
            minimum_deployment_target=ct.target.iOS15
        )
        
        # Add metadata
        coreml_model.author = "Relentless Trading"
        coreml_model.short_description = "SEC-BERT fine-tuned on Russell 2000"
        coreml_model.version = "1.0.0"
        
        # Save model
        output_path = "models/SECBERTHealth.mlmodel"
        coreml_model.save(output_path)
        
        print(f"   ✅ CoreML model saved to: {output_path}")
        print(f"   Size: {os.path.getsize(output_path) / (1024*1024):.1f} MB")
        
    except Exception as e:
        print(f"   ❌ CoreML conversion failed: {e}")
        print("   Attempting alternative conversion method...")
        
        # Try ONNX intermediate format
        try:
            import torch.onnx
            
            # Export to ONNX
            onnx_path = "models/secbert_temp.onnx"
            torch.onnx.export(
                wrapped_model,
                (example_input_ids, example_attention_mask),
                onnx_path,
                input_names=['input_ids', 'attention_mask'],
                output_names=['health_score'],
                dynamic_axes={'input_ids': {0: 'batch'}, 'attention_mask': {0: 'batch'}},
                opset_version=11
            )
            
            print(f"   ✅ ONNX export successful")
            
            # Convert ONNX to CoreML
            coreml_model = ct.convert(
                onnx_path,
                minimum_deployment_target=ct.target.iOS15
            )
            
            output_path = "models/SECBERTHealth.mlmodel"
            coreml_model.save(output_path)
            print(f"   ✅ CoreML model saved via ONNX: {output_path}")
            
            # Clean up
            os.remove(onnx_path)
            
        except Exception as e2:
            print(f"   ❌ ONNX conversion also failed: {e2}")
            print("   Model may be too complex for direct conversion")
    
    # Save tokenizer vocabulary
    print("\n4. Saving tokenizer vocabulary...")
    vocab = tokenizer.get_vocab()
    with open('models/secbert_vocab.json', 'w') as f:
        json.dump(vocab, f)
    print(f"   ✅ Vocabulary saved ({len(vocab)} tokens)")
    
    # Create usage example
    print("\n5. Creating usage example...")
    
    usage_code = '''
# Python usage example
from transformers import AutoTokenizer
import torch

# Load model
model = SECBERTRegressor()
checkpoint = torch.load('models/secbert_russell2000_actual.pth', map_location='cpu')
model.load_state_dict(checkpoint['model_state_dict'])
model.eval()

# Load tokenizer
tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')

# Analyze text
def analyze_health(text):
    tokens = tokenizer(text, max_length=256, padding='max_length', truncation=True, return_tensors='pt')
    with torch.no_grad():
        score = model(tokens['input_ids'], tokens['attention_mask']).item() * 100
    return score

# Example
filing_text = "The company reported strong revenue growth..."
health_score = analyze_health(filing_text)
print(f"Health Score: {health_score:.1f}%")
'''
    
    with open('models/usage_example.py', 'w') as f:
        f.write(usage_code)
    
    print("   ✅ Usage example saved")
    
    print("\n" + "="*60)
    print("Conversion Complete!")
    print("="*60)
    print("\nNext steps:")
    print("1. Add SECBERTHealth.mlmodel to your Xcode project")
    print("2. Use the model with Vision or CoreML framework")
    print("3. Implement tokenization in Swift using secbert_vocab.json")
    print("="*60)

if __name__ == "__main__":
    # Install required packages if needed
    try:
        import coremltools
    except ImportError:
        print("Installing coremltools...")
        os.system("pip install coremltools")
        import coremltools
    
    convert_to_coreml()