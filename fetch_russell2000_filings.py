#!/usr/bin/env python3
"""
Fetch all SEC filings for Russell 2000 companies
Organized by ticker subdirectories with proper rate limiting
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
from tqdm import tqdm

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
SEC_API_BASE = "https://data.sec.gov"
USER_AGENT = "Academic Research Bot research@university.edu"
RATE_LIMIT = 10  # SEC allows 10 requests per second
REQUEST_DELAY = 0.15  # 150ms between requests (conservative)

class Russell2000Fetcher:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        })
        self.last_request_time = 0
        
        # Load Russell 2000 tickers
        with open("russell_2000_tickers.json", "r") as f:
            data = json.load(f)
            self.tickers = data["tickers"]
        
        # Load SEC CIK mappings
        self.load_cik_mappings()
        
        print(f"📊 Loaded {len(self.tickers)} Russell 2000 tickers")
        print(f"📁 Data directory: {DATA_DIR}")
        
    def load_cik_mappings(self):
        """Load ticker to CIK mappings from SEC"""
        if os.path.exists("company_tickers.json"):
            with open("company_tickers.json", "r") as f:
                data = json.load(f)
        else:
            # Download from SEC
            print("📥 Downloading SEC ticker mappings...")
            url = "https://www.sec.gov/files/company_tickers.json"
            response = self.session.get(url)
            response.raise_for_status()
            data = response.json()
            
            with open("company_tickers.json", "w") as f:
                json.dump(data, f)
        
        # Build mapping
        self.ticker_to_cik = {}
        for entry in data.values():
            ticker = entry.get("ticker", "").upper()
            cik = str(entry.get("cik_str", "")).zfill(10)
            if ticker:
                self.ticker_to_cik[ticker] = cik
        
        print(f"✅ Loaded {len(self.ticker_to_cik)} ticker-to-CIK mappings")
    
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request_time
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request_time = time.time()
    
    def fetch_ticker(self, ticker):
        """Fetch all filings for a single ticker"""
        # Skip if no CIK
        if ticker not in self.ticker_to_cik:
            return {"ticker": ticker, "status": "no_cik"}
        
        cik = self.ticker_to_cik[ticker]
        ticker_dir = os.path.join(DATA_DIR, ticker)
        
        # Check if already fetched
        status_file = os.path.join(ticker_dir, "fetch_status.json")
        if os.path.exists(status_file):
            return {"ticker": ticker, "status": "already_fetched"}
        
        # Create ticker directory
        os.makedirs(ticker_dir, exist_ok=True)
        for subdir in ["10-K", "10-Q", "8-K", "metadata"]:
            os.makedirs(os.path.join(ticker_dir, subdir), exist_ok=True)
        
        try:
            # Rate limit
            self.rate_limit()
            
            # Fetch submissions
            url = f"{SEC_API_BASE}/submissions/CIK{cik}.json"
            response = self.session.get(url, timeout=30)
            
            if response.status_code == 404:
                return {"ticker": ticker, "status": "not_found"}
            
            response.raise_for_status()
            submissions = response.json()
            
            # Save metadata
            metadata = {
                "ticker": ticker,
                "cik": cik,
                "name": submissions.get("name", ""),
                "sic": submissions.get("sic", ""),
                "sicDescription": submissions.get("sicDescription", ""),
                "fetched": datetime.now().isoformat()
            }
            
            with open(os.path.join(ticker_dir, "metadata", "company.json"), "w") as f:
                json.dump(metadata, f, indent=2)
            
            # Extract filings (last 5 years)
            filings = self.extract_filings(submissions, ticker, cik)
            
            # Save filings list
            with open(os.path.join(ticker_dir, "metadata", "filings.json"), "w") as f:
                json.dump(filings, f, indent=2)
            
            # Mark as complete
            with open(status_file, "w") as f:
                json.dump({
                    "status": "complete",
                    "filings_count": len(filings),
                    "timestamp": datetime.now().isoformat()
                }, f)
            
            return {
                "ticker": ticker,
                "status": "success",
                "filings": len(filings)
            }
            
        except Exception as e:
            return {
                "ticker": ticker,
                "status": "error",
                "error": str(e)
            }
    
    def extract_filings(self, submissions, ticker, cik, years=5):
        """Extract filing information"""
        filings = []
        cutoff_date = datetime.now() - timedelta(days=365 * years)
        
        recent = submissions.get("filings", {}).get("recent", {})
        if not recent:
            return filings
        
        for i in range(len(recent.get("form", []))):
            form_type = recent["form"][i]
            
            # Only get 10-K, 10-Q, 8-K
            if form_type not in ["10-K", "10-Q", "8-K"]:
                continue
            
            filing_date = recent["filingDate"][i]
            filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
            
            if filing_dt < cutoff_date:
                continue
            
            filings.append({
                "form": form_type,
                "filing_date": filing_date,
                "accession": recent["accessionNumber"][i],
                "primary_doc": recent.get("primaryDocument", [""])[i],
                "report_date": recent.get("reportDate", [""])[i]
            })
        
        return filings
    
    def fetch_all(self):
        """Fetch all Russell 2000 companies"""
        print(f"\n🚀 Starting fetch for {len(self.tickers)} Russell 2000 companies")
        print(f"⏱️ Estimated time: {len(self.tickers) * REQUEST_DELAY / 60:.1f} minutes minimum\n")
        
        results = {
            "success": 0,
            "already_fetched": 0,
            "no_cik": 0,
            "not_found": 0,
            "error": 0
        }
        
        for ticker in tqdm(self.tickers, desc="Fetching companies"):
            result = self.fetch_ticker(ticker)
            status = result["status"]
            
            if status in results:
                results[status] += 1
            else:
                results["error"] += 1
            
            # Progress update every 100 companies
            if (results["success"] + results["already_fetched"]) % 100 == 0:
                elapsed = (results["success"] + results["already_fetched"]) * REQUEST_DELAY
                print(f"  Progress: {results['success']} fetched, {results['already_fetched']} cached")
        
        # Final summary
        print("\n" + "=" * 60)
        print("📊 Final Summary:")
        for key, count in results.items():
            print(f"  {key}: {count}")
        
        print(f"\n✅ Data saved in {DATA_DIR}")
        print("Each ticker has its own subdirectory with metadata and filing info")
        
        return results

if __name__ == "__main__":
    fetcher = Russell2000Fetcher()
    fetcher.fetch_all()
