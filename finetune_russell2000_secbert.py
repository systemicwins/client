#!/usr/bin/env python3
"""
Fine-tune SEC-BERT using Russell 2000 SEC filings as gold standard
Russell 2000 companies are considered healthy benchmarks (scores 60-90)
"""

import os
import json
import torch
import torch.nn as nn
import numpy as np
from torch.utils.data import Dataset, DataLoader
from transformers import AutoTokenizer, AutoModel
from pathlib import Path
import random
from tqdm import tqdm
import logging
from datetime import datetime
import re
import glob

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
MODEL_DIR = os.path.expanduser("~/relentless/models")
CHECKPOINT_DIR = os.path.expanduser("~/relentless/checkpoints")

# Create directories
os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(CHECKPOINT_DIR, exist_ok=True)

# Training config
BATCH_SIZE = 4  # Smaller batch size for memory efficiency
LEARNING_RATE = 2e-5
EPOCHS = 3
MAX_LENGTH = 256  # Shorter for faster training
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class Russell2000Dataset(Dataset):
    """Dataset for Russell 2000 SEC filings with health scores"""
    
    def __init__(self, data_dir, tokenizer, max_length=256):
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.samples = []
        
        logger.info(f"Loading Russell 2000 SEC filings from {data_dir}")
        
        # Process each company directory
        company_dirs = [d for d in Path(data_dir).iterdir() if d.is_dir()]
        
        for company_dir in tqdm(company_dirs, desc="Loading companies"):
            ticker = company_dir.name
            if ticker in ['10-K', '10-Q', '8-K']:  # Skip filing type dirs
                continue
            
            # Load company metadata
            metadata_file = company_dir / "metadata" / "company.json"
            if not metadata_file.exists():
                continue
            
            try:
                with open(metadata_file) as f:
                    metadata = json.load(f)
                
                # Russell 2000 companies get healthy scores (60-90)
                base_score = 75
                
                # Industry-based adjustments
                sic = str(metadata.get('sic', ''))
                if sic:
                    if sic.startswith('35') or sic.startswith('73'):  # Tech
                        base_score += 5
                    elif sic.startswith('6'):  # Financial
                        base_score += 3
                    elif sic[:1] in ['2', '3']:  # Manufacturing
                        base_score += 1
                
                # Add variation
                score = base_score + random.uniform(-10, 10)
                score = max(60, min(90, score))
                
                # Get filing text
                filing_text = self._get_filing_text(company_dir)
                
                if filing_text and len(filing_text) > 100:
                    self.samples.append({
                        'ticker': ticker,
                        'text': filing_text[:1500],
                        'score': score / 100.0,
                        'name': metadata.get('name', ticker)
                    })
            except Exception as e:
                logger.debug(f"Error processing {ticker}: {e}")
                continue
        
        logger.info(f"Loaded {len(self.samples)} samples")
        
        # Add synthetic contrast samples
        self._add_synthetic_samples()
    
    def _get_filing_text(self, company_dir):
        """Extract text from SEC filings"""
        text_parts = []
        
        # Try to get latest 10-K
        for filing_type in ['10-K', '10-Q']:
            filing_dir = company_dir / filing_type
            if filing_dir.exists():
                # Get filing summaries
                summary_files = list(filing_dir.glob("*_summary.json"))
                if summary_files:
                    try:
                        with open(summary_files[0]) as f:
                            data = json.load(f)
                            # Get first 500 chars from each section
                            for section in ['item1', 'item1a', 'item7', 'item8']:
                                if section in data and data[section]:
                                    text_parts.append(data[section][:500])
                    except:
                        pass
        
        return ' '.join(text_parts) if text_parts else None
    
    def _add_synthetic_samples(self):
        """Add synthetic unhealthy examples for contrast"""
        unhealthy_texts = [
            "Going concern doubt substantial losses continuing operations uncertain",
            "Material weakness internal controls restatement required audit issues", 
            "Bankruptcy restructuring debt default covenant violation",
            "Revenue decline market share loss customer termination",
            "Litigation regulatory investigation compliance failure"
        ]
        
        # Add 15% unhealthy samples
        num_unhealthy = max(10, len(self.samples) // 7)
        for i in range(num_unhealthy):
            self.samples.append({
                'ticker': f'WEAK{i}',
                'text': random.choice(unhealthy_texts),
                'score': random.uniform(0.2, 0.4),
                'name': f'Weak Company {i}'
            })
        
        random.shuffle(self.samples)
    
    def __len__(self):
        return len(self.samples)
    
    def __getitem__(self, idx):
        sample = self.samples[idx]
        
        encoding = self.tokenizer(
            sample['text'],
            truncation=True,
            padding='max_length',
            max_length=self.max_length,
            return_tensors='pt'
        )
        
        return {
            'input_ids': encoding['input_ids'].squeeze(),
            'attention_mask': encoding['attention_mask'].squeeze(),
            'score': torch.tensor(sample['score'], dtype=torch.float32),
            'ticker': sample['ticker']
        }

class SECBERTHealthPredictor(nn.Module):
    """SEC-BERT model fine-tuned for health scores"""
    
    def __init__(self, base_model='nlpaueb/sec-bert-base'):
        super().__init__()
        self.bert = AutoModel.from_pretrained(base_model)
        
        # Freeze early layers to prevent overfitting
        for param in self.bert.embeddings.parameters():
            param.requires_grad = False
        
        # Regression head
        self.regressor = nn.Sequential(
            nn.Linear(768, 128),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(128, 1),
            nn.Sigmoid()
        )
    
    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        pooled = outputs.pooler_output
        score = self.regressor(pooled)
        return score.squeeze()

def train_model(model, train_loader, val_loader, epochs, device):
    """Train the model"""
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE)
    criterion = nn.MSELoss()
    best_val_mae = float('inf')
    
    for epoch in range(epochs):
        # Training
        model.train()
        train_losses = []
        train_preds = []
        train_targets = []
        
        for batch in tqdm(train_loader, desc=f"Epoch {epoch+1}/{epochs}"):
            input_ids = batch['input_ids'].to(device)
            attention_mask = batch['attention_mask'].to(device)
            scores = batch['score'].to(device)
            
            optimizer.zero_grad()
            outputs = model(input_ids, attention_mask)
            loss = criterion(outputs, scores)
            loss.backward()
            optimizer.step()
            
            train_losses.append(loss.item())
            train_preds.extend(outputs.detach().cpu().numpy())
            train_targets.extend(scores.cpu().numpy())
        
        # Validation
        model.eval()
        val_losses = []
        val_preds = []
        val_targets = []
        val_tickers = []
        
        with torch.no_grad():
            for batch in val_loader:
                input_ids = batch['input_ids'].to(device)
                attention_mask = batch['attention_mask'].to(device)
                scores = batch['score'].to(device)
                
                outputs = model(input_ids, attention_mask)
                loss = criterion(outputs, scores)
                
                val_losses.append(loss.item())
                val_preds.extend(outputs.cpu().numpy())
                val_targets.extend(scores.cpu().numpy())
                val_tickers.extend(batch['ticker'])
        
        # Calculate metrics
        train_mae = np.mean(np.abs(np.array(train_preds) - np.array(train_targets)))
        val_mae = np.mean(np.abs(np.array(val_preds) - np.array(val_targets)))
        
        logger.info(f"\nEpoch {epoch+1}:")
        logger.info(f"  Train Loss: {np.mean(train_losses):.4f}, MAE: {train_mae*100:.2f}%")
        logger.info(f"  Val Loss: {np.mean(val_losses):.4f}, MAE: {val_mae*100:.2f}%")
        
        # Sample predictions
        if epoch == epochs - 1 or val_mae < best_val_mae:
            logger.info("\nSample predictions:")
            for i in range(min(5, len(val_preds))):
                pred = val_preds[i] * 100
                target = val_targets[i] * 100
                logger.info(f"  {val_tickers[i]}: Pred={pred:.1f}%, Target={target:.1f}%")
        
        # Save best model
        if val_mae < best_val_mae:
            best_val_mae = val_mae
            torch.save({
                'model_state_dict': model.state_dict(),
                'val_mae': val_mae,
                'epoch': epoch
            }, os.path.join(MODEL_DIR, 'secbert_russell2000.pth'))
            logger.info(f"✅ Saved best model (MAE: {val_mae*100:.2f}%)")
    
    return best_val_mae

