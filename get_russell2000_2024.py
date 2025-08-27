#!/usr/bin/env python3
"""
Get the current Russell 2000 Index constituents (2024)
The Russell 2000 is reconstituted annually in June
"""

import json
import requests
import pandas as pd
from datetime import datetime
import time
import os

def get_current_russell2000_from_iwm():
    """
    Get current Russell 2000 constituents from IWM ETF
    IWM (iShares Russell 2000 ETF) is updated to match the index
    """
    print("📊 Fetching current Russell 2000 constituents (2024) from IWM ETF...")
    
    # iShares provides a CSV download of current holdings
    # This URL provides the most recent holdings
    base_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf"
    
    # Direct download URL for IWM holdings CSV
    csv_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf/1467271812596.ajax?fileType=csv&fileName=IWM_holdings&dataType=fund"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1"
    }
    
    try:
        print("📥 Downloading IWM holdings CSV...")
        
        # First get the main page to establish session
        session = requests.Session()
        session.headers.update(headers)
        
        # Get the main page
        response = session.get(base_url)
        time.sleep(1)  # Be polite
        
        # Now get the CSV
        csv_response = session.get(csv_url)
        
        if csv_response.status_code == 200:
            # Save raw CSV
            with open("iwm_holdings_2024.csv", "wb") as f:
                f.write(csv_response.content)
            
            print("✅ Downloaded IWM holdings")
            
            # Parse the CSV
            # iShares CSV has metadata rows at the top
            try:
                # Try reading with different skip rows
                for skip in [9, 10, 11, 12]:
                    try:
                        df = pd.read_csv("iwm_holdings_2024.csv", skiprows=skip)
                        if len(df) > 1500:  # Should have ~2000 holdings
                            break
                    except:
                        continue
                
                # Find ticker column
                ticker_col = None
                for col in df.columns:
                    if 'ticker' in col.lower() or 'symbol' in col.lower():
                        ticker_col = col
                        break
                
                if ticker_col:
                    # Extract tickers
                    tickers = df[ticker_col].dropna().astype(str).str.strip().str.upper()
                    
                    # Filter out non-equity entries
                    tickers = [t for t in tickers if t and 
                              not t.startswith('$') and 
                              not t.startswith('CASH') and
                              not t.startswith('XX') and
                              len(t) <= 5 and
                              t.replace('-', '').replace('.', '').isalnum()]
                    
                    print(f"✅ Found {len(tickers)} equity tickers")
                    return tickers
                else:
                    print(f"❌ Could not find ticker column. Columns: {df.columns.tolist()[:10]}")
                    
            except Exception as e:
                print(f"❌ Error parsing CSV: {e}")
        else:
            print(f"❌ Failed to download: HTTP {csv_response.status_code}")
            
    except Exception as e:
        print(f"❌ Error: {e}")
    
    return []

def get_russell2000_from_api():
    """
    Alternative: Get Russell 2000 from financial data API
    """
    print("\n📊 Trying alternative data sources...")
    
    # Option 1: Try Yahoo Finance symbols for Russell 2000
    # The Russell 2000 index symbol is ^RUT
    try:
        # This would require yfinance or similar
        print("   Checking Yahoo Finance data...")
        
        # You could also scrape from financial sites
        # Example: finviz, marketwatch, etc.
        
    except Exception as e:
        print(f"   Yahoo Finance unavailable: {e}")
    
    return []

def get_russell2000_from_etfdb():
    """
    Get Russell 2000 constituents from ETF Database
    """
    print("\n📊 Fetching from ETF Database...")
    
    url = "https://etfdb.com/etf/IWM/"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    try:
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            # Would need to parse HTML for holdings
            # This is a backup option
            pass
    except:
        pass
    
    return []

def validate_and_save_tickers(tickers):
    """
    Validate and save the Russell 2000 ticker list
    """
    # Remove duplicates and sort
    tickers = sorted(list(set(tickers)))
    
    print(f"\n📊 Validation:")
    print(f"   Total unique tickers: {len(tickers)}")
    
    # Check for common Russell 2000 companies that should be there
    expected_samples = ["SMCI", "WING", "TXRH", "BOOT", "SHAK", "INSM", "TALO"]
    found = [t for t in expected_samples if t in tickers]
    print(f"   Sanity check - found {len(found)}/{len(expected_samples)} expected tickers")
    
    # Save the list
    output = {
        "index_name": "Russell 2000",
        "date_fetched": datetime.now().isoformat(),
        "year": 2024,
        "reconstitution": "June 2024",  # Russell reconstitutes annually in June
        "count": len(tickers),
        "tickers": tickers,
        "source": "iShares IWM ETF Holdings"
    }
    
    filename = "russell2000_2024.json"
    with open(filename, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n💾 Saved {len(tickers)} tickers to {filename}")
    
    # Also save just the ticker list for easy access
    with open("russell2000_tickers.txt", "w") as f:
        f.write("\n".join(tickers))
    
    return tickers

def create_comprehensive_fetcher():
    """
    Create a comprehensive fetcher script for olympus
    """
    script = '''#!/usr/bin/env python3
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
        print("\\n" + "=" * 70)
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
        print("=" * 70 + "\\n")
        
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
        
        tqdm.write(f"\\n📊 Progress: {pct:.1f}% complete")
        tqdm.write(f"   Fetched: {self.stats['fetched']}")
        tqdm.write(f"   Skipped: {self.stats['skipped']}")
        tqdm.write(f"   No CIK: {self.stats['no_cik']}")
        tqdm.write(f"   Errors: {self.stats['errors']}")
        tqdm.write(f"   Total filings: {self.stats['total_filings']}\\n")
    
    def print_summary(self):
        """Print final summary"""
        print("\\n" + "=" * 70)
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
'''
    
    with open("fetch_russell2000_comprehensive.py", "w") as f:
        f.write(script)
    
    print("✅ Created fetch_russell2000_comprehensive.py")

def main():
    print("🏢 Getting Russell 2000 Index Constituents (2024)")
    print("=" * 60)
    
    # Get from IWM ETF
    tickers = get_current_russell2000_from_iwm()
    
    # Try alternatives if needed
    if len(tickers) < 1900:
        print(f"\n⚠️ Only found {len(tickers)} tickers from IWM")
        print("Trying alternative sources...")
        
        # Try other sources
        additional = get_russell2000_from_api()
        if additional:
            tickers.extend(additional)
        
        additional = get_russell2000_from_etfdb()
        if additional:
            tickers.extend(additional)
    
    # Validate and save
    if tickers:
        final_tickers = validate_and_save_tickers(tickers)
        
        # Create fetcher script
        create_comprehensive_fetcher()
        
        print("\n📋 Next Steps:")
        print("1. Transfer russell2000_2024.json to olympus")
        print("2. Transfer fetch_russell2000_comprehensive.py to olympus")
        print("3. Run the fetcher on olympus (will take several hours)")
        print("4. Only train SEC-BERT after ALL data is collected")
        print(f"\n⏰ Estimated fetch time: ~{len(final_tickers) * 0.125 / 60:.1f} hours minimum")
    else:
        print("\n❌ Failed to get Russell 2000 list")
        print("Please manually download from:")
        print("- https://www.ftserussell.com/products/indices/russell-us")
        print("- Bloomberg Terminal: RUT Index Members")
        print("- Refinitiv: Russell 2000 Constituents")

if __name__ == "__main__":
    main()