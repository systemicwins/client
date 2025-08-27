#!/usr/bin/env python3
"""
Process downloaded SEC filings to create training data for SEC-BERT
Extracts key sections and labels with company performance metrics
"""

import json
import os
import re
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import pandas as pd
import numpy as np
from tqdm import tqdm
import yfinance as yf

def extract_filing_sections(filepath: str) -> Dict[str, str]:
    """
    Extract key sections from SEC filing text
    
    Returns dict with sections like:
    - management_discussion
    - risk_factors
    - business_overview
    - financial_data
    """
    sections = {}
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Convert to lowercase for searching
        content_lower = content.lower()
        
        # Define section patterns and their names
        section_patterns = [
            # MD&A section
            (r"item\s+7[.\s]+management['']?s?\s+discussion", "management_discussion", 20000),
            (r"management['']?s?\s+discussion\s+and\s+analysis", "management_discussion", 20000),
            
            # Risk Factors
            (r"item\s+1a[.\s]+risk\s+factors", "risk_factors", 15000),
            (r"risk\s+factors", "risk_factors", 15000),
            
            # Business Overview
            (r"item\s+1[.\s]+business", "business_overview", 15000),
            (r"business\s+overview", "business_overview", 15000),
            
            # Financial Performance
            (r"results\s+of\s+operations", "financial_performance", 10000),
            (r"financial\s+results", "financial_performance", 10000),
            
            # Executive Summary
            (r"executive\s+summary", "executive_summary", 5000),
            (r"overview", "executive_summary", 5000),
        ]
        
        # Extract each section
        for pattern, section_name, max_length in section_patterns:
            if section_name in sections:
                continue  # Skip if already found
            
            match = re.search(pattern, content_lower)
            if match:
                start_pos = match.start()
                # Extract text from this position
                section_text = content[start_pos:start_pos + max_length]
                
                # Clean up the text
                section_text = re.sub(r'\s+', ' ', section_text)  # Normalize whitespace
                section_text = re.sub(r'<[^>]+>', '', section_text)  # Remove HTML tags
                section_text = section_text.strip()
                
                if len(section_text) > 100:  # Only keep substantial sections
                    sections[section_name] = section_text
        
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
    
    return sections

