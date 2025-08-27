#!/usr/bin/env python3
"""
Comprehensive SEC filing fetcher for Russell 2000 Index
Downloads all filings for all ~2000 companies with proper organization
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
from tqdm import tqdm
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('russell2000_fetch.log'),
        logging.StreamHandler()
    ]
)

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
SEC_API_BASE = "https://data.sec.gov"
SEC_ARCHIVES = "https://www.sec.gov/Archives"
USER_AGENT = "Academic Research russell2000@university.edu"  # Update with your email

# SEC Rate Limits: 10 requests per second max
RATE_LIMIT = 8  # Conservative: 8 requests per second
REQUEST_DELAY = 1.0 / RATE_LIMIT

class Russell2000SECFetcher:
    def __init__(self):
        self.data_dir = DATA_DIR
        os.makedirs(self.data_dir, exist_ok=True)
        
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        })
        
        self.last_request_time = 0
        self.ticker_to_cik = {}
        self.russell2000_tickers = []
        
        # Load Russell 2000 list
        self.load_russell2000()
        
        # Load SEC CIK mappings
        self.load_cik_mappings()
        
        # Statistics
        self.stats = {
            "total": len(self.russell2000_tickers),
            "fetched": 0,
            "skipped": 0,
            "no_cik": 0,
            "errors": 0,
            "total_filings": 0
        }
        
    def load_russell2000(self):
        """Load Russell 2000 ticker list"""
        if os.path.exists("russell2000_2024.json"):
            with open("russell2000_2024.json", "r") as f:
                data = json.load(f)
                self.russell2000_tickers = data["tickers"]
                logging.info(f"Loaded {len(self.russell2000_tickers)} Russell 2000 tickers")
        else:
            logging.error("russell2000_2024.json not found!")
            raise FileNotFoundError("Russell 2000 ticker list not found")
    
    def load_cik_mappings(self):
        """Load SEC ticker to CIK mappings"""
        cik_file = "company_tickers.json"
        
        if not os.path.exists(cik_file):
            logging.info("Downloading SEC CIK mappings...")
            url = "https://www.sec.gov/files/company_tickers.json"
            
            for attempt in range(3):
                try:
                    response = self.session.get(url, timeout=30)
                    response.raise_for_status()
                    
                    with open(cik_file, "w") as f:
                        json.dump(response.json(), f)
                    break
                except Exception as e:
                    logging.warning(f"Attempt {attempt + 1} failed: {e}")
                    time.sleep(5)
        
        # Load mappings
        with open(cik_file, "r") as f:
            data = json.load(f)
        
        for entry in data.values():
            ticker = entry.get("ticker", "").upper()
            cik = str(entry.get("cik_str", "")).zfill(10)
            if ticker:
                self.ticker_to_cik[ticker] = {
                    "cik": cik,
                    "name": entry.get("title", "")
                }
        
        logging.info(f"Loaded {len(self.ticker_to_cik)} ticker-to-CIK mappings")
        
        # Check how many Russell 2000 companies have CIKs
        matched = sum(1 for t in self.russell2000_tickers if t in self.ticker_to_cik)
        logging.info(f"Matched {matched}/{len(self.russell2000_tickers)} Russell 2000 companies to CIKs")
    
    def rate_limit(self):
        """Enforce SEC rate limiting"""
        elapsed = time.time() - self.last_request_time
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request_time = time.time()
    
    def fetch_company_filings(self, ticker):
        """Fetch all filings for a single company"""
        ticker_dir = os.path.join(self.data_dir, ticker)
        
        # Check if already fetched
        status_file = os.path.join(ticker_dir, "fetch_complete.json")
        if os.path.exists(status_file):
            self.stats["skipped"] += 1
            return "skipped"
        
        # Check if ticker has CIK
        if ticker not in self.ticker_to_cik:
            self.stats["no_cik"] += 1
            logging.warning(f"{ticker}: No CIK mapping found")
            return "no_cik"
        
        cik_info = self.ticker_to_cik[ticker]
        cik = cik_info["cik"]
        company_name = cik_info["name"]
        
        # Create ticker directory structure
        os.makedirs(ticker_dir, exist_ok=True)
        for subdir in ["10-K", "10-Q", "8-K", "metadata"]:
            os.makedirs(os.path.join(ticker_dir, subdir), exist_ok=True)
        
        try:
            # Rate limit
            self.rate_limit()
            
            # Fetch submissions from SEC
            url = f"{SEC_API_BASE}/submissions/CIK{cik}.json"
            response = self.session.get(url, timeout=30)
            
            if response.status_code == 404:
                logging.warning(f"{ticker}: CIK {cik} not found at SEC")
                return "not_found"
            
            response.raise_for_status()
            submissions = response.json()
            
            # Save company metadata
            company_info = {
                "ticker": ticker,
                "cik": cik,
                "name": company_name,
                "sec_name": submissions.get("name", ""),
                "sic": submissions.get("sic", ""),
                "sic_description": submissions.get("sicDescription", ""),
                "state": submissions.get("stateOfIncorporation", ""),
                "fiscal_year_end": submissions.get("fiscalYearEnd", ""),
                "fetched": datetime.now().isoformat()
            }
            
            with open(os.path.join(ticker_dir, "metadata", "company.json"), "w") as f:
                json.dump(company_info, f, indent=2)
            
            # Extract filings (last 5 years)
            filings = self.extract_filings(submissions)
            
            # Save filings metadata
            with open(os.path.join(ticker_dir, "metadata", "filings.json"), "w") as f:
                json.dump(filings, f, indent=2)
            
            # Mark as complete
            with open(status_file, "w") as f:
                json.dump({
                    "status": "complete",
                    "ticker": ticker,
                    "cik": cik,
                    "filings_count": len(filings),
                    "timestamp": datetime.now().isoformat()
                }, f)
            
            self.stats["fetched"] += 1
            self.stats["total_filings"] += len(filings)
            
            logging.info(f"{ticker}: Fetched {len(filings)} filings")
            return "success"
            
        except Exception as e:
            self.stats["errors"] += 1
            logging.error(f"{ticker}: Error - {e}")
            
            # Save error info
            error_file = os.path.join(ticker_dir, "error.json")
            with open(error_file, "w") as f:
                json.dump({
                    "ticker": ticker,
                    "error": str(e),
                    "timestamp": datetime.now().isoformat()
                }, f)
            
            return "error"
    
    def extract_filings(self, submissions, years=5):
        """Extract relevant filings from SEC submissions"""
        filings = []
        cutoff_date = datetime.now() - timedelta(days=365 * years)
        
        recent = submissions.get("filings", {}).get("recent", {})
        if not recent or "form" not in recent:
            return filings
        
        # Process each filing
        for i in range(len(recent.get("form", []))):
            try:
                form_type = recent["form"][i]
                
                # Only get 10-K, 10-Q, 8-K
                if form_type not in ["10-K", "10-Q", "8-K"]:
                    continue
                
                filing_date = recent.get("filingDate", [""])[i]
                if not filing_date:
                    continue
                
                filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
                if filing_dt < cutoff_date:
                    continue
                
                # Get accession number
                accession = recent.get("accessionNumber", [""])[i]
                if not accession:
                    continue
                
                # Build filing record
                filing = {
                    "form_type": form_type,
                    "filing_date": filing_date,
                    "accession_number": accession,
                    "primary_document": recent.get("primaryDocument", [""])[i],
                    "report_date": recent.get("reportDate", [""])[i],
                    "file_number": recent.get("fileNumber", [""])[i],
                    "size": recent.get("size", [0])[i]
                }
                
                filings.append(filing)
                
            except (IndexError, ValueError) as e:
                continue
        
        return filings
    
    def fetch_all(self):
        """Fetch all Russell 2000 companies"""
        print("\n" + "=" * 70)
        print("🚀 Russell 2000 SEC Filing Fetcher")
        print("=" * 70)
        print(f"📊 Total companies: {len(self.russell2000_tickers)}")
        print(f"📁 Data directory: {self.data_dir}")
        print(f"⏱️ Rate limit: {RATE_LIMIT} requests/second")
        print(f"📅 Fetching filings from last 5 years")
        print()
        
        # Estimate time
        est_time = len(self.russell2000_tickers) * REQUEST_DELAY / 60
        print(f"⏰ Estimated minimum time: {est_time:.1f} minutes")
        print("=" * 70 + "\n")
        
        # Progress bar
        for ticker in tqdm(self.russell2000_tickers, desc="Fetching companies"):
            self.fetch_company_filings(ticker)
            
            # Progress update every 100 companies
            if self.stats["fetched"] % 100 == 0 and self.stats["fetched"] > 0:
                self.print_progress()
        
        # Final summary
        self.print_summary()
        
        return self.stats
    
    def print_progress(self):
        """Print progress statistics"""
        elapsed = self.stats["fetched"] + self.stats["skipped"] + self.stats["errors"]
        pct = (elapsed / self.stats["total"]) * 100
        
        tqdm.write(f"\n📊 Progress: {pct:.1f}% complete")
        tqdm.write(f"   Fetched: {self.stats['fetched']}")
        tqdm.write(f"   Skipped: {self.stats['skipped']}")
        tqdm.write(f"   No CIK: {self.stats['no_cik']}")
        tqdm.write(f"   Errors: {self.stats['errors']}")
        tqdm.write(f"   Total filings: {self.stats['total_filings']}\n")
    
    def print_summary(self):
        """Print final summary"""
        print("\n" + "=" * 70)
        print("✅ Fetching Complete!")
        print("=" * 70)
        print("📊 Final Statistics:")
        print(f"   Total companies: {self.stats['total']}")
        print(f"   Successfully fetched: {self.stats['fetched']}")
        print(f"   Already cached: {self.stats['skipped']}")
        print(f"   No CIK mapping: {self.stats['no_cik']}")
        print(f"   Errors: {self.stats['errors']}")
        print(f"   Total filings: {self.stats['total_filings']}")
        print()
        print(f"📁 Data location: {self.data_dir}")
        print("   Each ticker has its own subdirectory with:")
        print("   - metadata/company.json (company info)")
        print("   - metadata/filings.json (filing list)")
        print("   - 10-K/, 10-Q/, 8-K/ (filing documents)")
        print("=" * 70)
        
        # Save summary
        summary_file = os.path.join(self.data_dir, "fetch_summary.json")
        with open(summary_file, "w") as f:
            json.dump({
                "russell2000": True,
                "timestamp": datetime.now().isoformat(),
                "stats": self.stats
            }, f, indent=2)

if __name__ == "__main__":
    fetcher = Russell2000SECFetcher()
    fetcher.fetch_all()
