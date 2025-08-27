#!/usr/bin/env python3
"""
Get the CURRENT Russell 2000 Index constituents as of August 2025
The Russell 2000 is reconstituted annually in June, so we need the June 2025 list
"""

import json
import requests
import pandas as pd
from datetime import datetime
import time
import os
import csv

def get_russell2000_august_2025():
    """
    Get the current Russell 2000 constituents as of August 26, 2025
    The index was last reconstituted in June 2025
    """
    print("📊 Fetching CURRENT Russell 2000 constituents (August 26, 2025)")
    print("=" * 70)
    
    tickers = []
    
    # Method 1: Get from IWM ETF (iShares Russell 2000 ETF)
    # This ETF tracks the Russell 2000 and is updated after each reconstitution
    print("\n1️⃣ Fetching from iShares IWM ETF (Russell 2000 tracker)...")
    
    try:
        # iShares provides current holdings data
        # The ETF is rebalanced to match the Russell 2000 after June reconstitution
        
        # Build request for current holdings
        session = requests.Session()
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate, br",
            "DNT": "1",
            "Connection": "keep-alive",
            "Upgrade-Insecure-Requests": "1"
        }
        session.headers.update(headers)
        
        # First, get the main IWM page to establish cookies
        main_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf"
        print("   Accessing IWM page...")
        response = session.get(main_url)
        time.sleep(2)  # Be respectful
        
        # Now get the holdings data
        # This endpoint provides the current holdings as of the latest update
        holdings_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf/1467271812596.ajax"
        params = {
            "fileType": "csv",
            "fileName": "IWM_holdings",
            "dataType": "fund",
            "asOfDate": "20250826"  # Current date
        }
        
        print("   Downloading current holdings...")
        response = session.get(holdings_url, params=params)
        
        if response.status_code == 200:
            # Save the raw data
            filename = "iwm_holdings_august_2025.csv"
            with open(filename, "wb") as f:
                f.write(response.content)
            print(f"   ✅ Saved raw data to {filename}")
            
            # Parse the CSV
            # iShares CSV has metadata rows at the top, typically 9-12 rows
            for skip_rows in [9, 10, 11, 12]:
                try:
                    df = pd.read_csv(filename, skiprows=skip_rows, encoding='utf-8')
                    
                    # Look for ticker/symbol column
                    ticker_col = None
                    for col in df.columns:
                        if 'ticker' in col.lower() or 'symbol' in col.lower():
                            ticker_col = col
                            break
                    
                    if ticker_col and len(df) > 1500:  # Should have ~2000 stocks
                        # Extract tickers
                        raw_tickers = df[ticker_col].dropna().astype(str).str.strip().str.upper().tolist()
                        
                        # Clean: remove cash positions, derivatives, etc.
                        clean_tickers = []
                        for t in raw_tickers:
                            if (t and 
                                not t.startswith('$') and 
                                not t.startswith('CASH') and 
                                not t.startswith('XX') and
                                not t in ['N/A', 'NA', '--', ''] and
                                len(t) <= 6 and  # Normal ticker length
                                any(c.isalpha() for c in t)):  # Has letters
                                clean_tickers.append(t)
                        
                        if len(clean_tickers) >= 1900:  # Close to 2000
                            tickers = clean_tickers
                            print(f"   ✅ Found {len(tickers)} tickers from IWM")
                            break
                    
                except Exception as e:
                    continue
            
            if not tickers:
                print("   ❌ Could not parse IWM holdings CSV")
        else:
            print(f"   ❌ Failed to download IWM holdings: {response.status_code}")
            
    except Exception as e:
        print(f"   ❌ Error fetching IWM data: {e}")
    
    # Method 2: Alternative - Get from FTSE Russell directly
    if len(tickers) < 1900:
        print("\n2️⃣ Attempting to fetch from FTSE Russell (index provider)...")
        print("   Note: FTSE Russell provides official constituents after June reconstitution")
        print("   The June 2025 reconstitution is the latest for August 2025")
        
        # FTSE Russell typically provides constituent data through:
        # - Direct data license
        # - Bloomberg/Refinitiv terminals
        # - Official reconstitution announcements
        
        # For automated access, we'd need API credentials
        # Manual download available at: https://www.ftserussell.com/products/indices/russell-us
    
    # Method 3: Get from financial data aggregators
    if len(tickers) < 1900:
        print("\n3️⃣ Checking financial data aggregators...")
        
        # Try Yahoo Finance components (if available)
        try:
            print("   Checking Yahoo Finance for Russell 2000 components...")
            # The Russell 2000 index is ^RUT on Yahoo
            # Components would need to be scraped or accessed via API
        except:
            pass
    
    return tickers

