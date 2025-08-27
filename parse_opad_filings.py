#!/usr/bin/env python3
"""
Parse OPAD SEC filings to calculate accurate tradeable float
"""

import json
import requests
import re
from datetime import datetime, timedelta
from collections import defaultdict
import xml.etree.ElementTree as ET

# Configuration
FMP_API_KEY = "BiNbCLiPPz7LmMkDuMAfB6Bdj0AJTMxO"
SYMBOL = "OPAD"

def fetch_sec_filings(symbol, years=5):
    """Fetch SEC filings from FMP"""
    url = f"https://financialmodelingprep.com/api/v3/sec_filings/{symbol}"
    params = {
        "apikey": FMP_API_KEY,
        "limit": 500
    }
    
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"Error fetching filings: {response.status_code}")
        return []
    
    filings = response.json()
    
    # Filter for past 5 years
    cutoff_date = datetime.now() - timedelta(days=years*365)
    filtered_filings = []
    
    for filing in filings:
        try:
            filing_date = datetime.strptime(filing['fillingDate'][:10], '%Y-%m-%d')
            if filing_date >= cutoff_date:
                filtered_filings.append(filing)
        except:
            continue
    
    return filtered_filings

def parse_form4_xml(xml_content):
    """Parse Form 4 XML to extract transaction details"""
    transactions = []
    
    try:
        # Remove namespace for easier parsing
        xml_content = re.sub(r'xmlns="[^"]+"', '', xml_content)
        xml_content = re.sub(r'xmlns:[^=]+="[^"]+"', '', xml_content)
        
        root = ET.fromstring(xml_content)
        
        # Get owner information
        owner_name = root.findtext('.//rptOwnerName', default='Unknown')
        is_director = root.findtext('.//isDirector', default='0') == '1'
        is_officer = root.findtext('.//isOfficer', default='0') == '1'
        is_ten_percent = root.findtext('.//isTenPercentOwner', default='0') == '1'
        
        # Parse non-derivative transactions (common stock)
        for transaction in root.findall('.//nonDerivativeTransaction'):
            trans_date = transaction.findtext('.//transactionDate/value', default='')
            trans_code = transaction.findtext('.//transactionCoding/transactionCode', default='')
            shares = float(transaction.findtext('.//transactionAmounts/transactionShares/value', default='0'))
            price = float(transaction.findtext('.//transactionAmounts/transactionPricePerShare/value', default='0'))
            shares_after = float(transaction.findtext('.//postTransactionAmounts/sharesOwnedFollowingTransaction/value', default='0'))
            ownership_type = transaction.findtext('.//ownershipNature/directOrIndirectOwnership/value', default='D')
            
            transactions.append({
                'date': trans_date,
                'owner': owner_name,
                'code': trans_code,
                'shares': shares,
                'price': price,
                'shares_after': shares_after,
                'is_direct': ownership_type == 'D',
                'is_director': is_director,
                'is_officer': is_officer,
                'is_ten_percent': is_ten_percent
            })
        
        # Parse derivative transactions (options, warrants)
        for transaction in root.findall('.//derivativeTransaction'):
            trans_date = transaction.findtext('.//transactionDate/value', default='')
            trans_code = transaction.findtext('.//transactionCoding/transactionCode', default='')
            shares = float(transaction.findtext('.//transactionAmounts/transactionShares/value', default='0'))
            underlying_shares = float(transaction.findtext('.//underlyingSecurity/underlyingSecurityShares/value', default='0'))
            
            if underlying_shares > 0:
                transactions.append({
                    'date': trans_date,
                    'owner': owner_name,
                    'code': trans_code,
                    'shares': underlying_shares,  # Use underlying shares for derivatives
                    'price': 0,
                    'shares_after': 0,
                    'is_direct': True,
                    'is_derivative': True,
                    'is_director': is_director,
                    'is_officer': is_officer,
                    'is_ten_percent': is_ten_percent
                })
    
    except Exception as e:
        print(f"Error parsing XML: {e}")
    
    return transactions

