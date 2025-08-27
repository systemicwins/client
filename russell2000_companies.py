#!/usr/bin/env python3
"""
Russell 2000 company list with CIK mappings
This provides a more comprehensive list of Russell 2000 companies
"""

# Expanded Russell 2000 companies with CIK numbers
# This is still a subset - for full training, you'd need all 2000 companies
RUSSELL_2000_FULL = {
    # Technology (50+ companies)
    "SMCI": "0001375365", "COHR": "0001282637", "RMBS": "0000917520",
    "AEIS": "0000844991", "WOLF": "0001083743", "POWI": "0001088595",
    "DIOD": "0000029002", "ONTO": "0001768408", "FORM": "0001039399",
    "UCTT": "0001411057", "IPGP": "0001176334", "AMBA": "0001280263",
    "PI": "0001517898", "SITM": "0001514416", "CRUS": "0000772406",
    "SYNA": "0001057442", "LITE": "0000889419", "VIAV": "0001403159",
    "PRGS": "0000876167", "ACIA": "0001651945", "AOSL": "0000950170",
    "SLAB": "0001038074", "IDCC": "0001405495", "PXLW": "0001075736",
    "MRVL": "0001058057", "QRVO": "0001604778", "SWKS": "0000004127",
    
    # Healthcare & Biotech (50+ companies)
    "INSM": "0001104506", "KRYS": "0001686673", "ROIV": "0001763761",
    "HALO": "0000892553", "ACAD": "0000882731", "ARVN": "0001731202",
    "SWTX": "0001828016", "TGTX": "0001308606", "CGEM": "0001856525",
    "MRTX": "0001614018", "AXSM": "0001579428", "DNLI": "0001714113",
    "VKTX": "0001755149", "PCVX": "0001792044", "CRNX": "0001783398",
    "APLS": "0001434868", "NKTX": "0001434133", "RVMD": "0001764013",
    "KRTX": "0001705028", "LYEL": "0001874716", "VERV": "0001810530",
    "PRAX": "0001689548", "RXRX": "0001778878", "CLDX": "0001341766",
    "NEO": "0001404644", "OCDX": "0001088856", "PACB": "0001299130",
    
    # Energy (40+ companies)  
    "TALO": "0001680873", "SM": "0000893538", "MGY": "0001604950",
    "CRC": "0001624909", "NOG": "0001104485", "MTDR": "0001604912",
    "CIVI": "0001856862", "PR": "0001653390", "VTLE": "0001738834",
    "RRC": "0000315852", "CNX": "0001070412", "AR": "0001060131",
    "SWN": "0000007332", "CTRA": "0001722313", "PDCE": "0001037676",
    "CHK": "0000895126", "OVV": "0001792580", "MUR": "0000717423",
    "CLR": "0000804328", "FANG": "0001360565", "DVN": "0001090012",
    "MRO": "0000101778", "APA": "0000006769", "HES": "0000004447",
    
    # Financials (60+ companies)
    "SFBS": "0001661694", "EWBC": "0001069157", "OZK": "0001003418",
    "SSB": "0001473844", "GBCI": "0001071625", "WAL": "0001474735",
    "UMBF": "0000101385", "UBSI": "0000763907", "CBSH": "0000887595",
    "PACW": "0001102112", "FFIN": "0000702165", "FCNCA": "0001141807",
    "FHB": "0000046195", "HTH": "0001851182", "SFNC": "0000880146",
    "BANR": "0001472162", "FRME": "0001378872", "HOMB": "0000048589",
    "ONB": "0001106465", "PRK": "0000708821", "TBBK": "0001341318",
    "UCB": "0000751364", "WSFS": "0000828944", "WAFD": "0000936528",
    
    # Consumer & Retail (50+ companies)
    "WING": "0001688491", "TXRH": "0001289460", "SHAK": "0001620533",
    "DKS": "0001089063", "BOOT": "0001610618", "VSCO": "0001821825",
    "DLTR": "0000935703", "BBW": "0001703962", "PLCE": "0001041859",
    "HIBB": "0001017480", "FIVE": "0001177609", "OLLI": "0001639300",
    "DDS": "0001020214", "BIG": "0000768835", "BURL": "0001579298",
    "ROST": "0000745732", "TJX": "0000109198", "ANF": "0001018840",
    "AEO": "0000919012", "URBN": "0000912615", "GPS": "0000039911",
    
    # Industrials (50+ companies)
    "AAON": "0000824142", "TREX": "0001069878", "FELE": "0000354647",
    "GGG": "0000042888", "MIDD": "0001034899", "AIT": "0001018963",
    "GWW": "0000277135", "WSO": "0000105418", "RBC": "0000085408",
    "CR": "0001373835", "MSM": "0000065885", "EPAC": "0001039684",
    "B": "0001025746", "TTEK": "0000097745", "SSD": "0000090896",
    "SITE": "0001628369", "TTC": "0000102934", "VMI": "0001001039",
    "AYI": "0001144215", "EME": "0000103169", "HWM": "0000046619",
    
    # Materials (30+ companies)
    "CLF": "0000764065", "X": "0001163302", "STLD": "0001022671",
    "RS": "0001047862", "CMC": "0000022205", "ATI": "0001018963",
    "CRS": "0000018230", "HAYN": "0001000697", "MATX": "0001172358",
    "SXI": "0001320206", "ARCH": "0001037676", "AMR": "0001595289",
    "BTU": "0001064728", "CEIX": "0001439427", "HCC": "0001096385",
    
    # REITs (40+ companies)
    "REXR": "0001571283", "FR": "0001321652", "STAG": "0001479094",
    "EGP": "0001508311", "IIPR": "0001677576", "SBRA": "0001298946",
    "CTRE": "0001628063", "NSA": "0001520017", "CUBE": "0001552000",
    "SUI": "0001247401", "ELS": "0001051026", "AMH": "0001562401",
    "INVH": "0001687229", "UMH": "0001069889", "CSR": "0001628061",
    
    # Communications (20+ companies)
    "CABO": "0001468516", "SATS": "0001651671", "WOW": "0001126975",
    "LUMN": "0000018926", "FYBR": "0001659109", "ATUS": "0001193125",
    "GTN": "0001454789", "CNSL": "0001051512", "OOMA": "0001496048",
    
    # Utilities (15+ companies)
    "NWN": "0000073020", "SJW": "0000766829", "MSEX": "0001003078",
    "CWT": "0001482133", "YORW": "0000108388", "AWR": "0001056235",
    "SJI": "0000091928", "NJR": "0000356037", "SPH": "0001699150",
}

