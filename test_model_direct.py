#!/usr/bin/env python3
"""
Test loading the SEC-BERT model directly to ensure it's valid
"""

import os
import coremltools as ct

def test_model():
    print("Testing SEC-BERT Model")
    print("=" * 50)
    
    # Check if model exists
    model_paths = [
        ".build/arm64-apple-macosx/debug/TradingPlatform_TradingPlatform.bundle/SECBERT.mlmodel",
        "Sources/TradingPlatform/Models/SECBERT.mlmodel",
        "SECBERT_CoreML/SECBERT.mlmodel"
    ]
    
    model_path = None
    for path in model_paths:
        if os.path.exists(path):
            model_path = path
            print(f"✅ Found model at: {path}")
            break
    
    if not model_path:
        print("❌ Model not found in any expected location")
        return
    
    # Try to load the model
    try:
        print(f"\nLoading model from: {model_path}")
        print(f"File size: {os.path.getsize(model_path) / 1024 / 1024:.1f} MB")
        
        model = ct.models.MLModel(model_path)
        print("✅ Model loaded successfully in Python")
        
        # Print model details
        print(f"\nModel Description:")
        print(f"  Author: {model.author}")
        print(f"  Description: {model.short_description}")
        
        # Check inputs
        print(f"\nInputs:")
        spec = model.get_spec()
        for input in spec.description.input:
            print(f"  - {input.name}: {input.type}")
        
        print(f"\nOutputs:")
        for output in spec.description.output:
            print(f"  - {output.name}: {output.type}")
            
    except Exception as e:
        print(f"❌ Failed to load model: {e}")
        print(f"   Error type: {type(e).__name__}")

if __name__ == "__main__":
    test_model()