def fetch_and_parse_filing(filing):
    """Fetch and parse individual filing"""
    form_type = filing['type']
    
    # Get the SEC EDGAR URL
    if filing.get('finalLink'):
        url = filing['finalLink']
    elif filing.get('link'):
        url = filing['link']
    else:
        return None
    
    # For Form 3 and Form 4, we need to get the XML version
    if form_type in ['3', '4', '4/A']:
        # Extract CIK and accession number from the URL
        if 'Archives/edgar/data' in url:
            parts = url.split('/')
            # URL format: https://www.sec.gov/Archives/edgar/data/{CIK}/{ACCESSION}/{FILENAME}
            for i, part in enumerate(parts):
                if part == 'data' and i+2 < len(parts):
                    cik = parts[i+1]
                    accession = parts[i+2].replace('-', '')
                    
                    # Try multiple possible XML locations
                    xml_urls = [
                        f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/primary_doc.xml",
                        f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/doc1.xml",
                        f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/form4.xml",
                        f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/{accession.replace(cik, '')}.xml"
                    ]
                    
                    for xml_url in xml_urls:
                        try:
                            response = requests.get(xml_url, timeout=10)
                            if response.status_code == 200 and '<ownershipDocument>' in response.text:
                                return parse_form4_xml(response.text)
                        except:
                            continue
    
    # Try the original URL as fallback
    try:
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            content = response.text
            
            if form_type in ['3', '4', '4/A'] and '<ownershipDocument>' in content:
                return parse_form4_xml(content)
            elif form_type in ['13F-HR', '13F-HR/A'] and '<informationTable>' in content:
                # Parse 13F for institutional holdings
                return parse_13f_xml(content)
        
    except Exception as e:
        pass  # Silently fail for individual filing fetches
    
    return None

def parse_13f_xml(xml_content):
    """Parse 13F XML to extract institutional holdings"""
    holdings = []
    
    try:
        xml_content = re.sub(r'xmlns="[^"]+"', '', xml_content)
        xml_content = re.sub(r'xmlns:[^=]+="[^"]+"', '', xml_content)
        
        root = ET.fromstring(xml_content)
        
        # Look for OPAD holdings
        for info_table in root.findall('.//infoTable'):
            issuer = info_table.findtext('.//nameOfIssuer', default='')
            cusip = info_table.findtext('.//cusip', default='')
            shares = float(info_table.findtext('.//sshPrnamt', default='0'))
            
            # Check if this is OPAD (would need CUSIP match)
            if 'OPAD' in issuer.upper() or 'OFFERPAD' in issuer.upper():
                holdings.append({
                    'issuer': issuer,
                    'shares': shares,
                    'type': '13F'
                })
    
    except Exception as e:
        print(f"Error parsing 13F: {e}")
    
    return holdings