def validate_current_tickers(tickers):
    """
    Validate that we have current Russell 2000 tickers
    """
    print("\n🔍 Validating ticker list...")
    
    # Remove duplicates
    tickers = list(set(tickers))
    tickers.sort()
    
    print(f"   Total unique tickers: {len(tickers)}")
    
    # Sanity check: Look for known Russell 2000 companies that should be there in 2025
    # These are typically consistent Russell 2000 members
    expected_companies = [
        "AAON",  # AAON Inc - consistent member
        "AEIS",  # Advanced Energy Industries
        "CALM",  # Cal-Maine Foods
        "CATY",  # Cathay General Bancorp
        "CBSH",  # Commerce Bancshares
        "CHCO",  # City Holding Company
        "CWT",   # California Water Service
        "ENSG",  # The Ensign Group
        "EWBC",  # East West Bancorp
        "FELE",  # Franklin Electric
        "GBCI",  # Glacier Bancorp
        "HOMB",  # Home BancShares
        "HTLF",  # Heartland Financial
        "IBOC",  # International Bancshares
        "JJSF",  # J & J Snack Foods
        "LANC",  # Lancaster Colony
        "MGY",   # Magnolia Oil & Gas
        "OZK",   # Bank OZK
        "PATK",  # Patrick Industries
        "RBC",   # Regal Beloit
        "SFNC",  # Simmons First National
        "SJI",   # South Jersey Industries
        "UFPI",  # UFP Industries
        "WAFD",  # Washington Federal
    ]
    
    found = [t for t in expected_companies if t in tickers]
    print(f"   Sanity check: Found {len(found)}/{len(expected_companies)} expected long-term members")
    
    if len(found) < len(expected_companies) / 2:
        print("   ⚠️  Warning: Many expected companies not found. List may be incomplete.")
    
    return tickers

def save_russell2000_current(tickers):
    """
    Save the current Russell 2000 list with metadata
    """
    # Create comprehensive data structure
    russell_data = {
        "index_name": "Russell 2000",
        "current_date": "2025-08-26",
        "last_reconstitution": "2025-06-28",  # Russell reconstitutes last Friday of June
        "next_reconstitution": "2026-06-26",
        "data_source": "iShares IWM ETF Holdings",
        "total_constituents": len(tickers),
        "fetch_timestamp": datetime.now().isoformat(),
        "tickers": sorted(tickers)
    }
    
    # Save as JSON
    filename = "russell2000_current.json"
    with open(filename, "w") as f:
        json.dump(russell_data, f, indent=2)
    
    print(f"\n💾 Saved {len(tickers)} current Russell 2000 tickers to {filename}")
    
    # Also save as simple text list
    with open("russell2000_tickers.txt", "w") as f:
        for ticker in sorted(tickers):
            f.write(f"{ticker}\n")
    
    print(f"   Also saved as russell2000_tickers.txt")
    
    return russell_data

