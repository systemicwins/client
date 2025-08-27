#!/usr/bin/env python3
"""
Fine-tune SEC-BERT on Russell 2000 SEC filings with health scores (0-100%)
Optimized for olympus host with AMD GPU support
"""

import json
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from transformers import AutoTokenizer, AutoModel
from torch.optim import AdamW
from sklearn.model_selection import train_test_split
import numpy as np
from tqdm import tqdm
from typing import List, Tuple, Dict
import os
import sys

# Check for AMD GPU with ROCm
def check_gpu_availability():
    """Check for GPU availability (CUDA or ROCm)"""
    if torch.cuda.is_available():
        device_name = torch.cuda.get_device_name(0)
        print(f"✅ GPU detected: {device_name}")
        print(f"   Device count: {torch.cuda.device_count()}")
        print(f"   Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
        return torch.device('cuda')
    else:
        # Try to detect ROCm/HIP
        try:
            # Set environment variables for AMD GPU
            os.environ['HSA_OVERRIDE_GFX_VERSION'] = '11.0.0'
            os.environ['HIP_VISIBLE_DEVICES'] = '0'
            os.environ['ROCR_VISIBLE_DEVICES'] = '0'
            
            # Check if ROCm is available via environment
            if 'ROCM_PATH' in os.environ:
                print(f"🔧 ROCm detected at: {os.environ['ROCM_PATH']}")
            
            # For AMD GPUs, PyTorch still uses 'cuda' interface
            if hasattr(torch.version, 'hip') and torch.version.hip is not None:
                print(f"✅ HIP/ROCm version: {torch.version.hip}")
                return torch.device('cuda')
        except Exception as e:
            print(f"⚠️ ROCm detection: {e}")
        
        print("⚠️ No GPU detected. Using CPU (training will be slower)")
        print("   For AMD GPU: ensure ROCm and PyTorch-ROCm are properly installed")
        return torch.device('cpu')

# Known company health scores based on performance
COMPANY_HEALTH_SCORES = {
    # Russell 2000 Top Performers (70-95%)
    "SMCI": 85,  # Super Micro Computer - tech leader
    "COHR": 80,  # Coherent Corp
    "RMBS": 75,  # Rambus
    "INSM": 82,  # Insmed - healthcare leader
    "KRYS": 85,  # Krystal Biotech
    "TALO": 78,  # Talos Energy - energy leader
    "SM": 75,   # SM Energy
    "WING": 88,  # Wingstop - consumer leader
    "TXRH": 85,  # Texas Roadhouse
    "SHAK": 80,  # Shake Shack
    
    # Russell 2000 Average Performers (50-70%)
    "AAON": 65,  # AAON Inc - industrial
    "TREX": 68,  # Trex Company
    "FFIN": 60,  # First Financial
    "GBCI": 62,  # Glacier Bancorp
    
    # FAANG+ Mega-caps for reference (85-95%)
    "AAPL": 92,
    "MSFT": 90,
    "GOOGL": 88,
    "AMZN": 87,
    "META": 85,
    "NVDA": 93,
    "TSM": 89,
}

class SECFilingDataset(Dataset):
    """Dataset for SEC filing texts with health scores"""
    
    def __init__(self, texts: List[str], scores: List[float], tokenizer, max_length=512):
        self.texts = texts
        self.scores = scores
        self.tokenizer = tokenizer
        self.max_length = max_length
    
    def __len__(self):
        return len(self.texts)
    
    def __getitem__(self, idx):
        text = self.texts[idx]
        score = self.scores[idx]
        
        # Tokenize text
        encoding = self.tokenizer(
            text,
            truncation=True,
            padding='max_length',
            max_length=self.max_length,
            return_tensors='pt'
        )
        
        return {
            'input_ids': encoding['input_ids'].squeeze(),
            'attention_mask': encoding['attention_mask'].squeeze(),
            'score': torch.tensor(score / 100.0, dtype=torch.float)  # Normalize to 0-1
        }

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

def load_training_data():
    """Load training data from file if exists, otherwise generate"""
    
    # Check if pre-generated training data exists
    if os.path.exists('russell2000_training_data.json'):
        print("📂 Loading existing training data...")
        with open('russell2000_training_data.json', 'r') as f:
            data = json.load(f)
        print(f"   Loaded {len(data)} samples")
        return data
    
    print("🔄 Generating training data...")
    training_data = []
    
    # Sample training data structure
    sample_patterns = {
        "excellent": [
            "We achieved record revenue of {amount} billion, representing {pct}% year-over-year growth. "
            "Operating margins expanded by {bp} basis points, demonstrating strong operational leverage.",
            
            "The company delivered outstanding financial performance with revenue growth accelerating to {pct}%. "
            "We maintained industry-leading margins while investing heavily in R&D and innovation.",
        ],
        
        "strong": [
            "Revenue increased {pct}% year-over-year driven by strong demand across our product portfolio. "
            "We achieved positive EBITDA and are on track to reach our profitability targets.",
            
            "We delivered solid financial results with {pct}% revenue growth and expanding gross margins. "
            "Customer retention remains strong with net revenue retention exceeding {nrr}%.",
        ],
        
        "fair": [
            "Revenue remained relatively flat compared to the prior year period. "
            "We are focused on cost optimization to maintain profitability in a challenging environment.",
            
            "Financial performance was mixed with revenue growth of {pct}% offset by margin pressure. "
            "We are implementing restructuring initiatives to improve operational efficiency.",
        ],
        
        "weak": [
            "Revenue declined {pct}% year-over-year due to weakening demand and increased competition. "
            "The company reported an operating loss as we work to restructure operations.",
            
            "We experienced significant challenges with revenue decreasing {pct}% and widening losses. "
            "Cash burn remains elevated and we may need to raise additional capital.",
        ]
    }
    
    # Generate training samples
    import random
    
    for symbol, base_score in COMPANY_HEALTH_SCORES.items():
        # Determine pattern category
        if base_score >= 80:
            patterns = sample_patterns["excellent"]
            score_range = (80, 95)
        elif base_score >= 65:
            patterns = sample_patterns["strong"]
            score_range = (65, 80)
        elif base_score >= 45:
            patterns = sample_patterns["fair"]
            score_range = (45, 65)
        else:
            patterns = sample_patterns["weak"]
            score_range = (20, 45)
        
        # Generate variations
        for _ in range(10):  # 10 samples per company
            pattern = random.choice(patterns)
            
            # Fill in random values
            text = pattern.format(
                amount=random.randint(10, 200),
                pct=random.randint(5, 50),
                bp=random.randint(50, 500),
                nrr=random.randint(100, 130)
            )
            
            # Add some noise to the score
            score = base_score + random.uniform(-5, 5)
            score = max(0, min(100, score))  # Clamp to 0-100
            
            training_data.append({
                "text": text,
                "score": score,
                "symbol": symbol
            })
    
    # Save generated data
    with open('russell2000_training_data.json', 'w') as f:
        json.dump(training_data, f, indent=2)
    
    return training_data

def fine_tune_model(training_data: List[Dict], num_epochs=3, batch_size=8, learning_rate=2e-5):
    """Fine-tune SEC-BERT on health score prediction"""
    
    print("\n🔄 Initializing SEC-BERT for fine-tuning...")
    
    # Check device availability
    device = check_gpu_availability()
    
    # Initialize tokenizer and model
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    model = SECBERTHealthPredictor()
    
    # Prepare data
    texts = [item['text'] for item in training_data]
    scores = [item['score'] for item in training_data]
    
    # Split into train/validation
    train_texts, val_texts, train_scores, val_scores = train_test_split(
        texts, scores, test_size=0.2, random_state=42
    )
    
    # Create datasets
    train_dataset = SECFilingDataset(train_texts, train_scores, tokenizer)
    val_dataset = SECFilingDataset(val_texts, val_scores, tokenizer)
    
    # Create data loaders (smaller batch size for CPU)
    if device.type == 'cpu':
        batch_size = min(batch_size, 4)  # Reduce batch size for CPU
        print(f"📊 Using batch size: {batch_size} (optimized for CPU)")
    
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size)
    
    # Setup optimization
    optimizer = AdamW(model.parameters(), lr=learning_rate)
    criterion = nn.MSELoss()  # Mean squared error for regression
    
    # Move model to device
    model.to(device)
    
    print(f"📊 Training on {len(train_dataset)} samples, validating on {len(val_dataset)} samples")
    print(f"🖥️  Using device: {device}")
    
    # Training loop
    best_val_loss = float('inf')
    
    for epoch in range(num_epochs):
        # Training
        model.train()
        train_loss = 0
        train_progress = tqdm(train_loader, desc=f'Epoch {epoch+1}/{num_epochs} - Training')
        
        for batch in train_progress:
            input_ids = batch['input_ids'].to(device)
            attention_mask = batch['attention_mask'].to(device)
            targets = batch['score'].to(device)
            
            optimizer.zero_grad()
            outputs = model(input_ids, attention_mask)
            loss = criterion(outputs, targets)
            loss.backward()
            optimizer.step()
            
            train_loss += loss.item()
            train_progress.set_postfix({'loss': loss.item()})
        
        avg_train_loss = train_loss / len(train_loader)
        
        # Validation
        model.eval()
        val_loss = 0
        predictions = []
        actuals = []
        
        with torch.no_grad():
            for batch in tqdm(val_loader, desc='Validation'):
                input_ids = batch['input_ids'].to(device)
                attention_mask = batch['attention_mask'].to(device)
                targets = batch['score'].to(device)
                
                outputs = model(input_ids, attention_mask)
                loss = criterion(outputs, targets)
                val_loss += loss.item()
                
                predictions.extend(outputs.cpu().numpy() * 100)  # Convert back to 0-100
                actuals.extend(targets.cpu().numpy() * 100)
        
        avg_val_loss = val_loss / len(val_loader)
        
        # Calculate metrics
        predictions = np.array(predictions)
        actuals = np.array(actuals)
        mae = np.mean(np.abs(predictions - actuals))
        
        print(f"📈 Epoch {epoch+1}: Train Loss: {avg_train_loss:.4f}, Val Loss: {avg_val_loss:.4f}, MAE: {mae:.2f}%")
        
        # Save best model
        if avg_val_loss < best_val_loss:
            best_val_loss = avg_val_loss
            torch.save({
                'model_state_dict': model.state_dict(),
                'tokenizer_name': 'nlpaueb/sec-bert-base',
                'epoch': epoch,
                'val_loss': avg_val_loss,
                'mae': mae
            }, 'secbert_russell2000_best.pt')
            print(f"   💾 Saved best model (MAE: {mae:.2f}%)")
    
    return model, tokenizer