def calculate_tradeable_float(symbol):
    """Calculate tradeable float from SEC filings"""
    
    print(f"Fetching SEC filings for {symbol}...")
    filings = fetch_sec_filings(symbol)
    print(f"Found {len(filings)} filings in the past 5 years")
    
    # Count by type
    filing_types = defaultdict(int)
    for f in filings:
        filing_types[f['type']] += 1
    
    print("\nFiling breakdown:")
    for ftype, count in sorted(filing_types.items(), key=lambda x: x[1], reverse=True):
        print(f"  {ftype}: {count}")
    
    # Get shares outstanding from FMP
    print(f"\nFetching shares outstanding...")
    ev_url = f"https://financialmodelingprep.com/api/v3/enterprise-values/{symbol}?apikey={FMP_API_KEY}&limit=1"
    response = requests.get(ev_url)
    shares_outstanding = 27410000  # Default from earlier check
    
    if response.status_code == 200:
        data = response.json()
        if data and data[0].get('numberOfShares'):
            shares_outstanding = data[0]['numberOfShares']
            print(f"Shares Outstanding: {shares_outstanding:,.0f}")
    
    # Track ownership by person/entity
    insider_holdings = defaultdict(float)  # Track by owner name
    institutional_holdings = defaultdict(float)  # Track by institution
    
    # Process Form 4 and Form 3 filings
    form4_count = 0
    form3_count = 0
    transactions_parsed = 0
    
    print(f"\nProcessing Form 3/4 filings...")
    forms_to_process = [f for f in filings if f['type'] in ['3', '4', '4/A']]
    print(f"Found {len(forms_to_process)} Form 3/4 filings to process")
    
    for i, filing in enumerate(forms_to_process[:10]):  # Process first 10 for testing
        if filing['type'] in ['4', '3', '4/A']:
            filing_date = filing.get('fillingDate', 'Unknown date')
            filing_url = filing.get('finalLink') or filing.get('link', '')
            print(f"  Processing filing {i+1}/{min(10, len(forms_to_process))}: {filing['type']} from {filing_date}")
            print(f"    URL: {filing_url[:80]}...")
            transactions = fetch_and_parse_filing(filing)
            if transactions:
                for trans in transactions:
                    owner = trans['owner']
                    code = trans['code']
                    shares = trans['shares']
                    shares_after = trans.get('shares_after', 0)
                    
                    if filing['type'] == '3':
                        # Form 3: Initial statement - set baseline
                        insider_holdings[owner] = max(insider_holdings[owner], shares_after)
                        form3_count += 1
                    elif filing['type'] == '4':
                        # Form 4: Transaction
                        if shares_after > 0:
                            # Use shares_after as the new total for this owner
                            insider_holdings[owner] = shares_after
                        elif code == 'P':  # Purchase
                            insider_holdings[owner] += shares
                        elif code == 'S':  # Sale
                            insider_holdings[owner] = max(0, insider_holdings[owner] - shares)
                        form4_count += 1
                    
                    transactions_parsed += 1
                    
                    if transactions_parsed % 10 == 0:
                        print(f"  Processed {transactions_parsed} transactions...")
    
    print(f"  Parsed {form3_count} Form 3s and {form4_count} Form 4s")
    
    # Calculate total insider ownership
    total_insider_shares = sum(max(0, shares) for shares in insider_holdings.values())
    
    # Process 13F filings for institutional ownership
    form13f_count = 0
    for filing in filings:
        if '13F' in filing['type']:
            holdings = fetch_and_parse_filing(filing)
            if holdings:
                for holding in holdings:
                    institutional_holdings['13F'] += holding['shares']
                form13f_count += 1
    
    print(f"  Parsed {form13f_count} Form 13Fs")
    
    # Calculate total institutional ownership
    total_institutional_shares = sum(institutional_holdings.values())
    
    # If we couldn't parse institutional ownership, estimate it
    if total_institutional_shares == 0:
        # Estimate 30% institutional ownership for small-cap stocks
        total_institutional_shares = shares_outstanding * 0.30
        print(f"  Estimated institutional ownership at 30%")
    
    # Calculate tradeable float
    tradeable_float = shares_outstanding - total_insider_shares - total_institutional_shares
    
    print(f"\n=== TRADEABLE FLOAT CALCULATION ===")
    print(f"Shares Outstanding:        {shares_outstanding:,.0f}")
    print(f"Insider Ownership:        -{total_insider_shares:,.0f} ({total_insider_shares/shares_outstanding*100:.1f}%)")
    print(f"Institutional Ownership:  -{total_institutional_shares:,.0f} ({total_institutional_shares/shares_outstanding*100:.1f}%)")
    print(f"----------------------------------------")
    print(f"TRADEABLE FLOAT:           {tradeable_float:,.0f} ({tradeable_float/shares_outstanding*100:.1f}%)")
    
    # Show top insider holders
    if insider_holdings:
        print(f"\nTop Insider Holdings:")
        top_insiders = sorted(insider_holdings.items(), key=lambda x: x[1], reverse=True)[:10]
        for owner, shares in top_insiders:
            if shares > 0:
                print(f"  {owner[:30]:30} {shares:>12,.0f} shares")
    
    return {
        'shares_outstanding': shares_outstanding,
        'insider_ownership': total_insider_shares,
        'institutional_ownership': total_institutional_shares,
        'tradeable_float': tradeable_float,
        'float_percentage': tradeable_float / shares_outstanding * 100
    }

if __name__ == "__main__":
    result = calculate_tradeable_float(SYMBOL)