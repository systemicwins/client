#!/usr/bin/env python3
"""
Manual entry point for Russell 2000 constituents
Use this if you have the official list from FTSE Russell or Bloomberg
"""

import json
import csv
from datetime import datetime

def load_russell2000_from_file(filename):
    """
    Load Russell 2000 tickers from a CSV file
    Expected format: CSV with a column containing ticker symbols
    """
    tickers = []
    
    # Try to read the CSV
    with open(filename, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        
        # Find ticker column
        ticker_col = None
        for i, header in enumerate(headers):
            if 'ticker' in header.lower() or 'symbol' in header.lower():
                ticker_col = i
                break
        
        if ticker_col is None:
            # Assume first column is ticker
            ticker_col = 0
        
        # Read all tickers
        for row in reader:
            if len(row) > ticker_col:
                ticker = row[ticker_col].strip().upper()
                if ticker and len(ticker) <= 6 and ticker.replace('-', '').replace('.', '').isalnum():
                    tickers.append(ticker)
    
    # Remove duplicates
    tickers = list(set(tickers))
    
    print(f"Loaded {len(tickers)} unique tickers")
    
    if len(tickers) < 1900 or len(tickers) > 2100:
        print(f"⚠️  Warning: Expected ~2000 tickers, got {len(tickers)}")
    
    return tickers

def save_russell2000_list(tickers):
    """
    Save the complete Russell 2000 list
    """
    data = {
        "index_name": "Russell 2000",
        "as_of_date": "2025-08-26",
        "reconstitution_date": "2025-06-28",
        "next_reconstitution": "2026-06-26",
        "total_constituents": len(tickers),
        "source": "Official FTSE Russell constituent list",
        "timestamp": datetime.now().isoformat(),
        "tickers": sorted(tickers)
    }
    
    with open("russell2000_complete_2025.json", "w") as f:
        json.dump(data, f, indent=2)
    
    print(f"✅ Saved {len(tickers)} Russell 2000 tickers to russell2000_complete_2025.json")
    
    # Also save as simple text file
    with open("russell2000_tickers_2025.txt", "w") as f:
        for ticker in sorted(tickers):
            f.write(f"{ticker}\n")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        filename = sys.argv[1]
        print(f"Loading Russell 2000 from {filename}")
        tickers = load_russell2000_from_file(filename)
        save_russell2000_list(tickers)
    else:
        print("Usage: python load_russell2000.py <constituent_file.csv>")
        print("\nExpecting a CSV file with Russell 2000 ticker symbols")
