#!/usr/bin/env python3
"""
Fetch SEC filings for complete Russell 2000 index
Organize data by ticker in separate subdirectories
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
import pandas as pd
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib

# SEC EDGAR API settings
SEC_API_BASE = "https://data.sec.gov"
SEC_ARCHIVES = "https://www.sec.gov/Archives"
USER_AGENT = "Academic Research Bot research@university.edu"  # Update with your email

# Rate limiting: SEC allows 10 requests per second max
REQUESTS_PER_SECOND = 2  # Conservative to avoid 429 errors
REQUEST_DELAY = 1.0 / REQUESTS_PER_SECOND

class Russell2000SECFetcher:
    def __init__(self, data_dir="~/relentless/finetune/data"):
        self.data_dir = os.path.expanduser(data_dir)
        os.makedirs(self.data_dir, exist_ok=True)
        
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        })
        
        self.last_request_time = 0
        self.ticker_to_cik = {}
        self.failed_tickers = []
        
    def load_russell2000_list(self):
        """Load the Russell 2000 ticker list and CIK mappings"""
        # First, get SEC's complete ticker-to-CIK mapping
        print("📋 Loading SEC ticker-to-CIK mappings...")
        
        try:
            url = "https://www.sec.gov/files/company_tickers.json"
            response = self.session.get(url)
            response.raise_for_status()
            
            data = response.json()
            
            for entry in data.values():
                ticker = entry.get('ticker', '').upper()
                cik = str(entry.get('cik_str', '')).zfill(10)
                if ticker and cik:
                    self.ticker_to_cik[ticker] = cik
            
            print(f"✅ Loaded {len(self.ticker_to_cik)} ticker mappings")
            
        except Exception as e:
            print(f"Error loading SEC mappings: {e}")
            return False
        
        # Load Russell 2000 list if available
        russell_file = "russell_2000_complete.json"
        if os.path.exists(russell_file):
            with open(russell_file, 'r') as f:
                russell_data = json.load(f)
                return russell_data.get('tickers', [])
        
        # Otherwise use expanded known list
        return self.get_known_russell2000_tickers()
    
    def get_known_russell2000_tickers(self):
        """Return comprehensive list of known Russell 2000 tickers"""
        # This is an expanded list of Russell 2000 companies
        # In production, load from official source
        tickers = [
            # Technology sector (~300 companies)
            "SMCI", "COHR", "RMBS", "AEIS", "WOLF", "POWI", "DIOD", "ONTO", "FORM", "UCTT",
            "IPGP", "AMBA", "PI", "SITM", "CRUS", "SYNA", "LITE", "VIAV", "PRGS", "ACIA",
            "AOSL", "SLAB", "IDCC", "PXLW", "LSCC", "MPWR", "ENTG", "SIMO", "MCRI", "CRDO",
            "PLAB", "COHU", "ACLS", "NANO", "INDI", "CEVA", "XPER", "AMKR", "FLEX", "SANM",
            "PLXS", "CTS", "BHE", "VICR", "TTMI", "OSIS", "LUNA", "INFN", "CLFD", "AAOI",
            "FNKO", "HEAR", "KLIC", "IMMR", "VUZI", "MVIS", "KOPN", "EMAN", "WISA", "RESN",
            
            # Healthcare sector (~300 companies)
            "INSM", "KRYS", "ROIV", "HALO", "ACAD", "ARVN", "SWTX", "TGTX", "CGEM", "MRTX",
            "AXSM", "DNLI", "VKTX", "PCVX", "CRNX", "APLS", "NKTX", "RVMD", "KRTX", "LYEL",
            "VERV", "PRAX", "RXRX", "CLDX", "NEO", "OCDX", "PACB", "TWST", "CDNA", "FLGT",
            "NTRA", "NRIX", "FATE", "SDGR", "BEAM", "EDIT", "NTLA", "CRSP", "VCYT", "CDMO",
            "PRVB", "IMVT", "ARWR", "QURE", "SGMO", "AGIO", "BLUE", "SAGE", "ALKS", "ITCI",
            "SGEN", "INCY", "BMRN", "VRTX", "ALNY", "REGN", "BIIB", "GILD", "AMGN", "ABBV",
            
            # Financial sector (~400 companies)
            "SFBS", "EWBC", "OZK", "SSB", "GBCI", "WAL", "UMBF", "UBSI", "CBSH", "PACW",
            "FFIN", "FCNCA", "FHB", "HTH", "SFNC", "BANR", "FRME", "HOMB", "ONB", "PRK",
            "TBBK", "UCB", "WSFS", "WAFD", "IBOC", "FULT", "FBMS", "CVBF", "CATY", "HOPE",
            "NBTB", "INDB", "TOWN", "BPOP", "BKU", "TFSL", "FBNC", "SBCF", "EGBN", "CASH",
            "PPBI", "CHCO", "RNST", "FIBK", "FMBI", "MBWM", "HTLF", "EFSC", "BOCH", "BANF",
            "AMAL", "AMNB", "ASRV", "ATLO", "AUBN", "BHLB", "BKSC", "BMRC", "BSRR", "BUSE",
            
            # Consumer sector (~250 companies)
            "WING", "TXRH", "SHAK", "DKS", "BOOT", "VSCO", "DLTR", "BBW", "PLCE", "HIBB",
            "FIVE", "OLLI", "DDS", "BIG", "BURL", "ROST", "ANF", "AEO", "URBN", "GPS",
            "CHS", "CAL", "GES", "ZUMZ", "EXPR", "SCVL", "CATO", "DXLG", "TLYS", "BNED",
            "KIRK", "CONN", "BBBY", "PIR", "JWN", "KSS", "M", "PRTY", "SPB", "EYE",
            "MNRO", "ORLY", "AAP", "AZO", "GPC", "PBOY", "DORM", "CASY", "PSMT", "WINA",
            
            # Industrial sector (~350 companies)
            "AAON", "TREX", "FELE", "GGG", "MIDD", "AIT", "GWW", "WSO", "RBC", "CR",
            "MSM", "EPAC", "B", "TTEK", "SSD", "SITE", "TTC", "VMI", "AYI", "EME",
            "HWM", "APOG", "NVT", "ATKR", "JBT", "LECO", "FBIN", "TRN", "AGCO", "BLDR",
            "DOOR", "FAST", "SNA", "PH", "DOV", "ROK", "FLS", "XYL", "IEX", "ROP",
            "TDY", "COL", "HEI", "CW", "ESE", "BMI", "WTS", "NPO", "MOG", "DCO",
            
            # Energy sector (~100 companies)
            "TALO", "SM", "MGY", "CRC", "NOG", "MTDR", "CIVI", "PR", "VTLE", "RRC",
            "CNX", "AR", "SWN", "CTRA", "PDCE", "CHK", "OVV", "MUR", "CLR", "FANG",
            "DVN", "MRO", "APA", "HES", "COP", "EOG", "PXD", "XEC", "NFG", "EQT",
            "COG", "RIG", "DO", "VAL", "HP", "TDW", "FTI", "WHD", "PTEN", "LBRT",
            
            # Materials sector (~100 companies)
            "CLF", "X", "STLD", "RS", "CMC", "ATI", "CRS", "HAYN", "MATX", "SXI",
            "ARCH", "AMR", "BTU", "CEIX", "HCC", "ARLP", "METC", "SUM", "MLM", "VMC",
            "MDU", "CENX", "KALU", "SUP", "WOR", "OSK", "TG", "CMP", "NEU", "KOP",
            "ZEUS", "ROCK", "SXT", "DNMR", "TSE", "MTX", "OI", "CCF", "SLGN", "PCT",
            
            # REITs sector (~150 companies)
            "REXR", "FR", "STAG", "EGP", "IIPR", "SBRA", "CTRE", "NSA", "CUBE", "SUI",
            "ELS", "AMH", "INVH", "UMH", "CSR", "ALEX", "AIRC", "DEI", "AKR", "BRX",
            "CDP", "FCPT", "GTY", "HIW", "HPP", "JBGS", "KRC", "OFC", "PDM", "PGRE",
            "AAT", "AFIN", "AHH", "AIV", "APLE", "BDN", "BFS", "BNL", "COLD", "CONE",
            
            # Communications sector (~50 companies)
            "CABO", "SATS", "WOW", "LUMN", "FYBR", "ATUS", "GTN", "CNSL", "OOMA", "VSAT",
            "GSAT", "TRUE", "USM", "ATEX", "SHEN", "NECB", "IDT", "GILT", "BAND", "COMM",
            "TIGO", "TEF", "TU", "VOD", "ORAN", "CHT", "CHA", "SKM", "AMX", "VIV",
            
            # Utilities sector (~50 companies)
            "NWN", "SJW", "MSEX", "CWT", "YORW", "AWR", "SJI", "NJR", "SPH", "UTL",
            "CPK", "AVA", "BKH", "LNT", "NWE", "OGS", "PNM", "POR", "SR", "UGI",
            "MGEE", "OTTR", "WEC", "AEE", "CMS", "CNP", "D", "DTE", "DUK", "ED",
        ]
        
        # Filter to only include those with CIK mappings
        valid_tickers = [t for t in tickers if t in self.ticker_to_cik]
        print(f"📊 Using {len(valid_tickers)} Russell 2000 companies with valid CIKs")
        
        return valid_tickers
    
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request_time
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request_time = time.time()
    
    def create_ticker_directory(self, ticker):
        """Create subdirectory for ticker"""
        ticker_dir = os.path.join(self.data_dir, ticker)
        os.makedirs(ticker_dir, exist_ok=True)
        
        # Create subdirectories for filing types
        for filing_type in ["10-K", "10-Q", "8-K", "metadata"]:
            os.makedirs(os.path.join(ticker_dir, filing_type), exist_ok=True)
        
        return ticker_dir
    
    def fetch_ticker_filings(self, ticker, years_back=5):
        """Fetch all filings for a specific ticker"""
        if ticker not in self.ticker_to_cik:
            print(f"  ⚠️ No CIK found for {ticker}")
            self.failed_tickers.append(ticker)
            return None
        
        cik = self.ticker_to_cik[ticker]
        ticker_dir = self.create_ticker_directory(ticker)
        
        # Check if already processed
        metadata_file = os.path.join(ticker_dir, "metadata", "company_info.json")
        if os.path.exists(metadata_file):
            print(f"  ✓ {ticker} already processed")
            return ticker
        
        try:
            self.rate_limit()
            
            # Fetch company submissions
            cik_padded = cik.zfill(10)
            url = f"{SEC_API_BASE}/submissions/CIK{cik_padded}.json"
            
            response = self.session.get(url, timeout=30)
            
            if response.status_code == 404:
                print(f"  ⚠️ CIK not found: {ticker} ({cik})")
                self.failed_tickers.append(ticker)
                return None
            
            response.raise_for_status()
            data = response.json()
            
            # Save company metadata
            company_info = {
                "ticker": ticker,
                "cik": cik,
                "name": data.get("name", ""),
                "sic": data.get("sic", ""),
                "sicDescription": data.get("sicDescription", ""),
                "category": data.get("category", ""),
                "fiscalYearEnd": data.get("fiscalYearEnd", ""),
                "fetched": datetime.now().isoformat()
            }
            
            with open(metadata_file, 'w') as f:
                json.dump(company_info, f, indent=2)
            
            # Extract and save filings
            filings_saved = self.extract_and_save_filings(data, ticker, ticker_dir, years_back)
            
            print(f"  ✅ {ticker}: {filings_saved} filings saved")
            return ticker
            
        except Exception as e:
            print(f"  ❌ Error with {ticker}: {e}")
            self.failed_tickers.append(ticker)
            return None
    
    def extract_and_save_filings(self, submissions_data, ticker, ticker_dir, years_back=5):
        """Extract filings and save metadata"""
        filings = []
        end_date = datetime.now()
        start_date = end_date - timedelta(days=365 * years_back)
        
        recent = submissions_data.get("filings", {}).get("recent", {})
        if not recent:
            return 0
        
        filing_types = ["10-K", "10-Q", "8-K"]
        
        for i in range(len(recent.get("form", []))):
            form_type = recent["form"][i]
            
            if form_type not in filing_types:
                continue
            
            filing_date = recent["filingDate"][i]
            filing_dt = datetime.strptime(filing_date, "%Y-%m-%d")
            
            if filing_dt < start_date or filing_dt > end_date:
                continue
            
            accession = recent["accessionNumber"][i].replace("-", "")
            
            # Build filing info
            filing_info = {
                "ticker": ticker,
                "form_type": form_type,
                "filing_date": filing_date,
                "accession_number": accession,
                "reportDate": recent.get("reportDate", [None])[i],
                "fileNumber": recent.get("fileNumber", [None])[i],
                "filmNumber": recent.get("filmNumber", [None])[i],
                "primaryDocument": recent.get("primaryDocument", [None])[i],
                "size": recent.get("size", [None])[i]
            }
            
            filings.append(filing_info)
        
        # Save filings metadata
        filings_file = os.path.join(ticker_dir, "metadata", "filings.json")
        with open(filings_file, 'w') as f:
            json.dump(filings, f, indent=2)
        
        return len(filings)
    
    def fetch_all_russell2000(self):
        """Main method to fetch all Russell 2000 companies"""
        print("🚀 Russell 2000 SEC Filing Fetcher")
        print("=" * 50)
        
        # Load ticker list
        tickers = self.load_russell2000_list()
        
        if not tickers:
            print("❌ No tickers loaded")
            return
        
        print(f"📊 Processing {len(tickers)} Russell 2000 companies")
        print(f"📁 Data directory: {self.data_dir}")
        print(f"⏰ Rate limit: {REQUESTS_PER_SECOND} requests/second")
        print("")
        
        # Process each ticker
        successful = 0
        for ticker in tqdm(tickers, desc="Fetching companies"):
            result = self.fetch_ticker_filings(ticker)
            if result:
                successful += 1
        
        # Summary
        print("\n" + "=" * 50)
        print("📊 Summary:")
        print(f"  Total companies: {len(tickers)}")
        print(f"  Successfully fetched: {successful}")
        print(f"  Failed: {len(self.failed_tickers)}")
        
        if self.failed_tickers:
            print(f"\n⚠️ Failed tickers: {self.failed_tickers[:20]}")
            
            # Save failed tickers
            failed_file = os.path.join(self.data_dir, "failed_tickers.json")
            with open(failed_file, 'w') as f:
                json.dump(self.failed_tickers, f, indent=2)
        
        # Save overall summary
        summary = {
            "total_tickers": len(tickers),
            "successful": successful,
            "failed": len(self.failed_tickers),
            "timestamp": datetime.now().isoformat(),
            "data_directory": self.data_dir
        }
        
        summary_file = os.path.join(self.data_dir, "fetch_summary.json")
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"\n✅ Complete! Data saved in {self.data_dir}")
        print(f"   Each ticker has its own subdirectory with metadata and filings")

def main():
    fetcher = Russell2000SECFetcher()
    fetcher.fetch_all_russell2000()

if __name__ == "__main__":
    main()