def main():
    logger.info(f"Starting Russell 2000 SEC-BERT fine-tuning")
    logger.info(f"Device: {DEVICE}")
    
    # Load tokenizer and dataset
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    dataset = Russell2000Dataset(DATA_DIR, tokenizer, MAX_LENGTH)
    
    if len(dataset) == 0:
        logger.error("No data loaded!")
        return
    
    # Split data
    train_size = int(0.8 * len(dataset))
    val_size = len(dataset) - train_size
    train_data, val_data = torch.utils.data.random_split(dataset, [train_size, val_size])
    
    train_loader = DataLoader(train_data, batch_size=BATCH_SIZE, shuffle=True)
    val_loader = DataLoader(val_data, batch_size=BATCH_SIZE)
    
    logger.info(f"Train: {len(train_data)} samples, Val: {len(val_data)} samples")
    
    # Train model
    model = SECBERTHealthPredictor().to(DEVICE)
    best_mae = train_model(model, train_loader, val_loader, EPOCHS, DEVICE)
    
    logger.info(f"\n{'='*60}")
    logger.info(f"Training complete! Best MAE: {best_mae*100:.2f}%")
    logger.info(f"Model saved to: {MODEL_DIR}/secbert_russell2000.pth")
    logger.info(f"{'='*60}")

if __name__ == "__main__":
    main()