def calculate_company_health_score(ticker: str, filing_date: str) -> Tuple[float, Dict]:
    """
    Calculate health score based on stock performance around filing date
    
    Returns:
        score: 0-100 health score
        metrics: Dict of performance metrics
    """
    try:
        # Get stock data
        stock = yf.Ticker(ticker)
        
        # Parse filing date
        filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
        
        # Get historical data around filing date (6 months before to 3 months after)
        start_date = filing_dt - pd.Timedelta(days=180)
        end_date = filing_dt + pd.Timedelta(days=90)
        
        hist = stock.history(start=start_date, end=end_date)
        
        if hist.empty:
            return 50.0, {}  # Default neutral score
        
        # Calculate various metrics
        metrics = {}
        
        # 1. Price performance (6 month return)
        if len(hist) > 120:
            start_price = hist['Close'].iloc[0]
            mid_price = hist['Close'].iloc[len(hist)//2]
            price_return = ((mid_price - start_price) / start_price) * 100
            metrics['price_return_6m'] = price_return
        else:
            price_return = 0
            
        # 2. Volatility (lower is better)
        volatility = hist['Close'].pct_change().std() * np.sqrt(252) * 100
        metrics['volatility'] = volatility
        
        # 3. Volume trend
        if len(hist) > 20:
            recent_vol = hist['Volume'].tail(20).mean()
            older_vol = hist['Volume'].head(20).mean()
            volume_trend = (recent_vol - older_vol) / older_vol if older_vol > 0 else 0
            metrics['volume_trend'] = volume_trend
        else:
            volume_trend = 0
        
        # 4. Get company info
        info = stock.info
        market_cap = info.get('marketCap', 0)
        metrics['market_cap'] = market_cap
        
        # Calculate health score (0-100)
        score = 50.0  # Base score
        
        # Price performance contribution
        if price_return > 50:
            score += 20
        elif price_return > 20:
            score += 15
        elif price_return > 0:
            score += 10
        elif price_return > -10:
            score += 5
        else:
            score -= 10
        
        # Volatility contribution (lower is better)
        if volatility < 20:
            score += 10
        elif volatility < 30:
            score += 5
        elif volatility > 50:
            score -= 10
        
        # Volume trend contribution
        if volume_trend > 0.5:
            score += 5
        elif volume_trend > 0:
            score += 2
        
        # Market cap contribution
        if market_cap > 10_000_000_000:  # >$10B
            score += 15
        elif market_cap > 2_000_000_000:  # >$2B (Russell 2000 range)
            score += 10
        elif market_cap > 500_000_000:  # >$500M
            score += 5
        
        # Clamp score to 0-100
        score = max(0, min(100, score))
        
        return score, metrics
        
    except Exception as e:
        print(f"Error calculating score for {ticker}: {e}")
        return 50.0, {}  # Default neutral score

def process_filings_to_training_data(data_dir: str = "~/relentless/finetune/data"):
    """
    Process all downloaded SEC filings into training data
    """
    data_dir = os.path.expanduser(data_dir)
    
    # Load metadata
    metadata_file = os.path.join(data_dir, "filings_metadata.json")
    if not os.path.exists(metadata_file):
        print("❌ Metadata file not found. Run fetch_russell2000_sec_filings.py first.")
        return
    
    with open(metadata_file, 'r') as f:
        filings_metadata = json.load(f)
    
    print(f"📋 Processing {len(filings_metadata)} filings...")
    
    training_samples = []
    
    # Process each filing
    for filing in tqdm(filings_metadata, desc="Processing filings"):
        ticker = filing['ticker']
        form_type = filing['form_type']
        filing_date = filing['filing_date']
        
        # Construct filepath
        filename = f"{filing['cik']}_{form_type}_{filing_date}.txt"
        filepath = os.path.join(data_dir, form_type, filename)
        
        if not os.path.exists(filepath):
            continue
        
        # Extract sections
        sections = extract_filing_sections(filepath)
        
        if not sections:
            continue
        
        # Calculate health score
        health_score, metrics = calculate_company_health_score(ticker, filing_date)
        
        # Create training samples from each section
        for section_name, section_text in sections.items():
            # Split into chunks of ~2000 characters
            chunk_size = 2000
            for i in range(0, len(section_text), chunk_size):
                chunk = section_text[i:i+chunk_size]
                
                if len(chunk) < 100:
                    continue
                
                sample = {
                    "ticker": ticker,
                    "filing_type": form_type,
                    "filing_date": filing_date,
                    "section": section_name,
                    "text": chunk,
                    "health_score": health_score,
                    "metrics": metrics
                }
                
                training_samples.append(sample)
    
    print(f"\n✅ Created {len(training_samples)} training samples")
    
    # Save training data
    output_file = os.path.join(data_dir, "sec_filings_training_data.json")
    with open(output_file, 'w') as f:
        json.dump(training_samples, f, indent=2)
    
    print(f"💾 Saved training data to {output_file}")
    
    # Create summary statistics
    if training_samples:
        df = pd.DataFrame(training_samples)
        
        print("\n📊 Training Data Summary:")
        print(f"   Total samples: {len(df)}")
        print(f"   Unique companies: {df['ticker'].nunique()}")
        print(f"   Filing types: {df['filing_type'].value_counts().to_dict()}")
        print(f"   Health score range: {df['health_score'].min():.1f} - {df['health_score'].max():.1f}")
        print(f"   Mean health score: {df['health_score'].mean():.1f}")
        
        # Section distribution
        print(f"\n   Sections extracted:")
        for section, count in df['section'].value_counts().items():
            print(f"     - {section}: {count} samples")

def create_balanced_training_set(training_file: str):
    """
    Create a balanced training set with equal representation across score ranges
    """
    with open(training_file, 'r') as f:
        data = json.load(f)
    
    df = pd.DataFrame(data)
    
    # Define score bins
    bins = [0, 25, 40, 55, 70, 85, 100]
    labels = ['poor', 'weak', 'fair', 'good', 'strong', 'excellent']
    
    df['score_category'] = pd.cut(df['health_score'], bins=bins, labels=labels)
    
    # Sample equally from each category
    min_samples = df['score_category'].value_counts().min()
    
    balanced_samples = []
    for category in labels:
        category_samples = df[df['score_category'] == category]
        if len(category_samples) > 0:
            sampled = category_samples.sample(n=min(min_samples, len(category_samples)), random_state=42)
            balanced_samples.append(sampled)
    
    balanced_df = pd.concat(balanced_samples)
    balanced_df = balanced_df.sample(frac=1, random_state=42).reset_index(drop=True)  # Shuffle
    
    # Save balanced dataset
    balanced_data = balanced_df.drop('score_category', axis=1).to_dict('records')
    
    output_file = training_file.replace('.json', '_balanced.json')
    with open(output_file, 'w') as f:
        json.dump(balanced_data, f, indent=2)
    
    print(f"\n✅ Created balanced dataset with {len(balanced_data)} samples")
    print(f"💾 Saved to {output_file}")

def main():
    """Main processing pipeline"""
    
    print("🔄 SEC Filings Training Data Processor")
    print("=" * 50)
    
    # Process filings
    process_filings_to_training_data()
    
    # Create balanced dataset
    training_file = os.path.expanduser("~/relentless/finetune/data/sec_filings_training_data.json")
    if os.path.exists(training_file):
        create_balanced_training_set(training_file)
    
    print("\n✅ Processing complete!")
    print("\n📋 Next steps:")
    print("1. Review the training data")
    print("2. Fine-tune SEC-BERT with the processed data")
    print("3. Evaluate model performance")

if __name__ == "__main__":
    main()