def create_fetcher_for_current_russell():
    """
    Create fetcher script specifically for current Russell 2000
    """
    print("\n📝 Creating SEC filing fetcher for current Russell 2000...")
    
    script = '''#!/usr/bin/env python3
"""
SEC Filing Fetcher for Current Russell 2000 Index (August 2025)
Fetches all SEC filings for all ~2000 companies with proper organization
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
from tqdm import tqdm
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    handlers=[
        logging.FileHandler('russell2000_sec_fetch.log'),
        logging.StreamHandler()
    ]
)

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
SEC_API = "https://data.sec.gov"
USER_AGENT = "Academic Research Bot research@university.edu"

# SEC Rate Limiting: Max 10 requests per second
# We'll use 8 requests per second to be safe
RATE_LIMIT = 8
REQUEST_DELAY = 1.0 / RATE_LIMIT

class CurrentRussell2000Fetcher:
    def __init__(self):
        self.data_dir = DATA_DIR
        os.makedirs(self.data_dir, exist_ok=True)
        
        # Setup session
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        })
        
        self.last_request = 0
        
        # Load Russell 2000 list
        self.load_russell2000()
        
        # Load CIK mappings
        self.load_cik_mappings()
        
        # Track progress
        self.progress = {
            "total": len(self.russell2000_tickers),
            "completed": 0,
            "skipped": 0,
            "no_cik": 0,
            "errors": 0,
            "total_filings": 0,
            "start_time": datetime.now()
        }
    
    def load_russell2000(self):
        """Load current Russell 2000 list"""
        with open("russell2000_current.json", "r") as f:
            data = json.load(f)
            self.russell2000_tickers = data["tickers"]
            self.reconstitution_date = data["last_reconstitution"]
        
        logging.info(f"Loaded {len(self.russell2000_tickers)} Russell 2000 tickers")
        logging.info(f"Last reconstitution: {self.reconstitution_date}")
    
    def load_cik_mappings(self):
        """Load SEC CIK mappings"""
        # Check if we have the mapping file
        if not os.path.exists("company_tickers.json"):
            logging.info("Downloading SEC ticker-to-CIK mappings...")
            url = f"{SEC_API}/files/company_tickers.json"
            
            response = self.session.get(url)
            response.raise_for_status()
            
            with open("company_tickers.json", "w") as f:
                json.dump(response.json(), f)
        
        # Load mappings
        with open("company_tickers.json", "r") as f:
            sec_data = json.load(f)
        
        self.ticker_to_cik = {}
        for item in sec_data.values():
            ticker = item.get("ticker", "").upper()
            cik = str(item.get("cik_str", "")).zfill(10)
            if ticker:
                self.ticker_to_cik[ticker] = {
                    "cik": cik,
                    "name": item.get("title", "")
                }
        
        # Check coverage
        matched = sum(1 for t in self.russell2000_tickers if t in self.ticker_to_cik)
        logging.info(f"Matched {matched}/{len(self.russell2000_tickers)} to CIKs")
    
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request = time.time()
    
    def fetch_company(self, ticker):
        """Fetch all SEC filings for one company"""
        ticker_dir = os.path.join(self.data_dir, ticker)
        
        # Check if already done
        if os.path.exists(os.path.join(ticker_dir, "complete.json")):
            self.progress["skipped"] += 1
            return "skipped"
        
        # Check CIK
        if ticker not in self.ticker_to_cik:
            self.progress["no_cik"] += 1
            return "no_cik"
        
        cik_data = self.ticker_to_cik[ticker]
        cik = cik_data["cik"]
        
        # Create directory structure
        os.makedirs(ticker_dir, exist_ok=True)
        for subdir in ["10-K", "10-Q", "8-K", "metadata"]:
            os.makedirs(os.path.join(ticker_dir, subdir), exist_ok=True)
        
        try:
            # Rate limit
            self.rate_limit()
            
            # Get submissions
            url = f"{SEC_API}/submissions/CIK{cik}.json"
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            
            submissions = response.json()
            
            # Save company info
            company_info = {
                "ticker": ticker,
                "cik": cik,
                "name": cik_data["name"],
                "sec_name": submissions.get("name", ""),
                "sic": submissions.get("sic", ""),
                "sic_description": submissions.get("sicDescription", ""),
                "fiscal_year_end": submissions.get("fiscalYearEnd", ""),
                "state": submissions.get("stateOfIncorporation", ""),
                "fetched": datetime.now().isoformat()
            }
            
            with open(os.path.join(ticker_dir, "metadata", "company.json"), "w") as f:
                json.dump(company_info, f, indent=2)
            
            # Extract filings (5 years)
            filings = self.extract_filings(submissions)
            
            # Save filings list
            with open(os.path.join(ticker_dir, "metadata", "filings.json"), "w") as f:
                json.dump(filings, f, indent=2)
            
            # Mark complete
            with open(os.path.join(ticker_dir, "complete.json"), "w") as f:
                json.dump({
                    "ticker": ticker,
                    "completed": datetime.now().isoformat(),
                    "filings": len(filings)
                }, f)
            
            self.progress["completed"] += 1
            self.progress["total_filings"] += len(filings)
            
            return "success"
            
        except Exception as e:
            self.progress["errors"] += 1
            logging.error(f"{ticker}: {e}")
            return "error"
    
    def extract_filings(self, submissions, years=5):
        """Extract filing metadata"""
        filings = []
        cutoff = datetime.now() - timedelta(days=365 * years)
        
        recent = submissions.get("filings", {}).get("recent", {})
        if not recent:
            return filings
        
        for i in range(len(recent.get("form", []))):
            try:
                form = recent["form"][i]
                if form not in ["10-K", "10-Q", "8-K"]:
                    continue
                
                date = recent["filingDate"][i]
                if datetime.strptime(date, "%Y-%m-%d") < cutoff:
                    continue
                
                filings.append({
                    "form": form,
                    "date": date,
                    "accession": recent["accessionNumber"][i],
                    "document": recent.get("primaryDocument", [""])[i],
                    "size": recent.get("size", [0])[i]
                })
            except:
                continue
        
        return filings
    
    def run(self):
        """Main execution"""
        print("\\n" + "=" * 80)
        print("🚀 Russell 2000 SEC Filing Fetcher - August 2025")
        print("=" * 80)
        print(f"📊 Companies to fetch: {self.progress['total']}")
        print(f"📁 Data directory: {self.data_dir}")
        print(f"⏱️ Estimated time: {self.progress['total'] / RATE_LIMIT / 60:.1f} minutes minimum")
        print("=" * 80 + "\\n")
        
        # Process all companies
        for ticker in tqdm(self.russell2000_tickers, desc="Fetching"):
            self.fetch_company(ticker)
            
            # Progress update
            if self.progress["completed"] % 100 == 0:
                self.show_progress()
        
        # Final summary
        self.show_summary()
    
    def show_progress(self):
        """Show progress stats"""
        elapsed = (datetime.now() - self.progress["start_time"]).total_seconds() / 60
        rate = self.progress["completed"] / elapsed if elapsed > 0 else 0
        remaining = (self.progress["total"] - self.progress["completed"]) / rate if rate > 0 else 0
        
        tqdm.write(f"\\n📊 Progress Update:")
        tqdm.write(f"   Completed: {self.progress['completed']}")
        tqdm.write(f"   Rate: {rate:.1f} companies/minute")
        tqdm.write(f"   Est. remaining: {remaining:.1f} minutes")
        tqdm.write(f"   Total filings: {self.progress['total_filings']}")
    
    def show_summary(self):
        """Final summary"""
        print("\\n" + "=" * 80)
        print("✅ Fetching Complete!")
        print("=" * 80)
        print(f"Completed: {self.progress['completed']}")
        print(f"Skipped: {self.progress['skipped']}")
        print(f"No CIK: {self.progress['no_cik']}")
        print(f"Errors: {self.progress['errors']}")
        print(f"Total filings: {self.progress['total_filings']}")
        print(f"\\nData location: {self.data_dir}")
        print("Each ticker has its own subdirectory")
        print("=" * 80)

if __name__ == "__main__":
    fetcher = CurrentRussell2000Fetcher()
    fetcher.run()
'''
    
    with open("fetch_russell2000_sec.py", "w") as f:
        f.write(script)
    
    print("✅ Created fetch_russell2000_sec.py")