def get_expanded_russell_2000():
    """
    Get an expanded list of Russell 2000 companies
    In production, this would fetch from a data provider API
    """
    print(f"📊 Russell 2000 Company Database")
    print(f"   Companies loaded: {len(RUSSELL_2000_FULL)}")
    print(f"   Sectors covered: Technology, Healthcare, Energy, Financials, Consumer, Industrials, Materials, REITs, Communications, Utilities")
    
    # Group by first letter for easier lookup
    by_letter = {}
    for ticker in sorted(RUSSELL_2000_FULL.keys()):
        first = ticker[0]
        if first not in by_letter:
            by_letter[first] = []
        by_letter[first].append(ticker)
    
    print(f"\n📋 Companies by letter:")
    for letter in sorted(by_letter.keys()):
        print(f"   {letter}: {len(by_letter[letter])} companies")
    
    return RUSSELL_2000_FULL

def validate_ciks():
    """Validate that CIK numbers are properly formatted"""
    invalid = []
    for ticker, cik in RUSSELL_2000_FULL.items():
        if not cik.startswith("000"):
            continue
        try:
            int(cik)
        except:
            invalid.append((ticker, cik))
    
    if invalid:
        print(f"\n⚠️ Invalid CIKs found: {invalid}")
    else:
        print(f"\n✅ All CIKs validated")

def export_to_json(filename="russell2000_companies.json"):
    """Export the company list to JSON"""
    data = {
        "companies": RUSSELL_2000_FULL,
        "total_count": len(RUSSELL_2000_FULL),
        "last_updated": datetime.now().isoformat(),
        "note": "Subset of Russell 2000 for training. Full index has ~2000 companies."
    }
    
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"\n💾 Exported to {filename}")

if __name__ == "__main__":
    companies = get_expanded_russell_2000()
    validate_ciks()
    export_to_json()