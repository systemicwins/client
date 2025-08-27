#!/usr/bin/env python3
"""
Robust SEC filing fetcher with proper rate limiting and caching
Fetches actual SEC filings for Russell 2000 companies for training
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
import pandas as pd
from tqdm import tqdm
import hashlib
from russell2000_companies import RUSSELL_2000_FULL

# SEC EDGAR API settings with proper headers
SEC_API_BASE = "https://data.sec.gov"
SEC_ARCHIVES = "https://www.sec.gov/Archives"

# IMPORTANT: SEC requires a valid user agent with contact info
USER_AGENT = "Academic Research Bot contact@example.com"  # Update with your email

# Rate limiting settings (SEC allows 10 requests per second)
REQUESTS_PER_SECOND = 2  # Conservative rate to avoid 429 errors
REQUEST_DELAY = 1.0 / REQUESTS_PER_SECOND

class SECFilingFetcher:
    def __init__(self, output_dir="~/relentless/finetune/data"):
        self.output_dir = os.path.expanduser(output_dir)
        os.makedirs(self.output_dir, exist_ok=True)
        
        # Create subdirectories
        for form_type in ["10-K", "10-Q", "8-K", "metadata"]:
            os.makedirs(os.path.join(self.output_dir, form_type), exist_ok=True)
        
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate",
            "Host": "data.sec.gov"
        })
        
        self.last_request_time = 0
        self.metadata_cache = {}
        
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request_time
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request_time = time.time()
    
    def get_company_metadata(self, ticker, cik):
        """Get company filing metadata with caching"""
        cache_file = os.path.join(self.output_dir, "metadata", f"{ticker}_{cik}.json")
        
        # Check cache first
        if os.path.exists(cache_file):
            with open(cache_file, 'r') as f:
                return json.load(f)
        
        # Pad CIK to 10 digits
        cik_padded = cik.zfill(10)
        
        try:
            self.rate_limit()
            
            # Get company submissions
            url = f"{SEC_API_BASE}/submissions/CIK{cik_padded}.json"
            response = self.session.get(url, timeout=30)
            
            if response.status_code == 404:
                print(f"  ⚠️ CIK not found: {ticker} ({cik})")
                return None
            
            response.raise_for_status()
            data = response.json()
            
            # Cache the metadata
            with open(cache_file, 'w') as f:
                json.dump(data, f)
            
            return data
            
        except requests.exceptions.RequestException as e:
            print(f"  ❌ Error fetching {ticker}: {e}")
            return None
    
    def extract_filings(self, metadata, ticker, cik, filing_types=["10-K", "10-Q", "8-K"], years_back=5):
        """Extract relevant filings from metadata"""
        if not metadata:
            return []
        
        filings = []
        end_date = datetime.now()
        start_date = end_date - timedelta(days=365 * years_back)
        
        recent = metadata.get("filings", {}).get("recent", {})
        if not recent:
            return filings
        
        # Process each filing
        for i in range(len(recent.get("form", []))):
            form_type = recent["form"][i]
            
            if form_type not in filing_types:
                continue
            
            filing_date = recent["filingDate"][i]
            filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
            
            if filing_dt < start_date or filing_dt > end_date:
                continue
            
            accession = recent["accessionNumber"][i].replace("-", "")
            
            # Build document URL
            primary_doc = recent.get("primaryDocument", [None])[i]
            if primary_doc:
                doc_url = f"{SEC_ARCHIVES}/edgar/data/{cik}/{accession}/{primary_doc}"
            else:
                # Use HTML version
                doc_url = f"{SEC_ARCHIVES}/edgar/data/{cik}/{accession}/{recent['accessionNumber'][i]}.txt"
            
            filings.append({
                "ticker": ticker,
                "cik": cik,
                "form_type": form_type,
                "filing_date": filing_date,
                "accession_number": accession,
                "url": doc_url
            })
        
        return filings
    
    def download_filing_text(self, filing):
        """Download filing text with caching and retry logic"""
        # Create filename
        filename = f"{filing['ticker']}_{filing['form_type']}_{filing['filing_date']}.txt"
        filepath = os.path.join(self.output_dir, filing['form_type'], filename)
        
        # Skip if already downloaded
        if os.path.exists(filepath):
            return filepath, "cached"
        
        # Try downloading with retries
        max_retries = 3
        for attempt in range(max_retries):
            try:
                self.rate_limit()
                
                # Update headers for SEC Archives
                headers = {
                    "User-Agent": USER_AGENT,
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    "Accept-Language": "en-US,en;q=0.5",
                    "Accept-Encoding": "gzip, deflate",
                    "Connection": "keep-alive",
                }
                
                response = requests.get(filing['url'], headers=headers, timeout=30)
                
                if response.status_code == 429:  # Rate limited
                    wait_time = 2 ** attempt * 5  # Exponential backoff
                    print(f"    Rate limited, waiting {wait_time}s...")
                    time.sleep(wait_time)
                    continue
                
                response.raise_for_status()
                
                # Extract text content
                content = response.text
                
                # Basic HTML stripping
                import re
                text = re.sub('<[^<]+?>', '', content)
                text = re.sub(r'\s+', ' ', text)
                
                # Limit size to avoid huge files
                text = text[:500000]
                
                # Save to file
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(text)
                
                return filepath, "downloaded"
                
            except Exception as e:
                if attempt == max_retries - 1:
                    return None, f"error: {str(e)}"
                time.sleep(2 ** attempt)
        
        return None, "max_retries"
    
    def fetch_all_filings(self):
        """Main method to fetch all filings"""
        companies = RUSSELL_2000_FULL
        
        print(f"🚀 Fetching SEC filings for {len(companies)} Russell 2000 companies")
        print(f"📁 Output directory: {self.output_dir}")
        print(f"⏰ Rate limit: {REQUESTS_PER_SECOND} requests/second")
        
        all_filings = []
        successful_companies = 0
        
        # Phase 1: Fetch metadata
        print("\n1️⃣ Fetching company metadata...")
        for ticker, cik in tqdm(companies.items(), desc="Metadata"):
            metadata = self.get_company_metadata(ticker, cik)
            if metadata:
                filings = self.extract_filings(metadata, ticker, cik)
                all_filings.extend(filings)
                successful_companies += 1
        
        print(f"\n✅ Found {len(all_filings)} filings from {successful_companies} companies")
        
        # Save filing list
        filings_list_file = os.path.join(self.output_dir, "all_filings.json")
        with open(filings_list_file, 'w') as f:
            json.dump(all_filings, f, indent=2)
        
        # Phase 2: Download filing texts
        print("\n2️⃣ Downloading filing texts...")
        stats = {"downloaded": 0, "cached": 0, "errors": 0}
        
        for filing in tqdm(all_filings, desc="Downloading"):
            filepath, status = self.download_filing_text(filing)
            
            if status == "downloaded":
                stats["downloaded"] += 1
            elif status == "cached":
                stats["cached"] += 1
            else:
                stats["errors"] += 1
        
        # Summary
        print(f"\n📊 Download Summary:")
        print(f"   Downloaded: {stats['downloaded']}")
        print(f"   Cached: {stats['cached']}")
        print(f"   Errors: {stats['errors']}")
        print(f"   Total: {len(all_filings)}")
        
        # Save summary
        summary = {
            "total_companies": len(companies),
            "successful_companies": successful_companies,
            "total_filings": len(all_filings),
            "stats": stats,
            "timestamp": datetime.now().isoformat()
        }
        
        summary_file = os.path.join(self.output_dir, "fetch_summary.json")
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"\n💾 Summary saved to {summary_file}")
        
        return all_filings

def main():
    """Main entry point"""
    print("🏢 Robust SEC Filing Fetcher for Russell 2000")
    print("=" * 50)
    
    fetcher = SECFilingFetcher()
    filings = fetcher.fetch_all_filings()
    
    print("\n✅ Data collection complete!")
    print("\n📋 Next steps:")
    print("1. Process filings with process_sec_filings_for_training.py")
    print("2. Train SEC-BERT with real filing data")
    print("3. Convert model to CoreML for deployment")

if __name__ == "__main__":
    main()