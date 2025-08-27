#!/usr/bin/env python3
"""
Train SEC-BERT on actual Russell 2000 SEC filing text
Uses downloaded 10-K, 10-Q, 8-K filings as training data
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

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
MODEL_DIR = os.path.expanduser("~/relentless/models")
CHECKPOINT_DIR = os.path.expanduser("~/relentless/checkpoints")

# Create directories
os.makedirs(MODEL_DIR, exist_ok=True)
os.makedirs(CHECKPOINT_DIR, exist_ok=True)

# Training config
BATCH_SIZE = 4
LEARNING_RATE = 2e-5
EPOCHS = 5
MAX_LENGTH = 384  # Balanced for memory and context
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class ActualFilingsDataset(Dataset):
    """Dataset for actual Russell 2000 SEC filings"""
    
    def __init__(self, data_dir, tokenizer, max_length=384, max_samples_per_company=3):
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.samples = []
        
        logger.info(f"Loading actual SEC filings from {data_dir}")
        
        # Load filings from each company
        company_dirs = [d for d in Path(data_dir).iterdir() 
                       if d.is_dir() and d.name not in ['10-K', '10-Q', '8-K', 'metadata']]
        
        companies_with_filings = 0
        total_filings = 0
        
        for company_dir in tqdm(company_dirs[:500], desc="Loading companies"):  # Limit for memory
            ticker = company_dir.name
            company_filings = []
            
            # Load 10-K filings (most important)
            for filing_type in ['10-K', '10-Q']:
                filing_dir = company_dir / filing_type
                if filing_dir.exists():
                    filing_files = list(filing_dir.glob("*.json"))[:max_samples_per_company]
                    
                    for filing_file in filing_files:
                        try:
                            with open(filing_file) as f:
                                filing_data = json.load(f)
                            
                            # Extract text from sections
                            sections = filing_data.get('sections', {})
                            text_parts = []
                            
                            # Priority sections for health assessment
                            priority_sections = ['business', 'risk_factors', 'mda', 'financial_statements']
                            for section in priority_sections:
                                if section in sections and sections[section]:
                                    # Clean and limit section text
                                    section_text = sections[section]
                                    section_text = ' '.join(section_text.split())[:1000]
                                    if len(section_text) > 50:
                                        text_parts.append(section_text)
                            
                            # If no priority sections, use full_text
                            if not text_parts and 'full_text' in sections:
                                text_parts.append(sections['full_text'][:2000])
                            
                            if text_parts:
                                filing_text = ' '.join(text_parts)[:2500]
                                
                                # Assign score based on Russell 2000 membership
                                # Russell 2000 companies are healthy benchmarks
                                base_score = 75
                                
                                # Adjust based on filing type and recency
                                if filing_type == '10-K':
                                    base_score += 2  # Annual reports are comprehensive
                                
                                # Add some variation
                                score = base_score + random.uniform(-8, 8)
                                score = max(60, min(88, score))  # Clamp to healthy range
                                
                                company_filings.append({
                                    'ticker': ticker,
                                    'text': filing_text,
                                    'score': score / 100.0,
                                    'filing_type': filing_type,
                                    'filing_date': filing_data.get('filing_date', '')
                                })
                                total_filings += 1
                                
                        except Exception as e:
                            logger.debug(f"Error loading {filing_file}: {e}")
                            continue
            
            if company_filings:
                # Add best filings from this company
                company_filings.sort(key=lambda x: x['filing_date'], reverse=True)
                self.samples.extend(company_filings[:max_samples_per_company])
                companies_with_filings += 1
        
        logger.info(f"Loaded {len(self.samples)} samples from {companies_with_filings} companies")
        logger.info(f"Total filings processed: {total_filings}")
        
        # Add synthetic unhealthy examples for contrast
        self._add_synthetic_unhealthy()
        
        # Shuffle all samples
        random.shuffle(self.samples)
    
    def _add_synthetic_unhealthy(self):
        """Add synthetic unhealthy company examples"""
        unhealthy_patterns = [
            "The company has experienced substantial losses and negative cash flows from operations. "
            "Our independent auditors have expressed substantial doubt about our ability to continue as a going concern. "
            "We have limited financial resources and will need to raise additional capital.",
            
            "We face intense competition and have been losing significant market share. "
            "Revenue has declined by over 40% year-over-year. Customer retention rates have fallen below industry standards. "
            "Several major customers have terminated their contracts.",
            
            "We are subject to multiple class action lawsuits and regulatory investigations. "
            "The company has identified material weaknesses in internal control over financial reporting. "
            "We may be required to restate prior period financial statements.",
            
            "Our debt-to-equity ratio has deteriorated significantly. "
            "We are in violation of certain debt covenants and our lenders may accelerate repayment. "
            "Management is exploring strategic alternatives including restructuring or bankruptcy protection.",
            
            "We have experienced significant cybersecurity incidents resulting in data breaches. "
            "Product recalls have materially impacted our operations and reputation. "
            "Key members of our management team have resigned and we face challenges attracting qualified personnel."
        ]
        
        # Add synthetic samples (20% of real samples)
        num_synthetic = max(20, len(self.samples) // 5)
        
        for i in range(num_synthetic):
            # Combine multiple patterns for variety
            num_patterns = random.randint(1, 3)
            selected_patterns = random.sample(unhealthy_patterns, num_patterns)
            text = ' '.join(selected_patterns)
            
            # Unhealthy scores
            score = random.uniform(0.20, 0.45)
            
            self.samples.append({
                'ticker': f'SYNTH_UNHEALTHY_{i}',
                'text': text,
                'score': score,
                'filing_type': 'synthetic',
                'filing_date': '2024-01-01'
            })
        
        logger.info(f"Added {num_synthetic} synthetic unhealthy samples")
        logger.info(f"Total dataset size: {len(self.samples)} samples")
    
    def __len__(self):
        return len(self.samples)
    
    def __getitem__(self, idx):
        sample = self.samples[idx]
        
        # Tokenize text
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

class SECBERTRegressor(nn.Module):
    """SEC-BERT model for health score regression"""
    
    def __init__(self, model_name='nlpaueb/sec-bert-base', freeze_base=True):
        super().__init__()
        self.bert = AutoModel.from_pretrained(model_name)
        
        # Optionally freeze base model layers
        if freeze_base:
            for param in self.bert.embeddings.parameters():
                param.requires_grad = False
            # Keep last 2 encoder layers trainable
            for layer in self.bert.encoder.layer[:-2]:
                for param in layer.parameters():
                    param.requires_grad = False
        
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
            nn.Sigmoid()  # Output 0-1 score
        )
    
    def forward(self, input_ids, attention_mask):
        outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
        pooled_output = outputs.pooler_output
        pooled_output = self.dropout(pooled_output)
        score = self.regressor(pooled_output)
        return score.squeeze()

def train_epoch(model, dataloader, optimizer, criterion, device):
    """Train for one epoch"""
    model.train()
    total_loss = 0
    all_preds = []
    all_targets = []
    
    progress_bar = tqdm(dataloader, desc="Training")
    for batch in progress_bar:
        input_ids = batch['input_ids'].to(device)
        attention_mask = batch['attention_mask'].to(device)
        scores = batch['score'].to(device)
        
        optimizer.zero_grad()
        
        # Forward pass
        outputs = model(input_ids, attention_mask)
        loss = criterion(outputs, scores)
        
        # Backward pass
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        
        total_loss += loss.item()
        # Handle single value outputs
        if outputs.dim() == 0:
            all_preds.append(outputs.detach().cpu().item())
        else:
            all_preds.extend(outputs.detach().cpu().numpy())
        
        if scores.dim() == 0:
            all_targets.append(scores.cpu().item())
        else:
            all_targets.extend(scores.cpu().numpy())
        
        # Update progress bar
        progress_bar.set_postfix({'loss': loss.item()})
    
    # Calculate metrics
    all_preds = np.array(all_preds)
    all_targets = np.array(all_targets)
    mae = np.mean(np.abs(all_preds - all_targets))
    
    return total_loss / len(dataloader), mae

def evaluate(model, dataloader, criterion, device):
    """Evaluate model"""
    model.eval()
    total_loss = 0
    all_preds = []
    all_targets = []
    all_tickers = []
    
    with torch.no_grad():
        for batch in tqdm(dataloader, desc="Evaluating"):
            input_ids = batch['input_ids'].to(device)
            attention_mask = batch['attention_mask'].to(device)
            scores = batch['score'].to(device)
            
            outputs = model(input_ids, attention_mask)
            loss = criterion(outputs, scores)
            
            total_loss += loss.item()
            # Handle single value outputs
            if outputs.dim() == 0:
                all_preds.append(outputs.cpu().item())
            else:
                all_preds.extend(outputs.cpu().numpy())
            
            if scores.dim() == 0:
                all_targets.append(scores.cpu().item())
            else:
                all_targets.extend(scores.cpu().numpy())
            
            all_tickers.extend(batch['ticker'])
    
    # Calculate metrics
    all_preds = np.array(all_preds)
    all_targets = np.array(all_targets)
    mae = np.mean(np.abs(all_preds - all_targets))
    
    # Sample predictions
    logger.info("\nSample predictions:")
    indices = random.sample(range(len(all_preds)), min(10, len(all_preds)))
    for idx in indices:
        pred_pct = all_preds[idx] * 100
        target_pct = all_targets[idx] * 100
        ticker = all_tickers[idx]
        logger.info(f"  {ticker}: Predicted={pred_pct:.1f}%, Target={target_pct:.1f}%")
    
    return total_loss / len(dataloader), mae

def main():
    logger.info("="*70)
    logger.info("SEC-BERT Training on Actual Russell 2000 Filings")
    logger.info("="*70)
    logger.info(f"Device: {DEVICE}")
    
    # Initialize tokenizer and model
    tokenizer = AutoTokenizer.from_pretrained('nlpaueb/sec-bert-base')
    
    # Load dataset
    dataset = ActualFilingsDataset(DATA_DIR, tokenizer, MAX_LENGTH)
    
    if len(dataset) == 0:
        logger.error("No data loaded!")
        return
    
    # Split dataset
    train_size = int(0.8 * len(dataset))
    val_size = len(dataset) - train_size
    train_dataset, val_dataset = torch.utils.data.random_split(
        dataset, [train_size, val_size]
    )
    
    logger.info(f"Train samples: {len(train_dataset)}, Val samples: {len(val_dataset)}")
    
    # Create dataloaders
    train_loader = DataLoader(
        train_dataset, batch_size=BATCH_SIZE, shuffle=True, num_workers=0
    )
    val_loader = DataLoader(
        val_dataset, batch_size=BATCH_SIZE, shuffle=False, num_workers=0
    )
    
    # Initialize model
    model = SECBERTRegressor(freeze_base=True).to(DEVICE)
    
    # Optimizer and loss
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=0.01)
    criterion = nn.MSELoss()
    
    # Learning rate scheduler
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode='min', factor=0.5, patience=2
    )
    
    # Training loop
    best_val_mae = float('inf')
    
    for epoch in range(EPOCHS):
        logger.info(f"\n{'='*60}")
        logger.info(f"Epoch {epoch+1}/{EPOCHS}")
        logger.info(f"{'='*60}")
        
        # Train
        train_loss, train_mae = train_epoch(model, train_loader, optimizer, criterion, DEVICE)
        logger.info(f"Train Loss: {train_loss:.4f}, Train MAE: {train_mae*100:.2f}%")
        
        # Evaluate
        val_loss, val_mae = evaluate(model, val_loader, criterion, DEVICE)
        logger.info(f"Val Loss: {val_loss:.4f}, Val MAE: {val_mae*100:.2f}%")
        
        # Learning rate scheduling
        scheduler.step(val_mae)
        
        # Save best model
        if val_mae < best_val_mae:
            best_val_mae = val_mae
            model_path = os.path.join(MODEL_DIR, 'secbert_russell2000_actual.pth')
            torch.save({
                'epoch': epoch,
                'model_state_dict': model.state_dict(),
                'optimizer_state_dict': optimizer.state_dict(),
                'val_mae': val_mae,
                'train_mae': train_mae
            }, model_path)
            logger.info(f"✅ Saved best model with VAL MAE: {val_mae*100:.2f}%")
        
        # Save checkpoint
        checkpoint_path = os.path.join(CHECKPOINT_DIR, f'actual_epoch_{epoch+1}.pth')
        torch.save({
            'epoch': epoch,
            'model_state_dict': model.state_dict(),
            'optimizer_state_dict': optimizer.state_dict(),
            'val_mae': val_mae
        }, checkpoint_path)
    
    logger.info(f"\n{'='*60}")
    logger.info(f"Training Complete!")
    logger.info(f"Best VAL MAE: {best_val_mae*100:.2f}%")
    logger.info(f"Model saved to: {MODEL_DIR}/secbert_russell2000_actual.pth")
    logger.info(f"{'='*60}")

if __name__ == "__main__":
    main()