def save_model_for_transfer(model, tokenizer):
    """Save model in format ready for transfer back to local machine"""
    
    print("\n💾 Saving model for transfer...")
    
    # Save PyTorch model
    torch.save({
        'model_state_dict': model.state_dict(),
        'model_config': {
            'base_model': 'nlpaueb/sec-bert-base',
            'architecture': 'SECBERTHealthPredictor'
        }
    }, 'secbert_health_final.pt')
    
    # Save tokenizer vocabulary
    vocab = tokenizer.get_vocab()
    with open('secbert_health_vocab.json', 'w') as f:
        json.dump(vocab, f, indent=2)
    
    # Save special tokens
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
    
    with open('secbert_health_special_tokens.json', 'w') as f:
        json.dump(special_tokens, f, indent=2)
    
    print("✅ Model saved. Files ready for transfer:")
    print("   - secbert_health_final.pt (PyTorch model)")
    print("   - secbert_health_vocab.json (tokenizer vocabulary)")
    print("   - secbert_health_special_tokens.json (special tokens)")
    print("\n📋 Next step: Transfer files back to local machine for CoreML conversion")

def main():
    """Main fine-tuning pipeline"""
    
    print("🚀 SEC-BERT Russell 2000 Fine-tuning Pipeline (Olympus)")
    print("=" * 55)
    
    # Step 1: Load training data
    print("\n1️⃣ Loading training data...")
    training_data = load_training_data()
    print(f"   Loaded {len(training_data)} training samples")
    
    # Step 2: Fine-tune model
    print("\n2️⃣ Fine-tuning SEC-BERT...")
    model, tokenizer = fine_tune_model(
        training_data, 
        num_epochs=3,
        batch_size=8,  # Smaller batch size for stability
        learning_rate=2e-5
    )
    
    # Step 3: Save model for transfer
    save_model_for_transfer(model, tokenizer)
    
    print("\n✅ Fine-tuning complete!")
    print("\n📋 To complete the process:")
    print("1. Transfer model files back to local machine")
    print("2. Run CoreML conversion on macOS")
    print("3. Deploy to TradingPlatform app")

if __name__ == "__main__":
    main()