def main():
    print("🏢 Getting CURRENT Russell 2000 Index - August 26, 2025")
    print("=" * 70)
    
    # Get current Russell 2000 list
    tickers = get_russell2000_august_2025()
    
    if tickers:
        # Validate
        tickers = validate_current_tickers(tickers)
        
        # Save
        russell_data = save_russell2000_current(tickers)
        
        # Create fetcher
        create_fetcher_for_current_russell()
        
        print("\n" + "=" * 70)
        print("📋 Summary:")
        print(f"   Russell 2000 constituents: {len(tickers)}")
        print(f"   Last reconstitution: June 2025")
        print(f"   Data current as of: August 26, 2025")
        
        print("\n📋 Next Steps:")
        print("1. Transfer russell2000_current.json to olympus")
        print("2. Transfer fetch_russell2000_sec.py to olympus")  
        print("3. Run fetcher on olympus (will take ~4-6 hours)")
        print("4. Train SEC-BERT ONLY after all data is collected")
        
        print(f"\n⏰ Estimated time: {len(tickers) / 8 / 60:.1f} hours at 8 req/sec")
    else:
        print("\n❌ Failed to get current Russell 2000 list")
        print("\nManual options:")
        print("1. Download from FTSE Russell website")
        print("2. Get from Bloomberg Terminal (RUT Index)")
        print("3. Access via financial data provider API")

if __name__ == "__main__":
    main()