#!/usr/bin/env python3
"""
Get the official Russell 2000 index constituents
Download from IWM ETF holdings or other official sources
"""

import json
import requests
import pandas as pd
import time
from datetime import datetime
import os

def get_iwm_holdings():
    """
    Get Russell 2000 constituents from IWM ETF (iShares Russell 2000)
    IWM is the most popular ETF tracking the Russell 2000
    """
    print("📊 Fetching Russell 2000 constituents from IWM ETF holdings...")
    
    # iShares provides CSV downloads of their ETF holdings
    # IWM = iShares Russell 2000 ETF
    iwm_holdings_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf/1467271812596.ajax?fileType=csv&fileName=IWM_holdings&dataType=fund"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "text/csv,application/csv,text/plain",
        "Referer": "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf"
    }
    
    try:
        # Download the CSV
        response = requests.get(iwm_holdings_url, headers=headers)
        
        if response.status_code == 200:
            # Save the raw CSV
            with open("iwm_holdings_raw.csv", "wb") as f:
                f.write(response.content)
            
            # Parse the CSV
            # iShares CSVs have some header rows to skip
            df = pd.read_csv("iwm_holdings_raw.csv", skiprows=9)
            
            # Get ticker column (usually 'Ticker' or 'Symbol')
            if 'Ticker' in df.columns:
                tickers = df['Ticker'].dropna().tolist()
            elif 'Symbol' in df.columns:
                tickers = df['Symbol'].dropna().tolist()
            else:
                print("Column names:", df.columns.tolist())
                tickers = []
            
            # Clean tickers
            tickers = [str(t).strip().upper() for t in tickers if pd.notna(t) and str(t).strip()]
            
            # Remove non-equity holdings (cash, derivatives)
            tickers = [t for t in tickers if not t.startswith('$') and len(t) <= 5]
            
            print(f"✅ Found {len(tickers)} Russell 2000 constituents from IWM")
            return tickers
            
        else:
            print(f"❌ Failed to download IWM holdings: {response.status_code}")
            
    except Exception as e:
        print(f"❌ Error fetching IWM holdings: {e}")
    
    return []

def get_vtwo_holdings():
    """
    Alternative: Get Russell 2000 from Vanguard Russell 2000 ETF (VTWO)
    """
    print("\n📊 Trying Vanguard Russell 2000 ETF (VTWO) as alternative...")
    
    # Vanguard provides holdings data
    vtwo_url = "https://advisors.vanguard.com/investments/products/vtwo/vanguard-russell-2000-etf/portfolio-holdings"
    
    # This would require more complex parsing of Vanguard's site
    # Placeholder for now
    return []

def download_russell_2000_list():
    """
    Download Russell 2000 constituents from multiple sources
    """
    print("🏢 Fetching Official Russell 2000 Index Constituents")
    print("=" * 60)
    
    all_tickers = set()
    
    # Method 1: IWM ETF holdings
    iwm_tickers = get_iwm_holdings()
    if iwm_tickers:
        all_tickers.update(iwm_tickers)
    
    # Method 2: Try alternative sources if needed
    if len(all_tickers) < 1800:  # Russell 2000 should have ~2000 stocks
        print(f"\n⚠️ Only found {len(all_tickers)} tickers, trying additional sources...")
        
        # Try VTWO or other sources
        vtwo_tickers = get_vtwo_holdings()
        if vtwo_tickers:
            all_tickers.update(vtwo_tickers)
    
    # Convert to sorted list
    russell_2000_tickers = sorted(list(all_tickers))
    
    print(f"\n✅ Total Russell 2000 constituents found: {len(russell_2000_tickers)}")
    
    # Save the list
    output = {
        "index": "Russell 2000",
        "date": datetime.now().isoformat(),
        "count": len(russell_2000_tickers),
        "tickers": russell_2000_tickers
    }
    
    with open("russell_2000_tickers.json", "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"💾 Saved to russell_2000_tickers.json")
    
    return russell_2000_tickers

def create_fetch_script():
    """
    Create a robust fetching script for all Russell 2000 companies
    """
    script = '''#!/usr/bin/env python3
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
        print(f"\\n🚀 Starting fetch for {len(self.tickers)} Russell 2000 companies")
        print(f"⏱️ Estimated time: {len(self.tickers) * REQUEST_DELAY / 60:.1f} minutes minimum\\n")
        
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
        print("\\n" + "=" * 60)
        print("📊 Final Summary:")
        for key, count in results.items():
            print(f"  {key}: {count}")
        
        print(f"\\n✅ Data saved in {DATA_DIR}")
        print("Each ticker has its own subdirectory with metadata and filing info")
        
        return results

if __name__ == "__main__":
    fetcher = Russell2000Fetcher()
    fetcher.fetch_all()
'''
    
    with open("fetch_russell2000_filings.py", "w") as f:
        f.write(script)
    
    print("✅ Created fetch_russell2000_filings.py")

if __name__ == "__main__":
    # Download the official Russell 2000 list
    tickers = download_russell_2000_list()
    
    # Create the fetching script
    create_fetch_script()
    
    print("\n📋 Next Steps:")
    print("1. Transfer russell_2000_tickers.json to olympus")
    print("2. Transfer fetch_russell2000_filings.py to olympus")
    print("3. Run the fetcher to get all SEC data")
    print("4. Only train after all data is collected")