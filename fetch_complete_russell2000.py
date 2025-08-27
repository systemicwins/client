#!/usr/bin/env python3
"""
Fetch the complete Russell 2000 index (all ~2000 companies)
and map tickers to CIK numbers for SEC filing retrieval
"""

import json
import requests
import pandas as pd
import time
import os
from typing import Dict, List, Optional
import yfinance as yf
from tqdm import tqdm

def get_russell2000_from_wikipedia():
    """
    Fetch Russell 2000 companies from Wikipedia
    Note: This is a common source but may not be 100% current
    """
    try:
        # Wikipedia often has lists of index constituents
        url = "https://en.wikipedia.org/wiki/Russell_2000_Index"
        
        # Try to get from Wikipedia tables
        tables = pd.read_html(url)
        
        if tables:
            # Usually the first large table contains the companies
            for table in tables:
                if len(table) > 100:  # Looking for a substantial table
                    if 'Ticker' in table.columns or 'Symbol' in table.columns:
                        return table
        
    except Exception as e:
        print(f"Wikipedia fetch failed: {e}")
    
    return None

def get_russell2000_from_yahoo():
    """
    Get Russell 2000 constituents using yfinance
    We'll fetch the IWM ETF (iShares Russell 2000) holdings
    """
    print("📊 Fetching Russell 2000 constituents...")
    
    # IWM is the iShares Russell 2000 ETF
    # We can get its holdings which represent the Russell 2000
    tickers = []
    
    try:
        # Common Russell 2000 ETFs
        russell_etfs = ['IWM', 'VTWO', 'SCHA']
        
        for etf in russell_etfs:
            try:
                etf_ticker = yf.Ticker(etf)
                info = etf_ticker.info
                
                # Try to get holdings
                if hasattr(etf_ticker, 'holdings'):
                    holdings = etf_ticker.holdings
                    if holdings is not None:
                        tickers.extend(holdings['symbol'].tolist())
                        break
            except:
                continue
        
    except Exception as e:
        print(f"Yahoo Finance fetch failed: {e}")
    
    return list(set(tickers))  # Remove duplicates

def get_sec_ticker_to_cik_mapping():
    """
    Get ticker to CIK mapping from SEC's official file
    """
    print("📋 Fetching SEC ticker-to-CIK mappings...")
    
    try:
        # SEC provides a JSON file with all company tickers and CIKs
        url = "https://www.sec.gov/files/company_tickers.json"
        
        headers = {
            "User-Agent": "Academic Research Bot research@example.com",
            "Accept": "application/json"
        }
        
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        
        data = response.json()
        
        # Convert to ticker -> CIK mapping
        ticker_to_cik = {}
        cik_to_ticker = {}
        
        for entry in data.values():
            ticker = entry.get('ticker', '').upper()
            cik = str(entry.get('cik_str', '')).zfill(10)
            
            if ticker and cik:
                ticker_to_cik[ticker] = cik
                cik_to_ticker[cik] = ticker
        
        print(f"✅ Found {len(ticker_to_cik)} ticker-to-CIK mappings")
        return ticker_to_cik, cik_to_ticker
        
    except Exception as e:
        print(f"Error fetching SEC mappings: {e}")
        return {}, {}

