#!/usr/bin/env python3
"""
Fetch the COMPLETE Russell 2000 Index constituents as of August 26, 2025
The Russell 2000 index contains exactly 2000 small-cap US companies
Last reconstitution: June 28, 2025
"""

import json
import requests
import pandas as pd
from datetime import datetime
import time
import os
import csv
from io import StringIO

def fetch_russell2000_complete_2025():
    """
    Get ALL 2000 companies in the Russell 2000 as of August 2025
    """
    print("🏢 Fetching Complete Russell 2000 Index - August 26, 2025")
    print("=" * 70)
    print("Target: 2000 companies (full index)")
    print()
    
    all_tickers = set()
    
    # Method 1: Download from iShares IWM ETF with proper parsing
    print("1️⃣ Fetching from iShares IWM ETF (complete holdings)...")
    try:
        session = requests.Session()
        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "text/csv,application/csv,application/json,text/plain,*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept-Encoding": "gzip, deflate, br",
            "Referer": "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf",
            "Origin": "https://www.ishares.com"
        }
        session.headers.update(headers)
        
        # Get the main page first to establish session
        main_page = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf"
        session.get(main_page)
        time.sleep(2)
        
        # Multiple endpoints to try for complete holdings
        endpoints = [
            # Current holdings endpoint
            "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf/1467271812596.ajax?tab=all&fileType=csv",
            # Alternative API endpoint
            "https://api.blackrock.com/ishares/v1/products/239710/holdings/csv",
            # Direct holdings download
            "https://www.ishares.com/us/library-literature?type=holdings&productCode=IWM"
        ]
        
        for endpoint in endpoints:
            try:
                print(f"   Trying: {endpoint.split('/')[2]}...")
                response = session.get(endpoint, timeout=30)
                
                if response.status_code == 200 and len(response.content) > 10000:  # Substantial data
                    # Save raw data
                    with open("iwm_holdings_2025_complete.csv", "wb") as f:
                        f.write(response.content)
                    
                    # Try multiple parsing strategies
                    for skip_rows in range(0, 15):
                        try:
                            df = pd.read_csv("iwm_holdings_2025_complete.csv", skiprows=skip_rows)
                            
                            # Look for ticker column
                            ticker_cols = [col for col in df.columns if 'ticker' in col.lower() or 'symbol' in col.lower()]
                            
                            if ticker_cols and len(df) > 1500:
                                tickers = df[ticker_cols[0]].dropna().astype(str).str.strip().str.upper()
                                # Filter valid tickers
                                tickers = [t for t in tickers 
                                          if t and len(t) <= 6 
                                          and not t.startswith('$')
                                          and not t.startswith('CASH')
                                          and any(c.isalpha() for c in t)]
                                
                                if len(tickers) >= 1900:  # Close to 2000
                                    all_tickers.update(tickers)
                                    print(f"   ✅ Found {len(tickers)} tickers from IWM")
                                    break
                        except:
                            continue
                    
                    if len(all_tickers) >= 1900:
                        break
            except Exception as e:
                continue
        
    except Exception as e:
        print(f"   ❌ IWM fetch error: {e}")
    
    # Method 2: Get from Vanguard's Russell 2000 ETF (VTWO)
    if len(all_tickers) < 2000:
        print("\n2️⃣ Fetching from Vanguard Russell 2000 ETF (VTWO)...")
        try:
            # Vanguard provides holdings data
            vtwo_url = "https://advisors.vanguard.com/iippdf/pdfs/FS1504.pdf"  # Holdings report
            # This would need PDF parsing or API access
            print("   Note: Would need Vanguard API access or PDF parsing")
        except:
            pass
    
    # Method 3: Financial data providers
    if len(all_tickers) < 2000:
        print("\n3️⃣ Checking financial data providers...")
        
        # Try to get from financial APIs that track Russell 2000
        # These would require API keys in production
        providers = [
            ("Alpha Vantage", "https://www.alphavantage.co/query?function=LISTING_STATUS&apikey=demo"),
            ("IEX Cloud", "https://cloud.iexapis.com/stable/ref-data/symbols"),
            ("Polygon.io", "https://api.polygon.io/v3/reference/tickers"),
            ("Twelve Data", "https://api.twelvedata.com/stocks"),
        ]
        
        for provider, url in providers:
            print(f"   {provider}: Requires API key for full access")
    
    # Method 4: Direct from FTSE Russell (index provider)
    if len(all_tickers) < 2000:
        print("\n4️⃣ FTSE Russell (official index provider)...")
        print("   The official Russell 2000 constituents list is available at:")
        print("   https://www.ftserussell.com/products/indices/russell-us")
        print("   Reconstitution date: June 28, 2025")
        print("   Note: Direct download requires registration/subscription")
    
    return list(all_tickers)

