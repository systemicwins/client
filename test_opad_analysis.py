#!/usr/bin/env python3
"""
Test OPAD SEC filing analysis to debug why it's returning 50% scores
"""

import asyncio
import aiohttp
from datetime import datetime
import json

async def fetch_opad_filings():
    """Fetch OPAD SEC filings from FMP API"""
    symbol = "OPAD"
    api_key = "apikey-2"  # Replace with actual key
    
    url = f"https://financialmodelingprep.com/api/v3/sec_filings/{symbol}?limit=20&apikey={api_key}"
    
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            if response.status == 200:
                filings = await response.json()
                print(f"Found {len(filings)} filings for {symbol}")
                return filings
            else:
                print(f"Failed to fetch filings: {response.status}")
                return []

async def test_filing_content(filing):
    """Test if we can actually fetch and parse filing content"""
    form_type = filing.get('type', 'Unknown')
    filing_date = filing.get('fillingDate', 'Unknown')
    final_url = filing.get('finalLink')
    regular_url = filing.get('link')
    
    url = final_url or regular_url
    if not url:
        return f"{form_type} ({filing_date}): No URL available"
    
    print(f"\nTesting {form_type} filed on {filing_date}")
    print(f"URL: {url[:100]}...")
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as response:
                if response.status == 200:
                    content = await response.text()
                    print(f"✅ Fetched {len(content)} characters")
                    
                    # Check what kind of content we got
                    content_lower = content[:5000].lower()
                    
                    # Check for key sections
                    has_mda = "management's discussion" in content_lower or "item 7" in content_lower or "item 2" in content_lower
                    has_risk = "risk factor" in content_lower or "item 1a" in content_lower
                    has_financial = "financial statement" in content_lower or "item 8" in content_lower
                    has_business = "business" in content_lower or "item 1" in content_lower
                    
                    print(f"  MD&A section: {'✅' if has_mda else '❌'}")
                    print(f"  Risk section: {'✅' if has_risk else '❌'}")
                    print(f"  Financial section: {'✅' if has_financial else '❌'}")
                    print(f"  Business section: {'✅' if has_business else '❌'}")
                    
                    # Sample some actual text
                    if has_mda:
                        mda_idx = content_lower.find("management's discussion")
                        if mda_idx == -1:
                            mda_idx = content_lower.find("item 7")
                        if mda_idx == -1:
                            mda_idx = content_lower.find("item 2")
                        
                        if mda_idx > -1:
                            sample = content[mda_idx:mda_idx+500].replace('\n', ' ').replace('\r', ' ')
                            print(f"  MD&A sample: {sample[:200]}...")
                    
                    return f"{form_type}: Successfully fetched with {'some' if (has_mda or has_risk) else 'no'} parseable sections"
                else:
                    return f"{form_type}: HTTP {response.status}"
        except asyncio.TimeoutError:
            return f"{form_type}: Timeout"
        except Exception as e:
            return f"{form_type}: Error - {str(e)}"

async def main():
    print("Testing OPAD SEC Filing Analysis")
    print("=" * 50)
    
    # Fetch filings
    filings = await fetch_opad_filings()
    
    if not filings:
        print("No filings found!")
        return
    
    # Test content extraction for each filing type
    filing_types = {}
    for filing in filings[:10]:  # Test first 10
        form_type = filing.get('type', 'Unknown')
        if form_type not in filing_types:
            filing_types[form_type] = filing
    
    print(f"\nFound filing types: {list(filing_types.keys())}")
    
    # Test each unique filing type
    results = []
    for form_type, filing in filing_types.items():
        result = await test_filing_content(filing)
        results.append(result)
    
    print("\n" + "=" * 50)
    print("Summary:")
    for result in results:
        print(f"  {result}")
    
    # Check if we have substantive content
    print("\n" + "=" * 50)
    print("Analysis:")
    
    # Count how many filings have parseable content
    parseable_count = sum(1 for r in results if "Successfully fetched with some" in r)
    
    if parseable_count == 0:
        print("❌ No filings have parseable MD&A or Risk sections")
        print("   This would result in 50% neutral scores")
    else:
        print(f"✅ {parseable_count} filing types have parseable sections")
        print("   These should produce non-50% scores if SEC-BERT runs properly")

if __name__ == "__main__":
    asyncio.run(main())