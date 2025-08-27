#!/usr/bin/env python3
"""
Export SEC-BERT model to TorchScript for efficient serving
"""

import torch
import torch.nn as nn
from transformers import AutoTokenizer, AutoModel
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

def export_torchscript():
    print("="*60)
    print("Exporting SEC-BERT to TorchScript")
    print("="*60)
    
    # Load fine-tuned model
    print("\nLoading fine-tuned SEC-BERT model...")
    model = SECBERTRegressor()
    checkpoint = torch.load('models/secbert_russell2000_actual.pth', map_location='cpu', weights_only=False)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()
    
    # Test the model
    print("Testing model...")
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    test_text = "The company reported strong revenue growth and positive cash flows."
    tokens = tokenizer(test_text, max_length=256, padding='max_length', truncation=True, return_tensors='pt')
    
    with torch.no_grad():
        score = model(tokens['input_ids'], tokens['attention_mask']).item() * 100
        print(f"Test score: {score:.1f}%")
    
    # Export to TorchScript
    print("\nExporting to TorchScript...")
    example_input_ids = torch.randint(0, 1000, (1, 256))
    example_attention_mask = torch.ones(1, 256)
    
    traced_model = torch.jit.trace(model, (example_input_ids, example_attention_mask))
    
    # Save model
    output_path = 'models/secbert_health.pt'
    traced_model.save(output_path)
    print(f"✅ Saved TorchScript model to: {output_path}")
    
    # Save metadata
    metadata = {
        'model_type': 'SEC-BERT Health Analyzer',
        'training_mae': float(checkpoint.get('val_mae', 0) * 100),
        'max_length': 256,
        'vocab_size': tokenizer.vocab_size,
        'pad_token_id': int(tokenizer.pad_token_id) if tokenizer.pad_token_id is not None else 0,
        'version': '1.0.0'
    }
    
    with open('models/model_metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print("✅ Saved model metadata")
    
    # Save tokenizer vocab
    vocab = tokenizer.get_vocab()
    with open('models/vocab.json', 'w') as f:
        json.dump(vocab, f)
    print(f"✅ Saved vocabulary ({len(vocab)} tokens)")
    
    print("\n" + "="*60)
    print("Export Complete!")
    print("="*60)
    print("\nFiles created:")
    print("- models/secbert_health.pt (TorchScript model)")
    print("- models/model_metadata.json (Model configuration)")
    print("- models/vocab.json (Tokenizer vocabulary)")
    print("="*60)

if __name__ == "__main__":
    export_torchscript()