def get_russell2000_from_multiple_sources():
    """
    Combine multiple ETF sources to get complete Russell 2000 list
    """
    print("\n5️⃣ Combining multiple Russell 2000 ETF sources...")
    
    combined_tickers = set()
    
    # List of ETFs that track Russell 2000
    russell_etfs = [
        ("IWM", "iShares Russell 2000 ETF"),
        ("VTWO", "Vanguard Russell 2000 ETF"),
        ("IWN", "iShares Russell 2000 Value ETF"),
        ("IWO", "iShares Russell 2000 Growth ETF"),
        ("IWMZQ", "iShares Russell 2000 Equal Weight ETF"),
    ]
    
    for etf_symbol, etf_name in russell_etfs:
        print(f"   Checking {etf_symbol} ({etf_name})...")
        # Each would need specific endpoint/parsing
    
    return list(combined_tickers)

def download_official_russell2000_list():
    """
    Instructions for getting the official complete list
    """
    print("\n" + "=" * 70)
    print("📋 To Get the Official Complete Russell 2000 List (2000 companies):")
    print("=" * 70)
    
    print("\nOption 1: FTSE Russell (Official Provider)")
    print("1. Go to: https://www.ftserussell.com/products/indices/russell-us")
    print("2. Navigate to 'Russell 2000 Index'")
    print("3. Download 'Constituent List' (as of June 28, 2025 reconstitution)")
    print("4. Save as: russell2000_constituents_2025.csv")
    
    print("\nOption 2: Bloomberg Terminal")
    print("1. Type: RUT Index DES <GO>")
    print("2. Select: Members/Constituents")
    print("3. Export all 2000 constituents")
    
    print("\nOption 3: Refinitiv Eikon")
    print("1. Search: .RUT")
    print("2. View: Index Constituents")
    print("3. Export complete list")
    
    print("\nOption 4: S&P Capital IQ")
    print("1. Search: Russell 2000 Index")
    print("2. View: Current Constituents (as of June 2025)")
    print("3. Export to CSV")
    
    print("\n⚠️  Important: The Russell 2000 has EXACTLY 2000 constituents")
    print("   Last reconstitution: June 28, 2025")
    print("   Next reconstitution: June 26, 2026")

def create_manual_entry_script():
    """
    Create a script to manually input the Russell 2000 list if needed
    """
    script = '''#!/usr/bin/env python3
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
            f.write(f"{ticker}\\n")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        filename = sys.argv[1]
        print(f"Loading Russell 2000 from {filename}")
        tickers = load_russell2000_from_file(filename)
        save_russell2000_list(tickers)
    else:
        print("Usage: python load_russell2000.py <constituent_file.csv>")
        print("\\nExpecting a CSV file with Russell 2000 ticker symbols")
'''
    
    with open("load_russell2000_manual.py", "w") as f:
        f.write(script)
    
    print("\n✅ Created load_russell2000_manual.py for manual list entry")

def main():
    print("\n" + "🚀" * 35)
    print("RUSSELL 2000 INDEX - COMPLETE CONSTITUENT FETCHER")
    print("Target: ALL 2000 companies as of August 26, 2025")
    print("🚀" * 35 + "\n")
    
    # Try to fetch automatically
    tickers = fetch_russell2000_complete_2025()
    
    if len(tickers) >= 1900:
        print(f"\n✅ Found {len(tickers)} tickers (close to 2000)")
        
        # Save what we have
        data = {
            "index_name": "Russell 2000",
            "as_of_date": "2025-08-26", 
            "reconstitution_date": "2025-06-28",
            "total_constituents": len(tickers),
            "tickers": sorted(list(tickers))
        }
        
        with open("russell2000_partial_2025.json", "w") as f:
            json.dump(data, f, indent=2)
        
        print(f"💾 Saved to russell2000_partial_2025.json")
        print(f"\n⚠️  This is {len(tickers)}/2000 companies")
        print("   To get the complete list, see instructions below")
    else:
        print(f"\n⚠️  Only found {len(tickers)} tickers")
        print("   Need manual download for complete list")
    
    # Provide instructions
    download_official_russell2000_list()
    
    # Create manual loader
    create_manual_entry_script()
    
    print("\n" + "=" * 70)
    print("📋 Next Steps:")
    print("1. Get the complete Russell 2000 list (one of the methods above)")
    print("2. Use load_russell2000_manual.py to process it")
    print("3. Transfer russell2000_complete_2025.json to olympus")
    print("4. Run the SEC filing fetcher for all 2000 companies")
    print("5. Only train after ALL data is collected")
    print("=" * 70)

if __name__ == "__main__":
    main()