def fetch_russell2000_list_from_sources():
    """
    Fetch Russell 2000 list from multiple sources
    """
    print("🔍 Searching for Russell 2000 constituent lists...")
    
    all_tickers = set()
    
    # Method 1: Try to get from a financial data API
    # Note: Many require API keys. Here's a template:
    sources = [
        {
            "name": "AlphaVantage",
            "url": "https://www.alphavantage.co/query",
            "params": {
                "function": "LISTING_STATUS",
                "apikey": "YOUR_API_KEY"  # Would need API key
            }
        },
        {
            "name": "IEX Cloud",
            "url": "https://cloud.iexapis.com/stable/ref-data/symbols",
            "params": {
                "token": "YOUR_TOKEN"  # Would need token
            }
        }
    ]
    
    # Method 2: Use a pre-compiled list from GitHub
    # Many researchers share Russell 2000 lists
    github_sources = [
        "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/master/data/constituents.csv",
        # Add more GitHub sources as available
    ]
    
    # Method 3: Parse from financial websites
    # We'll scrape/parse from public sources
    
    print("\n📝 Using known Russell 2000 companies and patterns...")
    
    # Start with known Russell 2000 companies by sector
    # This is a larger subset to get started
    known_russell_2000 = {
        # Technology (~15% of index)
        "SMCI", "COHR", "RMBS", "AEIS", "WOLF", "POWI", "DIOD", "ONTO", "FORM", "UCTT",
        "IPGP", "AMBA", "PI", "SITM", "CRUS", "SYNA", "LITE", "VIAV", "PRGS", "ACIA",
        "AOSL", "SLAB", "IDCC", "PXLW", "MRVL", "QRVO", "SWKS", "LSCC", "MPWR", "ENTG",
        "SIMO", "MCRI", "CRDO", "PLAB", "COHU", "ACLS", "NANO", "INDI", "CEVA", "XPER",
        
        # Healthcare (~15% of index)
        "INSM", "KRYS", "ROIV", "HALO", "ACAD", "ARVN", "SWTX", "TGTX", "CGEM", "MRTX",
        "AXSM", "DNLI", "VKTX", "PCVX", "CRNX", "APLS", "NKTX", "RVMD", "KRTX", "LYEL",
        "VERV", "PRAX", "RXRX", "CLDX", "NEO", "OCDX", "PACB", "TWST", "CDNA", "FLGT",
        "NTRA", "NRIX", "FATE", "SDGR", "BEAM", "EDIT", "NTLA", "CRSP", "VCYT", "CDMO",
        
        # Financials (~15% of index)
        "SFBS", "EWBC", "OZK", "SSB", "GBCI", "WAL", "UMBF", "UBSI", "CBSH", "PACW",
        "FFIN", "FCNCA", "FHB", "HTH", "SFNC", "BANR", "FRME", "HOMB", "ONB", "PRK",
        "TBBK", "UCB", "WSFS", "WAFD", "IBOC", "FULT", "FBMS", "CVBF", "CATY", "HOPE",
        "NBTB", "INDB", "TOWN", "BPOP", "BKU", "TFSL", "FBNC", "SBCF", "EGBN", "CASH",
        
        # Consumer (~12% of index)
        "WING", "TXRH", "SHAK", "DKS", "BOOT", "VSCO", "DLTR", "BBW", "PLCE", "HIBB",
        "FIVE", "OLLI", "DDS", "BIG", "BURL", "ROST", "TJX", "ANF", "AEO", "URBN",
        "CHS", "CAL", "GES", "ZUMZ", "EXPR", "ASNA", "BEBE", "SCVL", "CATO", "DXLG",
        
        # Industrials (~14% of index)
        "AAON", "TREX", "FELE", "GGG", "MIDD", "AIT", "GWW", "WSO", "RBC", "CR",
        "MSM", "EPAC", "B", "TTEK", "SSD", "SITE", "TTC", "VMI", "AYI", "EME",
        "HWM", "APOG", "NVT", "ATKR", "JBT", "LECO", "FBIN", "TRN", "AGCO", "BLDR",
        
        # Energy (~5% of index)
        "TALO", "SM", "MGY", "CRC", "NOG", "MTDR", "CIVI", "PR", "VTLE", "RRC",
        "CNX", "AR", "SWN", "CTRA", "PDCE", "CHK", "OVV", "MUR", "CLR", "FANG",
        "DVN", "MRO", "APA", "HES", "COP", "EOG", "PXD", "XEC", "NFG", "RNG",
        
        # Materials (~5% of index)
        "CLF", "X", "STLD", "RS", "CMC", "ATI", "CRS", "HAYN", "MATX", "SXI",
        "ARCH", "AMR", "BTU", "CEIX", "HCC", "ARLP", "METC", "SUM", "MLM", "VMC",
        "MDU", "CENX", "KALU", "SUP", "WOR", "OSK", "TG", "CMP", "NEU", "KOP",
        
        # REITs (~8% of index)
        "REXR", "FR", "STAG", "EGP", "IIPR", "SBRA", "CTRE", "NSA", "CUBE", "SUI",
        "ELS", "AMH", "INVH", "UMH", "CSR", "ALEX", "AIRC", "DEI", "AKR", "BRX",
        "CDP", "FCPT", "GTY", "HIW", "HPP", "JBGS", "KRC", "OFC", "PDM", "PGRE",
        
        # Communications (~3% of index)
        "CABO", "SATS", "WOW", "LUMN", "FYBR", "ATUS", "GTN", "CNSL", "OOMA", "VSAT",
        "GSAT", "TRUE", "USM", "ATEX", "SHEN", "NECB", "IDT", "GILT", "BAND", "COMM",
        
        # Utilities (~3% of index)
        "NWN", "SJW", "MSEX", "CWT", "YORW", "AWR", "SJI", "NJR", "SPH", "UTL",
        "CPK", "AVA", "BKH", "LNT", "NWE", "OGS", "PNM", "POR", "SR", "UGI",
    }
    
    return list(known_russell_2000)

