#!/usr/bin/env python3
"""
Fetch actual SEC filing text for Russell 2000 companies
Downloads the full text of 10-K, 10-Q, and 8-K filings
"""

import os
import json
import requests
import time
from pathlib import Path
from datetime import datetime, timedelta
import logging
from tqdm import tqdm
import re

# Configuration
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
SEC_ARCHIVES = "https://www.sec.gov/Archives"
SEC_API = "https://data.sec.gov"
USER_AGENT = "Academic Research russell2000@research.edu"
RATE_LIMIT = 8  # requests per second
REQUEST_DELAY = 1.0 / RATE_LIMIT

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SECFilingFetcher:
    def __init__(self, data_dir=DATA_DIR):
        self.data_dir = Path(data_dir)
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/json,application/xml,*/*",
            "Accept-Encoding": "gzip, deflate",
            "Host": "www.sec.gov"
        })
        self.last_request = 0
        self.stats = {'downloaded': 0, 'skipped': 0, 'errors': 0}
    
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request = time.time()
    
    def get_filing_text(self, url):
        """Download and extract text from SEC filing"""
        try:
            self.rate_limit()
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            
            content = response.text
            
            # Remove HTML tags and scripts
            content = re.sub(r'<script[^>]*>.*?</script>', '', content, flags=re.DOTALL)
            content = re.sub(r'<style[^>]*>.*?</style>', '', content, flags=re.DOTALL)
            content = re.sub(r'<[^>]+>', ' ', content)
            
            # Clean up whitespace
            content = re.sub(r'\s+', ' ', content)
            content = content.strip()
            
            return content
        except Exception as e:
            logger.error(f"Error downloading {url}: {e}")
            return None
    
    def extract_filing_sections(self, text, filing_type):
        """Extract key sections from filing text"""
        sections = {}
        
        if filing_type == "10-K":
            # Extract key 10-K sections
            patterns = {
                'business': r'(?:Item\s+1[\.\s]+Business)(.*?)(?:Item\s+1A|Item\s+2|$)',
                'risk_factors': r'(?:Item\s+1A[\.\s]+Risk\s+Factors)(.*?)(?:Item\s+1B|Item\s+2|$)',
                'properties': r'(?:Item\s+2[\.\s]+Properties)(.*?)(?:Item\s+3|$)',
                'legal': r'(?:Item\s+3[\.\s]+Legal\s+Proceedings)(.*?)(?:Item\s+4|$)',
                'mda': r'(?:Item\s+7[\.\s]+Management.*?Discussion.*?Analysis)(.*?)(?:Item\s+7A|Item\s+8|$)',
                'financial_statements': r'(?:Item\s+8[\.\s]+Financial\s+Statements)(.*?)(?:Item\s+9|$)'
            }
        elif filing_type == "10-Q":
            patterns = {
                'financial_statements': r'(?:Part\s+I.*?Item\s+1.*?Financial\s+Statements)(.*?)(?:Item\s+2|$)',
                'mda': r'(?:Item\s+2.*?Management.*?Discussion.*?Analysis)(.*?)(?:Item\s+3|$)',
                'controls': r'(?:Item\s+4.*?Controls.*?Procedures)(.*?)(?:Part\s+II|$)',
                'legal': r'(?:Item\s+1.*?Legal\s+Proceedings)(.*?)(?:Item\s+2|$)',
                'risk_factors': r'(?:Item\s+1A.*?Risk\s+Factors)(.*?)(?:Item\s+2|$)'
            }
        else:  # 8-K
            patterns = {
                'content': r'(?:Item\s+\d+\.\d+.*?)(.*?)(?:Item\s+\d+\.\d+|SIGNATURES|$)'
            }
        
        for section_name, pattern in patterns.items():
            match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
            if match:
                section_text = match.group(1)[:5000]  # Limit section size
                sections[section_name] = section_text.strip()
        
        # If no sections found, use first part of text
        if not sections:
            sections['full_text'] = text[:10000]
        
        return sections
    
    def fetch_company_filings(self, ticker):
        """Fetch actual filing text for a company"""
        company_dir = self.data_dir / ticker
        
        if not company_dir.exists():
            return
        
        # Check if we have filings metadata
        filings_file = company_dir / "metadata" / "filings.json"
        company_file = company_dir / "metadata" / "company.json"
        
        if not filings_file.exists():
            logger.debug(f"No filings metadata for {ticker}")
            return
        
        try:
            with open(filings_file) as f:
                filings_list = json.load(f)
            
            # Get CIK from company metadata
            cik = None
            if company_file.exists():
                with open(company_file) as f:
                    company_data = json.load(f)
                    cik = company_data.get('cik', '').replace('0x', '').lstrip('0').zfill(10)
            
            if not cik:
                logger.debug(f"No CIK for {ticker}")
                return
                
        except Exception as e:
            logger.error(f"Error loading filings for {ticker}: {e}")
            return
        
        # filings_list is a list of filing objects
        if not filings_list or not isinstance(filings_list, list):
            return
        
        # Process recent filings (last 2 years)
        cutoff_date = datetime.now() - timedelta(days=730)
        
        for filing in filings_list[:50]:  # Limit to 50 most recent
            form_type = filing.get('form', '')
            
            # Only process 10-K, 10-Q, and 8-K
            if form_type not in ['10-K', '10-Q', '8-K']:
                continue
            
            try:
                filing_date = datetime.strptime(filing.get('date', ''), '%Y-%m-%d')
                if filing_date < cutoff_date:
                    continue
            except:
                continue
            
            accession = filing.get('accession', '').replace('-', '')
            primary_doc = filing.get('document', '')
            
            if not accession or not primary_doc:
                continue
            
            # Construct filing URL
            filing_url = f"{SEC_ARCHIVES}/edgar/data/{cik}/{accession}/{primary_doc}"
            
            # Create filing directory
            filing_dir = company_dir / form_type
            filing_dir.mkdir(parents=True, exist_ok=True)
            
            # Check if already downloaded
            filing_file = filing_dir / f"{filing.get('date', 'unknown')}_{accession}.json"
            if filing_file.exists():
                self.stats['skipped'] += 1
                continue
            
            # Download filing text
            logger.debug(f"Downloading {ticker} {form_type} from {filing.get('date', 'unknown')}")
            text = self.get_filing_text(filing_url)
            
            if text and len(text) > 100:
                # Extract sections
                sections = self.extract_filing_sections(text, form_type)
                
                # Save filing
                filing_data = {
                    'ticker': ticker,
                    'form_type': form_type,
                    'filing_date': filing.get('date', ''),
                    'accession_number': filing.get('accession', ''),
                    'url': filing_url,
                    'downloaded': datetime.now().isoformat(),
                    'sections': sections
                }
                
                with open(filing_file, 'w') as f:
                    json.dump(filing_data, f, indent=2)
                
                self.stats['downloaded'] += 1
                logger.info(f"Downloaded {ticker} {form_type} ({filing.get('date', '')})")
            else:
                self.stats['errors'] += 1
    
    def fetch_all_companies(self):
        """Fetch filings for all companies with metadata"""
        # Get all company directories
        company_dirs = [d for d in self.data_dir.iterdir() 
                       if d.is_dir() and d.name not in ['10-K', '10-Q', '8-K']]
        
        logger.info(f"Processing {len(company_dirs)} companies")
        
        for company_dir in tqdm(company_dirs, desc="Fetching filings"):
            ticker = company_dir.name
            
            # Check if we already have filings
            has_10k = any((company_dir / "10-K").glob("*.json")) if (company_dir / "10-K").exists() else False
            has_10q = any((company_dir / "10-Q").glob("*.json")) if (company_dir / "10-Q").exists() else False
            
            if has_10k and has_10q:
                self.stats['skipped'] += 1
                continue
            
            self.fetch_company_filings(ticker)
            
            # Log progress every 100 companies
            total_processed = self.stats['downloaded'] + self.stats['skipped'] + self.stats['errors']
            if total_processed % 100 == 0:
                logger.info(f"Progress: Downloaded={self.stats['downloaded']}, "
                          f"Skipped={self.stats['skipped']}, Errors={self.stats['errors']}")
        
        logger.info(f"\nCompleted! Downloaded={self.stats['downloaded']}, "
                   f"Skipped={self.stats['skipped']}, Errors={self.stats['errors']}")

def main():
    logger.info("="*70)
    logger.info("SEC Filing Text Fetcher for Russell 2000")
    logger.info("="*70)
    
    fetcher = SECFilingFetcher()
    
    # Test with a single company first
    logger.info("\nTesting with single company...")
    test_ticker = None
    for d in Path(DATA_DIR).iterdir():
        if d.is_dir() and d.name not in ['10-K', '10-Q', '8-K']:
            test_ticker = d.name
            break
    
    if test_ticker:
        logger.info(f"Test fetching: {test_ticker}")
        fetcher.fetch_company_filings(test_ticker)
        
        # Check if test worked
        test_dir = Path(DATA_DIR) / test_ticker / "10-K"
        if test_dir.exists() and any(test_dir.glob("*.json")):
            logger.info(f"✅ Test successful! Found filings in {test_dir}")
        else:
            logger.warning("Test fetch didn't produce files. Check connection.")
    
    # Fetch all companies
    logger.info("\nFetching all company filings...")
    fetcher.fetch_all_companies()
    
    logger.info("="*70)
    logger.info("Fetching complete!")
    logger.info(f"Total downloaded: {fetcher.stats['downloaded']}")
    logger.info(f"Total skipped: {fetcher.stats['skipped']}")
    logger.info(f"Total errors: {fetcher.stats['errors']}")
    logger.info("="*70)

if __name__ == "__main__":
    main()