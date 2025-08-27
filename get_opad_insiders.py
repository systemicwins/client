#!/usr/bin/env python3
"""
Get OPAD insider ownership from FMP insider trading endpoint
"""

import json
import requests
from datetime import datetime, timedelta

# Configuration
FMP_API_KEY = "BiNbCLiPPz7LmMkDuMAfB6Bdj0AJTMxO"
SYMBOL = "OPAD"

def get_insider_trading(symbol):
    """Get insider trading data from FMP"""
    url = f"https://financialmodelingprep.com/api/v4/insider-trading"
    params = {
        "symbol": symbol,
        "apikey": FMP_API_KEY,
        "limit": 500
    }
    
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"Error fetching insider trading: {response.status_code}")
        return []
    
    return response.json()

def get_insider_ownership(symbol):
    """Get current insider ownership from FMP"""
    url = f"https://financialmodelingprep.com/api/v4/insider-ownership-float"
    params = {
        "symbol": symbol,
        "apikey": FMP_API_KEY
    }
    
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"Error fetching insider ownership: {response.status_code}")
        return None
    
    data = response.json()
    if data:
        return data[0]
    return None

def get_institutional_holders(symbol):
    """Get institutional holders from FMP"""
    url = f"https://financialmodelingprep.com/api/v3/institutional-holder/{symbol}"
    params = {
        "apikey": FMP_API_KEY
    }
    
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"Error fetching institutional holders: {response.status_code}")
        return []
    
    return response.json()

def get_shares_outstanding(symbol):
    """Get shares outstanding from enterprise value endpoint"""
    url = f"https://financialmodelingprep.com/api/v3/enterprise-values/{symbol}"
    params = {
        "apikey": FMP_API_KEY,
        "limit": 1
    }
    
    response = requests.get(url, params=params)
    if response.status_code != 200:
        return None
    
    data = response.json()
    if data and data[0].get('numberOfShares'):
        return data[0]['numberOfShares']
    return None

def main():
    print(f"=== OPAD OWNERSHIP ANALYSIS ===\n")
    
    # Get shares outstanding
    shares_outstanding = get_shares_outstanding(SYMBOL)
    if shares_outstanding:
        print(f"Shares Outstanding: {shares_outstanding:,.0f}")
    else:
        shares_outstanding = 27_410_000  # Known value for OPAD
        print(f"Shares Outstanding (default): {shares_outstanding:,.0f}")
    
    # Get insider ownership summary
    print(f"\n1. Insider Ownership Summary:")
    ownership_data = get_insider_ownership(SYMBOL)
    if ownership_data:
        print(f"   Float: {ownership_data.get('floatShares', 0):,.0f}")
        print(f"   Outstanding: {ownership_data.get('outstandingShares', 0):,.0f}")
        print(f"   Float %: {ownership_data.get('floatPercentage', 0):.2f}%")
    
    # Get recent insider transactions
    print(f"\n2. Recent Insider Transactions:")
    insider_trades = get_insider_trading(SYMBOL)
    
    # Track insider holdings by person
    insider_holdings = {}
    
    if insider_trades:
        print(f"   Found {len(insider_trades)} insider transactions")
        
        # Group by reporting person and sum shares
        for trade in insider_trades[:50]:  # Look at most recent 50
            owner = trade.get('reportingName', 'Unknown')
            trans_type = trade.get('transactionType', '')
            shares = trade.get('securitiesTransacted', 0)
            shares_owned = trade.get('securitiesOwned', 0)
            filing_date = trade.get('filingDate', '')
            
            # Track the most recent ownership position for each insider
            if owner not in insider_holdings or filing_date > insider_holdings[owner].get('date', ''):
                insider_holdings[owner] = {
                    'shares': shares_owned,
                    'date': filing_date,
                    'title': trade.get('typeOfOwner', '')
                }
        
        # Show top insider holders
        print(f"\n   Top Insider Holdings (from Form 4 filings):")
        sorted_insiders = sorted(insider_holdings.items(), key=lambda x: x[1]['shares'], reverse=True)
        total_insider_shares = 0
        
        for owner, data in sorted_insiders[:10]:
            if data['shares'] > 0:
                print(f"   {owner[:35]:35} {data['shares']:>15,.0f} shares ({data['title'][:20]})")
                total_insider_shares += data['shares']
        
        print(f"\n   Total Insider Shares (top holders): {total_insider_shares:,.0f}")
        insider_percent = (total_insider_shares / shares_outstanding) * 100
        print(f"   Insider Ownership %: {insider_percent:.2f}%")
    
    # Get institutional holdings
    print(f"\n3. Institutional Holdings:")
    institutions = get_institutional_holders(SYMBOL)
    
    if institutions:
        print(f"   Found {len(institutions)} institutional holders")
        
        # Sum institutional holdings
        total_institutional = 0
        print(f"\n   Top Institutional Holdings:")
        
        for inst in institutions[:10]:
            holder = inst.get('holder', 'Unknown')
            shares = inst.get('shares', 0)
            change = inst.get('change', 0)
            date = inst.get('dateReported', '')
            
            if shares > 0:
                print(f"   {holder[:35]:35} {shares:>15,.0f} shares")
                total_institutional += shares
        
        print(f"\n   Total Institutional Shares: {total_institutional:,.0f}")
        inst_percent = (total_institutional / shares_outstanding) * 100
        print(f"   Institutional Ownership %: {inst_percent:.2f}%")
    else:
        # Estimate institutional ownership
        total_institutional = shares_outstanding * 0.30
        print(f"   No institutional data available - estimating at 30%")
        print(f"   Estimated Institutional Shares: {total_institutional:,.0f}")
    
    # Calculate tradeable float
    print(f"\n=== TRADEABLE FLOAT CALCULATION ===")
    print(f"Shares Outstanding:        {shares_outstanding:,.0f}")
    print(f"Insider Ownership:        -{total_insider_shares:,.0f} ({insider_percent:.1f}%)")
    print(f"Institutional Ownership:  -{total_institutional:,.0f} ({(total_institutional/shares_outstanding)*100:.1f}%)")
    print(f"----------------------------------------")
    
    tradeable_float = shares_outstanding - total_insider_shares - total_institutional
    float_percent = (tradeable_float / shares_outstanding) * 100
    
    print(f"TRADEABLE FLOAT:           {tradeable_float:,.0f} ({float_percent:.1f}%)")
    
    return {
        'shares_outstanding': shares_outstanding,
        'insider_ownership': total_insider_shares,
        'institutional_ownership': total_institutional,
        'tradeable_float': tradeable_float,
        'float_percentage': float_percent
    }

if __name__ == "__main__":
    result = main()