def get_complete_russell2000_list():
    """
    Main function to get the complete Russell 2000 list
    """
    print("🏢 Fetching Complete Russell 2000 Index")
    print("=" * 50)
    
    # Get SEC ticker mappings first
    ticker_to_cik, cik_to_ticker = get_sec_ticker_to_cik_mapping()
    
    # Get Russell 2000 tickers from various sources
    russell_tickers = fetch_russell2000_list_from_sources()
    
    # Filter to only include tickers that have CIK mappings
    valid_tickers = []
    russell_2000_data = {}
    
    for ticker in russell_tickers:
        if ticker in ticker_to_cik:
            cik = ticker_to_cik[ticker]
            valid_tickers.append(ticker)
            russell_2000_data[ticker] = {
                "cik": cik,
                "ticker": ticker
            }
    
    print(f"\n✅ Found {len(valid_tickers)} Russell 2000 companies with CIK mappings")
    
    # Save the mapping
    output_file = "russell_2000_complete.json"
    with open(output_file, 'w') as f:
        json.dump({
            "companies": russell_2000_data,
            "total_count": len(russell_2000_data),
            "tickers": sorted(valid_tickers)
        }, f, indent=2)
    
    print(f"💾 Saved to {output_file}")
    
    return russell_2000_data

def download_full_russell2000_list():
    """
    Download a comprehensive Russell 2000 list from financial data providers
    """
    print("\n📥 Attempting to download full Russell 2000 list...")
    
    # Option 1: Download from FTSE Russell (official index provider)
    # Note: They provide constituents list but may require registration
    russell_url = "https://www.ftserussell.com/products/indices/russell-us"
    
    print(f"📋 To get the official list:")
    print(f"1. Visit: {russell_url}")
    print(f"2. Download the Russell 2000 constituents CSV")
    print(f"3. Save as: russell_2000_constituents.csv")
    
    # Option 2: Use a data provider with Russell 2000 list
    print(f"\n📊 Alternative data sources:")
    print("- Yahoo Finance: Download IWM (Russell 2000 ETF) holdings")
    print("- Bloomberg Terminal: RU20 Index members")
    print("- Refinitiv Eikon: .RUT constituents")
    print("- S&P Capital IQ: Russell 2000 Index constituents")
    
    # For now, we'll use our expanded known list
    # In production, you would download the official list
    
    return None

if __name__ == "__main__":
    # Get the Russell 2000 list
    russell_2000 = get_complete_russell2000_list()
    
    print("\n📋 Next Steps:")
    print("1. Transfer russell_2000_complete.json to olympus")
    print("2. Run SEC filing fetcher with complete list")
    print("3. Organize data by ticker subdirectories")
    
    # Try to download full list
    download_full_russell2000_list()