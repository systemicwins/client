#!/usr/bin/env python3
"""
Fetch SEC filings for all Russell 2000 companies from the past 5 years
Uses SEC EDGAR API to download actual filing data for training
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

# SEC EDGAR API settings
SEC_API_BASE = "https://data.sec.gov"
SEC_ARCHIVES = "https://www.sec.gov/Archives"
USER_AGENT = "Mozilla/5.0 (your-email@example.com)"  # SEC requires user agent

# Import expanded Russell 2000 list
from russell2000_companies import RUSSELL_2000_FULL as RUSSELL_2000_COMPANIES

def get_company_filings(cik: str, filing_types: List[str] = ["10-K", "10-Q", "8-K"], 
                        years_back: int = 5) -> List[Dict]:
    """
    Fetch filing metadata for a company from SEC EDGAR
    
    Args:
        cik: Company CIK number (padded to 10 digits)
        filing_types: List of filing types to fetch
        years_back: Number of years of history to fetch
    """
    # Pad CIK to 10 digits
    cik_padded = cik.zfill(10)
    
    # Calculate date range
    end_date = datetime.now()
    start_date = end_date - timedelta(days=365 * years_back)
    
    filings = []
    
    try:
        # Get company submissions
        url = f"{SEC_API_BASE}/submissions/CIK{cik_padded}.json"
        headers = {"User-Agent": USER_AGENT}
        
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        
        data = response.json()
        
        # Extract recent filings
        recent_filings = data.get("filings", {}).get("recent", {})
        
        if not recent_filings:
            return filings
        
        # Process each filing
        for i in range(len(recent_filings.get("form", []))):
            form_type = recent_filings["form"][i]
            
            # Check if it's a filing type we want
            if form_type not in filing_types:
                continue
            
            # Get filing date
            filing_date = recent_filings["filingDate"][i]
            filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
            
            # Check if within date range
            if filing_dt < start_date or filing_dt > end_date:
                continue
            
            # Get accession number
            accession = recent_filings["accessionNumber"][i].replace("-", "")
            
            # Construct filing URL
            filing_url = f"{SEC_ARCHIVES}/edgar/data/{cik}/{accession}/{recent_filings['primaryDocument'][i]}"
            
            filings.append({
                "cik": cik,
                "form_type": form_type,
                "filing_date": filing_date,
                "accession_number": accession,
                "url": filing_url,
                "primary_doc": recent_filings['primaryDocument'][i]
            })
        
        # Rate limiting
        time.sleep(0.1)
        
    except Exception as e:
        print(f"Error fetching filings for CIK {cik}: {e}")
    
    return filings

def download_filing_text(filing: Dict, output_dir: str) -> Optional[str]:
    """
    Download the actual filing text content
    
    Args:
        filing: Filing metadata dictionary
        output_dir: Directory to save filing text
    """
    try:
        # Create filename
        filename = f"{filing['cik']}_{filing['form_type']}_{filing['filing_date']}.txt"
        filepath = os.path.join(output_dir, filename)
        
        # Skip if already downloaded
        if os.path.exists(filepath):
            return filepath
        
        # Download filing
        headers = {"User-Agent": USER_AGENT}
        response = requests.get(filing['url'], headers=headers)
        response.raise_for_status()
        
        # Extract text content (basic HTML stripping)
        content = response.text
        
        # Remove HTML tags (simple approach)
        import re
        text = re.sub('<[^<]+?>', '', content)
        text = re.sub(r'\s+', ' ', text)
        
        # Save to file
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(text[:500000])  # Limit to 500K chars to avoid huge files
        
        return filepath
        
    except Exception as e:
        print(f"Error downloading filing: {e}")
        return None

def fetch_all_russell2000_filings(output_dir: str = "~/relentless/finetune/data"):
    """
    Fetch SEC filings for all Russell 2000 companies
    """
    # Expand output directory
    output_dir = os.path.expanduser(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    
    # Create metadata file
    metadata_file = os.path.join(output_dir, "filings_metadata.json")
    
    print(f"🚀 Fetching SEC filings for {len(RUSSELL_2000_COMPANIES)} Russell 2000 companies")
    print(f"📁 Output directory: {output_dir}")
    
    all_filings = []
    
    # Fetch metadata for all companies
    print("\n1️⃣ Fetching filing metadata...")
    for ticker, cik in tqdm(RUSSELL_2000_COMPANIES.items(), desc="Companies"):
        filings = get_company_filings(cik)
        
        # Add ticker to each filing
        for filing in filings:
            filing['ticker'] = ticker
        
        all_filings.extend(filings)
        
        # Rate limiting
        time.sleep(0.1)
    
    print(f"\n✅ Found {len(all_filings)} total filings")
    
    # Save metadata
    with open(metadata_file, 'w') as f:
        json.dump(all_filings, f, indent=2)
    
    # Download filing texts
    print("\n2️⃣ Downloading filing texts...")
    
    # Create subdirectories by form type
    for form_type in ["10-K", "10-Q", "8-K"]:
        os.makedirs(os.path.join(output_dir, form_type), exist_ok=True)
    
    # Download with thread pool for efficiency
    downloaded = 0
    failed = 0
    
    with ThreadPoolExecutor(max_workers=5) as executor:
        # Submit download tasks
        future_to_filing = {}
        
        for filing in all_filings:
            subdir = os.path.join(output_dir, filing['form_type'])
            future = executor.submit(download_filing_text, filing, subdir)
            future_to_filing[future] = filing
        
        # Process completed downloads
        for future in tqdm(as_completed(future_to_filing), total=len(all_filings), desc="Downloading"):
            filing = future_to_filing[future]
            try:
                filepath = future.result()
                if filepath:
                    downloaded += 1
                else:
                    failed += 1
            except Exception as e:
                print(f"Download failed for {filing['ticker']} {filing['form_type']}: {e}")
                failed += 1
            
            # Rate limiting
            time.sleep(0.1)
    
    print(f"\n✅ Downloaded {downloaded} filings")
    print(f"❌ Failed: {failed} filings")
    
    # Create summary
    summary = {
        "total_companies": len(RUSSELL_2000_COMPANIES),
        "total_filings": len(all_filings),
        "downloaded": downloaded,
        "failed": failed,
        "date_range": "2019-2024",
        "filing_types": ["10-K", "10-Q", "8-K"]
    }
    
    summary_file = os.path.join(output_dir, "download_summary.json")
    with open(summary_file, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\n📊 Summary saved to {summary_file}")
    
    return all_filings

def get_full_russell2000_list():
    """
    Get the complete Russell 2000 index constituents
    Note: In production, this would fetch from a financial data provider
    """
    # This is a subset - you would need to get the full list from a data provider
    # or the Russell index website
    print("\n📋 To get the full Russell 2000 list:")
    print("1. Visit https://www.ftserussell.com/products/indices/russell-us")
    print("2. Download the Russell 2000 constituents CSV")
    print("3. Extract ticker symbols and CIKs")
    print("\nAlternatively, use a financial data API like:")
    print("- Yahoo Finance")
    print("- Alpha Vantage") 
    print("- IEX Cloud")
    print("- Polygon.io")

def main():
    """Main function to fetch all SEC filings"""
    
    print("🏢 Russell 2000 SEC Filing Fetcher")
    print("=" * 50)
    
    # Note about full list
    print(f"\n⚠️ Currently using {len(RUSSELL_2000_COMPANIES)} sample companies")
    print("For production training, expand RUSSELL_2000_COMPANIES with full index")
    
    # Fetch filings
    fetch_all_russell2000_filings()
    
    print("\n✅ Data collection complete!")
    print("\n📋 Next steps:")
    print("1. Transfer this script to olympus")
    print("2. Run on olympus to fetch all filings")
    print("3. Process filings for training data")
    print("4. Fine-tune SEC-BERT with real filing data")

if __name__ == "__main__":
    main()