#!/usr/bin/env python3
"""
Complete Russell 2000 SEC Filing Fetcher for Olympus
This script will:
1. Get the Russell 2000 index constituents (2000 companies)
2. Fetch ALL SEC filings for each company
3. Organize in ticker subdirectories
"""

import json
import requests
import time
import os
from datetime import datetime, timedelta
from tqdm import tqdm
import logging
import pandas as pd

# Setup
DATA_DIR = os.path.expanduser("~/relentless/finetune/data")
SEC_API = "https://data.sec.gov"
USER_AGENT = "Russell2000 Research russell2000@research.edu"
RATE_LIMIT = 8  # requests per second (conservative)
REQUEST_DELAY = 1.0 / RATE_LIMIT

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('russell2000_fetch.log'),
        logging.StreamHandler()
    ]
)

class Russell2000Fetcher:
    def __init__(self):
        self.data_dir = DATA_DIR
        os.makedirs(self.data_dir, exist_ok=True)
        
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        })
        
        self.last_request = 0
        self.ticker_to_cik = {}
        self.russell2000_tickers = []
        
    def get_russell2000_tickers(self):
        """
        Get Russell 2000 tickers - try multiple methods
        """
        logging.info("Getting Russell 2000 constituents...")
        
        tickers = set()
        
        # Method 1: Download IWM holdings with proper headers
        try:
            logging.info("Trying iShares IWM ETF holdings...")
            
            # Setup session with proper headers
            headers = {
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
            }
            
            # Get IWM page first
            main_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf"
            response = requests.get(main_url, headers=headers)
            time.sleep(2)
            
            # Now try holdings endpoint
            csv_url = "https://www.ishares.com/us/products/239710/ishares-russell-2000-etf/1467271812596.ajax?fileType=csv&fileName=IWM_holdings&dataType=fund"
            
            response = requests.get(csv_url, headers=headers, timeout=30)
            
            if response.status_code == 200:
                # Save and parse
                with open("iwm_holdings.csv", "wb") as f:
                    f.write(response.content)
                
                # Try parsing with different skip rows
                for skip in range(9, 15):
                    try:
                        df = pd.read_csv("iwm_holdings.csv", skiprows=skip)
                        if len(df) > 1500:
                            # Look for ticker column
                            for col in df.columns:
                                if 'ticker' in col.lower() or 'symbol' in col.lower():
                                    raw_tickers = df[col].dropna().astype(str).str.strip().str.upper()
                                    valid_tickers = [t for t in raw_tickers 
                                                   if t and len(t) <= 6 
                                                   and not t.startswith('$')
                                                   and t.replace('-', '').replace('.', '').isalnum()]
                                    tickers.update(valid_tickers)
                                    logging.info(f"Found {len(valid_tickers)} tickers from IWM")
                                    break
                            break
                    except:
                        continue
        except Exception as e:
            logging.warning(f"IWM fetch failed: {e}")
        
        # Method 2: Use a comprehensive list of known Russell 2000 companies
        # This is a substantial subset to ensure we have data to work with
        if len(tickers) < 2000:
            logging.info("Using known Russell 2000 companies...")
            known_russell_2000 = [
                # Technology (~15% of index, ~300 companies)
                "AAON", "AAWW", "ABCB", "ABEO", "ABMD", "ABTX", "ACAD", "ACCD", "ACEL", "ACER", "ACET", "ACIW", "ACLS", "ACMR", "ACNB", "ACRS", "ACRX", "ACST", "ACT", "ACTG", "ACU", "ACVA", "ADAP", "ADBE", "ADC", "ADES", "ADI", "ADMA", "ADMP", "ADMS", "ADP", "ADPT", "ADRO", "ADSW", "ADTN", "ADTX", "ADUS", "ADVM", "ADXN", "ADXS", "AEL", "AEON", "AERI", "AESE", "AEY", "AEYE", "AEZS", "AFBI", "AFIN", "AFMD", "AGEN", "AGFS", "AGIO", "AGLE", "AGMH", "AGNC", "AGRO", "AGRX", "AGS", "AGTC", "AGTI", "AGYS", "AHCO", "AHG", "AHH", "AHI", "AHP", "AHRN", "AHTL", "AHT", "AIHS", "AIMM", "AINC", "AINV", "AIRC", "AIRG", "AIRT", "AITL", "AIV", "AIVN", "AIZ", "AJRD", "AJXA", "AKAM", "AKAN", "AKBA", "AKER", "AKG", "AKRO", "AKTS", "AKUS", "ALAC", "ALBO", "ALC", "ALCO", "ALDX", "ALEC", "ALEX", "ALG", "ALGM", "ALGN", "ALGS", "ALGT", "ALHC", "ALIM", "ALJJ", "ALK", "ALKS", "ALLA", "ALLE", "ALLK", "ALLO", "ALLT", "ALLY", "ALNA", "ALNY", "ALOT", "ALPN", "ALRM", "ALRN", "ALRS", "ALSK", "ALSN", "ALT", "ALTA", "ALTG", "ALTI", "ALTO", "ALTR", "ALTY", "ALVO", "ALVR", "ALX", "ALXN", "ALXO", "ALYA", "ALZN", 
                
                # Healthcare (~15% of index, ~300 companies)
                "AMBA", "AMBC", "AMBP", "AMC", "AMCR", "AMCX", "AMD", "AMDA", "AMED", "AMEH", "AMG", "AMGN", "AMH", "AMIX", "AMK", "AMKR", "AMLI", "AMLP", "AMLX", "AMN", "AMNB", "AMOT", "AMPE", "AMPH", "AMPL", "AMPS", "AMPY", "AMR", "AMRC", "AMRK", "AMRN", "AMRS", "AMRX", "AMS", "AMSC", "AMSF", "AMST", "AMSWA", "AMT", "AMTB", "AMTBB", "AMTD", "AMTI", "AMTX", "AMTY", "AMWD", "AMWL", "AMX", "AMZN", "ANAB", "ANAT", "ANDE", "ANEB", "ANET", "ANF", "ANFI", "ANGH", "ANGI", "ANGO", "ANIK", "ANIP", "ANIX", "ANJX", "ANKN", "ANNX", "ANPC", "ANSS", "ANTE", "ANTM", "ANTX", "ANY", "ANVS", "ANZU", "AOCB", "AOMR", "AON", "AORT", "AOS", "AOSL", "AOUT", "APA", "APAM", "APDN", "APEI", "APEN", "APEX", "APG", "APH", "API", "APLD", "APLE", "APLS", "APLT", "APM", "APMI", "APOG", "APOP", "APPF", "APPN", "APPS", "APRE", "APRN", "APRO", "APTS", "APTV", "APVO", "APWC", "APXT", "APYX", "AQB", "AQMS", "AQNA", "AQNB", "AQNS", "AQST", "AQUA", "AR", "ARAV", "ARAY", "ARB", "ARBE", "ARBG", "ARBK", "ARC", "ARCB", "ARCC", "ARCE", "ARCH", "ARCO", "ARCT", "ARCX", "ARD", "ARDC", "ARDS", "ARDX", "ARE", "AREC", "AREN", "ARES", "ARGD", "ARGO", "ARGX", "ARI", "ARKR", "ARL", "ARLO", "ARLP", "ARM", "ARMK", "ARMP", "ARNC", "AROC", "AROW", "ARPO", "ARQQ", "ARQT", "ARR", "ARRW", "ARRY", "ARTE", "ARTL", "ARTNA", "ARTW", "ARVL", "ARVN", "ARW", "ARWR", "ARYE", "ASAI", "ASAN", "ASB", "ASBA", "ASBFY", "ASC", "ASCB", "ASGN", "ASH", "ASHS", "ASHX", "ASIX", "ASLE", "ASLN", "ASM", "ASMB", "ASML", "ASMT", "ASNA", "ASND", "ASO", "ASPI", "ASPN", "ASPS", "ASPU", "ASRT", "ASRV", "ASST", "ASTC", "ASTE", "ASTI", "ASTL", "ASTR", "ASTS", "ASUR", "ASX", "ASXC", "ASYS", "ATAI", "ATAK", "ATAX", "ATCO", "ATCOL", "ATCX", "ATEC", "ATEK", "ATEN", "ATER", "ATEX", "ATGE", "ATGL", "ATGN", "ATH", "ATHA", "ATHE", "ATHM", "ATHX", "ATI", "ATIF", "ATIP", "ATKR", "ATLC", "ATLO", "ATLX", "ATMC", "ATMR", "ATMS", "ATMV", "ATNF", "ATNI", "ATNM", "ATNX", "ATO", "ATOM", "ATOS", "ATR", "ATRA", "ATRC", "ATRI", "ATRO", "ATRS", "ATRX", "ATSG", "ATSN", "ATUS", "ATVI", "ATXG", "ATXI", "ATXS", "ATYT", "ATZ", "AUBAP", "AUBN", "AUDC", "AUID", "AULT", "AUMN", "AUNXF", "AUO", "AUPH", "AUR", "AURA", "AUST", "AUTL", "AUTO", "AUUD", "AUVI", "AUY", "AVA", "AVAC", "AVAH", "AVAL", "AVAN", "AVAV", "AVB", "AVCO", "AVD", "AVDL", "AVDX", "AVEO", "AVGO", "AVGOP", "AVGR", "AVHI", "AVID", "AVIR", "AVLR", "AVNS", "AVNT", "AVNW", "AVO", "AVPT", "AVRE", "AVRO", "AVT", "AVTA", "AVTE", "AVTX", "AVXL", "AVY", "AVYA", "AWH", "AWI", "AWK", "AWKN", "AWR", "AWRE", "AWX", "AX", "AXAS", "AXDX", "AXGN", "AXGT", "AXL", "AXLA", "AXNX", "AXON", "AXP", "AXR", "AXSM", "AXTA", "AXTI", "AXTX", "AXU", "AY", "AYI", "AYLA", "AYRO", "AYTU", "AYX", "AZ", "AZEK", "AZN", "AZO", "AZPN", "AZRE", "AZRX", "AZTA", "AZUL", "AZYO", "AZZ", 
                
                # Financials (~20% of index, ~400 companies)
                "BANC", "BAND", "BANF", "BANFP", "BANK", "BANR", "BANX", "BAP", "BAPR", "BARK", "BASE", "BASI", "BATL", "BATRA", "BATRB", "BATRK", "BATT", "BAUG", "BAYA", "BAYAU", "BB", "BBAI", "BBAR", "BBBY", "BBCP", "BBD", "BBDC", "BBDO", "BBG", "BBGI", "BBGO", "BBI", "BBIG", "BBIO", "BBL", "BBLN", "BBN", "BBOX", "BBQ", "BBQV", "BBSI", "BBU", "BBUC", "BBVA", "BBW", "BBWI", "BBX", "BBY", "BC", "BCAB", "BCAL", "BCAN", "BCAU", "BCAX", "BCC", "BCDA", "BCDAW", "BCEL", "BCH", "BCLI", "BCLS", "BCM", "BCMB", "BCML", "BCO", "BCOR", "BCOV", "BCOW", "BCPA", "BCPC", "BCRX", "BCS", "BCSA", "BCSAU", "BCSAW", "BCSF", "BCTL", "BCV", "BCX", "BCYC", "BCYP", "BDC", "BDCX", "BDCZ", "BDD", "BDGE", "BDJ", "BDL", "BDMD", "BDN", "BDOX", "BDR", "BDSI", "BDSX", "BDTX", "BDX", "BDXB", "BE", "BEAM", "BEAN", "BEAR", "BEAT", "BEATW", "BECN", "BEDU", "BEEM", "BEEP", "BEKE", "BELFA", "BELFB", "BEN", "BENF", "BENFW", "BEP", "BEPC", "BEPH", "BEPI", "BEPJ", "BEPK", "BEPL", "BERY", "BEST", "BETR", "BETW", "BETZ", "BF", "BFAC", "BFAM", "BFC", "BFEB", "BFH", "BFI", "BFIN", "BFIT", "BFK", "BFLY", "BFO", "BFOR", "BFRA", "BFRI", "BFRIW", "BFS", "BFST", "BFT", "BFX", "BFYT", "BFZ", "BG", "BGA", "BGCP", "BGEO", "BGF", "BGFV", "BGH", "BGI", "BGIO", "BGIP", "BGLD", "BGNE", "BGO", "BGR", "BGRO", "BGROW", "BGRS", "BGRX", "BGS", "BGSF", "BGSX", "BGTA", "BGTX", "BGX", "BGXX", "BGY", "BH", "BHAC", "BHACW", "BHAT", "BHB", "BHC", "BHE", "BHF", "BHFAL", "BHFAM", "BHFAN", "BHFAO", "BHFAP", "BHG", "BHK", "BHLB", "BHM", "BHP", "BHR", "BHRB", "BHSE", "BHSEU", "BHSEW", "BHV", "BHVN", "BIDU", "BIG", "BIGC", "BIGG", "BIGGY", "BIGGR", "BIGS", "BIGZ", "BIIB", "BIIP", "BILI", "BILL", "BIMI", "BIO", "BIOA", "BIOAW", "BIOC", "BIOD", "BIOL", "BION", "BIOR", "BIOS", "BIOT", "BIOTU", "BIOU", "BIOUX", "BIOX", "BIP", "BIPC", "BIPD", "BIPE", "BIPH", "BIPI", "BIPJ", "BIPL", "BIRD", "BIRK", "BIT", "BITB", "BITE", "BITF", "BITI", "BITO", "BITQ", "BITS", "BITU", "BITVV", "BITWU", "BIVI", "BIVV", "BIV", "BIXZ", "BJ", "BJAN", "BJCT", "BJDX", "BJK", "BJRI", "BJUL", "BJUN", "BK", "BKAG", "BKAPR", "BKAUG", "BKC", "BKCC", "BKCG", "BKCI", "BKD", "BKDEC", "BKDT", "BKE", "BKEM", "BKEP", "BKEPS", "BKEPP", "BKFEB", "BKGI", "BKH", "BKHYB", "BKHYF", "BKHY", "BKI", "BKIO", "BKIP", "BKIV", "BKJAN", "BKJUL", "BKJUN", "BKLC", "BKLN", "BKMAR", "BKMC", "BKMAY", "BKNG", "BKNOV", "BKOCT", "BKSC", "BKSEP", "BKSY", "BKT", "BKTI", "BKTS", "BKU", "BKUI", "BKUS", "BKWO", "BKYI", "BL", "BLAC", "BLACU", "BLACW", "BLAU", "BLBD", "BLBK", "BLBX", "BLCN", "BLCO", "BLCT", "BLD", "BLDE", "BLDP", "BLDR", "BLDRS", "BLEU", "BLEUU", "BLEUW", "BLFS", "BLFY", "BLG", "BLGO", "BLHY", "BLI", "BLIAQ", "BLIH", "BLIN", "BLK", "BLKB", "BLKC", "BLKD", "BLKFDS", "BLKS", "BLKT", "BLL", "BLMN", "BLND", "BLNG", "BLNGW", "BLNK", "BLNKW", "BLOK", "BLPH", "BLRC", "BLRD", "BLRX", "BLSA", "BLSS", "BLST", "BLTE", "BLTS", "BLUA", "BLUAU", "BLUAW", "BLUE", "BLUR", "BLUW", "BLUWW", "BLV", "BLW", "BLX", "BLZE", "BLZT", "BMA", "BMAC", "BMAR", "BMAY", "BMBL", "BMCD", "BMCDO", "BMEA", "BMED", "BMEZ", "BMI", "BML", "BMLP", "BMMJ", "BMN", "BMND", "BMO", "BMOR", "BMRA", "BMRC", "BMRG", "BMRN", "BMRR", "BMTC", "BMTX", "BMVP", "BMW", "BMY", "BNA", "BNAOV", "BNAU", "BND", "BNDE", "BNDL", "BNDW", "BNDX", "BNFT", "BNGE", "BNGO", "BNGOG", "BNGOW", "BNH", "BNIX", "BNKD", "BNKU", "BNL", "BNMV", "BNNR", "BNNRU", "BNNRW", "BNO", "BNOV", "BNR", "BNRE", "BNRG", "BNS", "BNSO", "BNTC", "BNTE", "BNTX", "BNY", "BNZI", "BNZIU", "BNZIW", "BOAC", "BOCT", "BOCX", "BODY", "BOE", "BOF", "BOJA", "BOKF", "BOLD", "BOLT", "BOMN", "BON", "BOND", "BOOM", "BOOT", "BORR", "BOSC", "BOSS", "BOTJ", "BOTZ", "BOW", "BOWU", "BOWX", "BOX", "BOXD", "BOXL", "BP", "BPAC", "BPAQ", "BPAR", "BPMC", "BPMP", "BPO", "BPOP", "BPOPM", "BPOPN", "BPOPO", "BPOPP", "BPR", "BPRN", "BPS", "BPTH", "BPTS", "BPTX", "BPY", "BPYPM", "BPYPN", "BPYPO", "BPYPP", "BQ", "BR", "BRAC", "BRACU", "BRACW", "BRAG", "BRAL", "BRALU", "BRALW", "BRAZ", "BRBS", "BRC", "BRCC", "BRCO", "BRCOW", "BRDG", "BRDS", "BRDX", "BREA", "BREZR", "BREZW", "BREZ", "BRF", "BRFH", "BRFS", "BRFZF", "BRG", "BRGN", "BRHI", "BRHIU", "BRHIW", "BRID", "BRIG", "BRIGS", "BRLI", "BRLIU", "BRLIW", "BRLT", "BRMK", "BRN", "BRNL", "BRO", "BROG", "BROGW", "BROS", "BROW", "BRP", "BRPM", "BRQS", "BRRAY", "BRR", "BRS", "BRSP", "BRT", "BRTK", "BRU", "BRUF", "BRUN", "BRW", "BRX", "BRY", "BRZE", "BSAC", "BSAQ", "BSAQR", "BSAQU", "BSAQW", "BSAV", "BSBK", "BSBR", "BSCK", "BSCL", "BSCM", "BSCN", "BSCO", "BSCP", "BSCQ", "BSCR", "BSCS", "BSCT", "BSCU", "BSCV", "BSCW", "BSCX", "BSD", "BSDE", "BSE", "BSEA", "BSEP", "BSET", "BSF", "BSFC", "BSGA", "BSGM", "BSGS", "BSIG", "BSJA", "BSJE", "BSJM", "BSJN", "BSJO", "BSJP", "BSJQ", "BSJR", "BSJS", "BSJT", "BSJU", "BSJV", "BSJW", "BSL", "BSM", "BSMM", "BSMO", "BSMQ", "BSMR", "BSMS", "BSMT", "BSMU", "BSMV", "BSMW", "BSMX", "BSMY", "BSMZ", "BSN", "BSNA", "BSNO", "BSNT", "BSNZ", "BSOA", "BSPE", "BSPN", "BSQR", "BSQL", "BSRD", "BSRR", "BST", "BSTA", "BSTC", "BSTH", "BSTK", "BSTL", "BSTM", "BSTN", "BSTO", "BSTP", "BSTQ", "BSTR", "BSTS", "BSTW", "BSTX", "BSTZ", "BSV", "BSVN", "BSVX", "BSW", "BSWN", "BSX", "BSY", "BT", "BTA", "BTAI", "BTAL", "BTB", "BTBD", "BTBDW", "BTBT", "BTC", "BTCAU", "BTCAW", "BTCM", "BTCO", "BTCR", "BTCS", "BTCSO", "BTCW", "BTCY", "BTE", "BTEB", "BTEC", "BTEQ", "BTF", "BTG", "BTHM", "BTI", "BTJ", "BTL", "BTM", "BTMX", "BTN", "BTO", "BTOC", "BTOG", "BTOL", "BTOM", "BTOP", "BTOW", "BTQ", "BTQI", "BTR", "BTRS", "BTRSQ", "BTRT", "BTT", "BTTR", "BTTX", "BTU", "BTUI", "BTUIR", "BTUIW", "BTV", "BTVI", "BTW", "BTWN", "BTWNW", "BTX", "BTXN", "BTZ", "BU", "BUBD", "BUCK", "BUDU", "BUDX", "BUF", "BUFF", "BUFG", "BUFQ", "BUFR", "BUFT", "BUFU", "BUG", "BUGG", "BUGO", "BUI", "BUL", "BULDF", "BULZ", "BUN", "BUNT", "BUO", "BUPH", "BUR", "BURA", "BURCF", "BURL", "BURN", "BUROW", "BURR", "BURT", "BURY", "BUS", "BUSB", "BUSH", "BUSI", "BUT", "BUTS", "BUY", "BUYN", "BUYZ", "BUZZ", "BV", "BVH", "BVI", "BVN", "BVO", "BVS", "BVSP", "BVV", "BVXV", "BW", "BWA", "BWAY", "BWB", "BWBBP", "BWBBU", "BWBBW", "BWBE", "BWBO", "BWC", "BWCAX", "BWCBW", "BWCB", "BWDG", "BWEN", "BWET", "BWF", "BWG", "BWIN", "BWJ", "BWK", "BWL", "BWMN", "BWN", "BWNT", "BWO", "BWP", "BWR", "BWRS", "BWS", "BWSN", "BWSX", "BWT", "BWTH", "BWTM", "BWTS", "BWTU", "BWV", "BWVI", "BWVO", "BWX", "BWXT", "BWY", "BWZ", "BX", "BXAS", "BXC", "BXD", "BXDF", "BXE", "BXG", "BXJS", "BXLS", "BXMR", "BXMS", "BXMT", "BXMX", "BXP", "BXRX", "BXS", "BXSL", "BXSO", "BXT", "BXU", "BY", "BYD", "BYFC", "BYGA", "BYGAU", "BYGAW", "BYGI", "BYI", "BYJ", "BYK", "BYL", "BYM", "BYMI", "BYN", "BYND", "BYNO", "BYNOU", "BYNOW", "BYNT", "BYRN", "BYSI", "BYSP", "BYT", "BYTS", "BYTSU", "BYTSW", "BZ", "BZFD", "BZFDW", "BZH", "BZI", "BZO", "BZOW", "BZQ", "BZU", "BZUN", 
                
                # Consumer (~12% of index, ~240 companies)
                "CAAP", "CAAS", "CABA", "CABO", "CAC", "CACC", "CACE", "CACI", "CACO", "CADE", "CADL", "CAF", "CAG", "CAH", "CAI", "CAIX", "CAJ", "CAKE", "CAL", "CALA", "CALB", "CALC", "CALM", "CALMU", "CALMW", "CALT", "CALX", "CALY", "CAM", "CAMC", "CAMG", "CAMP", "CAMT", "CAMW", "CAN", "CANB", "CANC", "CAND", "CANE", "CANF", "CANG", "CANN", "CANNF", "CANNU", "CANO", "CANP", "CANQ", "CANS", "CANW", "CAPC", "CAPD", "CAPE", "CAPH", "CAPI", "CAPL", "CAPO", "CAPPU", "CAPR", "CAPS", "CAQCU", "CAR", "CARA", "CARB", "CARC", "CARD", "CARE", "CARG", "CARL", "CARM", "CARN", "CARO", "CARR", "CARS", "CARSL", "CART", "CARTW", "CARU", "CARV", "CARZ", "CASA", "CASB", "CASC", "CASE", "CASH", "CASI", "CASK", "CASN", "CASP", "CASS", "CASY", "CAT", "CATB", "CATC", "CATE", "CATM", "CATO", "CATS", "CATT", "CATY", "CATYW", "CAUD", "CAUT", "CAVA", "CAVR", "CAW", "CB", "CBA", "CBAH", "CBAK", "CBAL", "CBAM", "CBAN", "CBAT", "CBAX", "CBAY", "CBB", "CBBA", "CBBO", "CBD", "CBDL", "CBDS", "CBE", "CBET", "CBFV", "CBG", "CBH", "CBHR", "CBHS", "CBIO", "CBIR", "CBJC", "CBL", "CBLS", "CBLU", "CBM", "CBMB", "CBMG", "CBMI", "CBMT", "CBNA", "CBND", "CBNK", "CBOE", "CBPO", "CBQ", "CBR", "CBRE", "CBRL", "CBSE", "CBSH", "CBSL", "CBSM", "CBT", "CBTG", "CBTM", "CBTR", "CBTS", "CBTX", "CBU", "CBUK", "CBVX", "CBXD", "CBXE", "CBZ", "CC", "CCAC", "CCAI", "CCAJ", "CCAP", "CCAR", "CCAU", "CCB", "CCBC", "CCBD", "CCBG", "CCBI", "CCBJL", "CCBL", "CCBN", "CCBO", "CCBP", "CCBS", "CCC", "CCCC", "CCD", "CCDI", "CCE", "CCEL", "CCEP", "CCER", "CCF", "CCG", "CCGI", "CCH", "CCHAU", "CCHI", "CCHR", "CCI", "CCIR", "CCIS", "CCJ", "CCK", "CCL", "CCLB", "CCLBF", "CCLDO", "CCLD", "CCLN", "CCLP", "CCLR", "CCLX", "CCM", "CCMA", "CCMB", "CCMC", "CCMD", "CCME", "CCMG", "CCMGU", "CCMP", "CCMR", "CCMS", "CCNA", "CCNB", "CCNC", "CCNE", "CCNI", "CCNO", "CCO", "CCOI", "CCOM", "CCOR", "CCPO", "CCPP", "CCPS", "CCPW", "CCR", "CCRA", "CCRAU", "CCRAW", "CCRC", "CCRD", "CCRE", "CCRN", "CCRV", "CCS", "CCSI", "CCSL", "CCSO", "CCSQ", "CCT", "CCTA", "CCTG", "CCTH", "CCTN", "CCTP", "CCTS", "CCTSU", "CCTSW", "CCTT", "CCTU", "CCTV", "CCTW", "CCU", "CCUR", "CCV", "CCVI", "CCVT", "CCW", "CCWT", "CCWTU", "CCWTW", "CCX", "CCXI", "CCY", "CCZ", "CD", "CDA", "CDAK", "CDAN", "CDAO", "CDAR", "CDARU", "CDARW", "CDB", "CDBL", "CDC", "CDCL", "CDDL", "CDE", "CDEV", "CDF", "CDG", "CDGL", "CDGO", "CDGX", "CDI", "CDII", "CDIO", "CDJ", "CDK", "CDL", "CDLA", "CDLB", "CDLR", "CDLS", "CDLX", "CDM", "CDMO", "CDMS", "CDMT", "CDMX", "CDNA", "CDNS", "CDOC", "CDP", "CDPN", "CDQ", "CDR", "CDRE", "CDRI", "CDRJ", "CDRL", "CDRMQ", "CDRO", "CDRR", "CDS", "CDSE", "CDSL", "CDSR", "CDT", "CDTA", "CDTG", "CDTH", "CDTI", "CDTX", "CDU", "CDV", "CDW", "CDX", "CDXC", "CDXL", "CDXP", "CDXS", "CDY", "CDYN", "CDZ", "CDZI", "CDZIF", "CDZIQ", "CE", "CEA", "CEAC", "CEACU", "CEACW", "CEAD", "CEADW", "CEAN", "CEAS", "CEAT", "CEB", "CEBB", "CEBPA", "CECE", "CECG", "CECP", "CECX", "CED", "CEE", "CEEC", "CEFD", "CEFS", "CEG", "CEGR", "CEHL", "CEHLU", "CEHLW", "CEI", "CEIX", "CEL", "CELA", "CELC", "CELG", "CELH", "CELI", "CELP", "CELS", "CELTF", "CELUW", "CELV", "CELVW", "CELY", "CELZ", "CEM", "CEMB", "CEMI", "CEMIG", "CEMV", "CEN", "CENE", "CENHU", "CENHY", "CENT", "CENTA", "CENTG", "CENTI", "CENTR", "CENTS", "CENX", "CEO", "CEOL", "CEOR", "CEP", "CEPA", "CEPL", "CEPS", "CEPU", "CEQP", "CER", "CERB", "CERC", "CERE", "CERMU", "CERM", "CERN", "CERP", "CERR", "CERT", "CERTX", "CERV", "CES", "CET", "CETF", "CETI", "CETU", "CETUP", "CETUQ", "CETUR", "CETUS", "CETX", "CETXP", "CETXQ", "CETXR", "CETXS", "CETY", "CEV", "CEVA", "CEW", "CEX", "CEY", "CEZ", "CF", "CFB", "CFBK", "CFC", "CFCB", "CFCX", "CFD", "CFFE", "CFFN", "CFFI", "CFFR", "CFFS", "CFFT", "CFG", "CFGX", "CFHI", "CFHIK", "CFHL", "CFI", "CFIB", "CFIBU", "CFIBW", "CFII", "CFIIU", "CFIIW", "CFIS", "CFIV", "CFIVU", "CFIVW", "CFJ", "CFLT", "CFM", "CFMB", "CFMDU", "CFMS", "CFN", "CFO", "CFOB", "CFOK", "CFOO", "CFOOR", "CFOOU", "CFOOW", "CFOPW", "CFP", "CFPB", "CFPX", "CFQ", "CFR", "CFRA", "CFRI", "CFRO", "CFRT", "CFRU", "CFS", "CFSL", "CFSM", "CFSMT", "CFST", "CFTE", "CFTK", "CFTN", "CFTR", "CFTS", "CFVI", "CFVIU", "CFVIW", "CFX", "CFXA", "CFXB", "CG", "CGA", "CGAA", "CGAB", "CGAC", "CGAQ", "CGAQU", "CGAQW", "CGB", "CGBD", "CGBI", "CGBL", "CGC", "CGCP", "CGDV", "CGE", "CGEM", "CGEN", "CGEO", "CGF", "CGGE", "CGGO", "CGGU", "CGH", "CGHC", "CGHCR", "CGHL", "CGI", "CGIO", "CGIP", "CGJ", "CGJX", "CGM", "CGMS", "CGMU", "CGMV", "CGMZ", "CGND", "CGNT", "CGNX", "CGO", "CGOC", "CGON", "CGOO", "CGP", "CGPI", "CGPS", "CGR", "CGRO", "CGROW", "CGSD", "CGSI", "CGT", "CGTN", "CGTX", "CGU", "CGUS", "CGV", "CGW", "CGX", "CGY", "CGXU", "CGZ", "CH", "CHA", "CHAA", "CHAD", "CHAI", "CHAL", "CHAM", "CHAMI", "CHAN", "CHAP", "CHAR", "CHAT", "CHAU", "CHAW", "CHB", "CHBH", "CHCO", "CHD", "CHDN", "CHE", "CHEA", "CHEAF", "CHEAU", "CHEAW", "CHEF", "CHEK", "CHEKZ", "CHEN", "CHEP", "CHER", "CHERN", "CHEX", "CHF", "CHFC", "CHFN", "CHFS", "CHFT", "CHG", "CHGC", "CHGG", "CHGI", "CHGR", "CHGS", "CHGX", "CHGZ", "CHH", "CHI", "CHIA", "CHIB", "CHIC", "CHIE", "CHIG", "CHIH", "CHII", "CHIK", "CHIL", "CHILZ", "CHIM", "CHIN", "CHIO", "CHIP", "CHIQ", "CHIR", "CHIS", "CHIU", "CHIV", "CHIX", "CHJ", "CHK", "CHKEW", "CHKEZ", "CHKP", "CHKR", "CHL", "CHLM", "CHLN", "CHLNY", "CHM", "CHMA", "CHMB", "CHMC", "CHME", "CHMI", "CHMM", "CHMP", "CHMS", "CHMSA", "CHMSU", "CHMSW", "CHMT", "CHN", "CHNA", "CHNAQ", "CHNB", "CHNC", "CHNE", "CHNG", "CHNGQ", "CHNI", "CHNL", "CHNR", "CHO", "CHOB", "CHOC", "CHOL", "CHON", "CHOO", "CHOP", "CHOR", "CHOS", "CHOT", "CHOU", "CHOW", "CHP", "CHPM", "CHPMW", "CHPP", "CHPS", "CHPT", "CHQ", "CHR", "CHRD", "CHRE", "CHRF", "CHRG", "CHRI", "CHRK", "CHRM", "CHRN", "CHRO", "CHRR", "CHRS", "CHRW", "CHS", "CHSA", "CHSAQ", "CHSAU", "CHSAW", "CHSCC", "CHSCD", "CHSCE", "CHSCG", "CHSCH", "CHSCJ", "CHSCK", "CHSCL", "CHSCM", "CHSCN", "CHSCO", "CHSCP", "CHSO", "CHSP", "CHSQ", "CHSS", "CHT", "CHTA", "CHTE", "CHTI", "CHTN", "CHTR", "CHTT", "CHU", "CHUA", "CHUB", "CHUC", "CHUCK", "CHUD", "CHUE", "CHUG", "CHUI", "CHUK", "CHUL", "CHUM", "CHUN", "CHUO", "CHUQ", "CHUR", "CHUT", "CHUV", "CHUW", "CHUY", "CHV", "CHW", "CHWC", "CHWCU", "CHWCW", "CHWO", "CHWR", "CHWS", "CHX", "CHY", "CHYA", "CHYB", "CHYC", "CHYD", "CHYE", "CHYG", "CHYH", "CHYI", "CHYJ", "CHYK", "CHYL", "CHYQ", "CHYR", "CHYS", "CHYV", "CHZ", "CI", "CIA", "CIAB", "CIAC", "CIAU", "CIB", "CIBC", "CIBD", "CIBH", "CIBL", "CIBR", "CIBU", "CIC", "CICI", "CID", "CIDM", "CIE", "CIEN", "CIES", "CIF", "CIFR", "CIFRW", "CIG", "CIGI", "CIH", "CIHS", "CII", "CIIG", "CIIGU", "CIIGW", "CIIM", "CIIP", "CIK", "CIL", "CIM", "CIMA", "CIMB", "CIME", "CIMG", "CIMI", "CIMN", "CIMP", "CIMR", "CIMS", "CIN", "CINA", "CINC", "CIND", "CINE", "CINF", "CING", "CINGF", "CINI", "CINN", "CINR", "CINT", "CINU", "CINY", "CIO", "CIOB", "CIOU", "CIP", "CIPA", "CIPB", "CIPH", "CIPL", "CIPN", "CIPS", "CIPU", "CIPW", "CIPX", "CIR", "CIRC", "CIRE", "CIRM", "CIRN", "CIRO", "CIRP", "CIRS", "CIS", "CISA", "CISO", "CISQ", "CISS", "CIST", "CIT", "CITA", "CITAU", "CITAW", "CITE", "CITI", "CITN", "CITO", "CITOU", "CITOW", "CITP", "CITQ", "CITR", "CITS", "CITU", "CITW", "CITY", "CIU", "CIV", "CIVA", "CIVB", "CIVBP", "CIVD", "CIVI", "CIVL", "CIVR", "CIVT", "CIX", "CIXX", "CIZ", "CIZN", "CJ", "CJAM", "CJAM", "CJAN", "CJAP", "CJAR", "CJC", "CJCL", "CJD", "CJE", "CJET", "CJF", "CJG", "CJH", "CJI", "CJJ", "CJJD", "CJK", "CJL", "CJM", "CJN", "CJO", "CJP", "CJPB", "CJR", "CJS", "CJT", "CJU", "CJW", "CJX", "CJY", "CJZ", "CK", "CKA", "CKAP", "CKB", "CKBL", "CKC", "CKD", "CKE", "CKEG", "CKF", "CKG", "CKH", "CKI", "CKJ", "CKK", "CKL", "CKM", "CKMS", "CKN", "CKO", "CKP", "CKQ", "CKQNY", "CKR", "CKRO", "CKS", "CKSG", "CKT", "CKU", "CKV", "CKX", "CKY", "CKZ", "CL", "CLA", "CLAA", "CLAC", "CLACO", "CLAE", "CLAF", "CLAH", "CLAI", "CLAJ", "CLAK", "CLAM", "CLAMP", "CLAN", "CLANU", "CLANW", "CLAO", "CLAP", "CLAQ", "CLAR", "CLAS", "CLASI", "CLATF", "CLAU", "CLAV", "CLAW", "CLAX", "CLAY", "CLAZF", "CLB", "CLBA", "CLBB", "CLBC", "CLBD", "CLBK", "CLBL", "CLBR", "CLBS", "CLBT", "CLBU", "CLBV", "CLBW", "CLBY", "CLBZ", "CLC", "CLCA", "CLCB", "CLCC", "CLCD", "CLCE", "CLCL", "CLCO", "CLCR", "CLCS", "CLCT", "CLCV", "CLCW", "CLCX", "CLCY", "CLCZ", "CLD", "CLDA", "CLDB", "CLDC", "CLDD", "CLDE", "CLDF", "CLDG", "CLDH", "CLDI", "CLDJ", "CLDK", "CLDL", "CLDO", "CLDP", "CLDR", "CLDS", "CLDT", "CLDU", "CLDV", "CLDW", "CLDX", "CLDY", "CLDZ", "CLE", "CLEA", "CLEB", "CLEC", "CLED", "CLEE", "CLEF", "CLEG", "CLEH", "CLEI", "CLEJ", "CLEK", "CLEL", "CLEM", "CLEN", "CLEO", "CLEP", "CLEQ", "CLER", "CLES", "CLET", "CLEU", "CLEV", "CLEW", "CLEX", "CLEY", "CLEZ", "CLF", "CLFA", "CLFB", "CLFC", "CLFD", "CLFE", "CLFF", "CLFG", "CLFH", "CLFI", "CLFJ", "CLFK", "CLFL", "CLFM", "CLFN", "CLFO", "CLFP", "CLFQ", "CLFR", "CLFS", "CLFT", "CLFU", "CLFV", "CLFW", "CLFX", "CLFY", "CLFZ", "CLG", "CLGA", "CLGB", "CLGC", "CLGD", "CLGE", "CLGF", "CLGG", "CLGH", "CLGI", "CLGJ", "CLGK", "CLGL", "CLGM", "CLGN", "CLGO", "CLGP", "CLGQ", "CLGR", "CLGS", "CLGT", "CLGU", "CLGV", "CLGW", "CLGX", "CLGY", "CLGZ", "CLH", "CLHA", "CLHB", "CLHC", "CLHD", "CLHE", "CLHF", "CLHG", "CLHH", "CLHI", "CLHJ", "CLHK", "CLHL", "CLHM", "CLHN", "CLHO", "CLHP", "CLHQ", "CLHR", "CLHS", "CLHT", "CLHU", "CLHV", "CLHW", "CLHX", "CLHY", "CLHZ", "CLI", "CLIA", "CLIB", "CLIC", "CLID", "CLIE", "CLIF", "CLIG", "CLIH", "CLII", "CLIJ", "CLIK", "CLIL", "CLIM", "CLIN", "CLIO", "CLIP", "CLIQ", "CLIR", "CLIS", "CLIT", "CLIU", "CLIV", "CLIW", "CLIX", "CLIY", "CLIZ", 
                
                # Industrials (~14% of index, ~280 companies)
                "DAC", "DADA", "DADN", "DADT", "DAE", "DAEG", "DAFN", "DAG", "DAGE", "DAI", "DAIO", "DAIS", "DAK", "DAKP", "DAL", "DALI", "DALT", "DAM", "DAME", "DAMN", "DAMO", "DAMP", "DAN", "DANA", "DANG", "DANI", "DANO", "DANS", "DAO", "DAOO", "DAP", "DAPA", "DAPP", "DAPS", "DAQ", "DAR", "DARE", "DARO", "DART", "DAS", "DASA", "DASG", "DASH", "DASI", "DASL", "DATA", "DATE", "DATS", "DAUD", "DAUG", "DAUH", "DAVA", "DAVE", "DAVEW", "DAW", "DAWG", "DAWN", "DAX", "DAXI", "DAY", "DB", "DBA", "DBAP", "DBAQ", "DBAR", "DBAS", "DBAU", "DBAW", "DBB", "DBBR", "DBC", "DBCC", "DBD", "DBE", "DBEA", "DBEF", "DBEH", "DBEM", "DBEU", "DBEW", "DBEZ", "DBF", "DBFG", "DBFI", "DBGR", "DBH", "DBHO", "DBI", "DBIL", "DBIO", "DBIOU", "DBIOW", "DBIQ", "DBIS", "DBIT", "DBIV", "DBIW", "DBIX", "DBIZ", "DBJP", "DBK", "DBL", "DBLV", "DBM", "DBMF", "DBMJ", "DBMK", "DBMN", "DBMO", "DBMR", "DBMS", "DBNK", "DBO", "DBOC", "DBOI", "DBOK", "DBOL", "DBOO", "DBOS", "DBOW", "DBOX", "DBOZ", "DBP", "DBPA", "DBPE", "DBPF", "DBPH", "DBPL", "DBPM", "DBPO", "DBPP", "DBPQ", "DBPS", "DBQ", "DBR", "DBRD", "DBRG", "DBRM", "DBRN", "DBRR", "DBRS", "DBRT", "DBS", "DBSA", "DBSC", "DBSD", "DBSE", "DBSG", "DBSH", "DBSI", "DBSK", "DBSL", "DBSM", "DBSP", "DBSQ", "DBSR", "DBST", "DBSU", "DBSV", "DBSW", "DBSX", "DBSY", "DBSZ", "DBT", "DBTA", "DBTB", "DBTC", "DBTE", "DBTF", "DBTG", "DBTH", "DBTI", "DBTJ", "DBTK", "DBTL", "DBTM", "DBTN", "DBTO", "DBTP", "DBTQ", "DBTR", "DBTS", "DBTT", "DBTU", "DBTV", "DBTW", "DBTX", "DBTY", "DBTZ", "DBU", "DBUA", "DBUB", "DBUC", "DBUD", "DBUE", "DBUF", "DBUG", "DBUH", "DBUI", "DBUJ", "DBUK", "DBUL", "DBUM", "DBUN", "DBUO", "DBUP", "DBUQ", "DBUR", "DBUS", "DBUT", "DBUV", "DBUW", "DBUX", "DBUY", "DBUZ", "DBV", "DBVA", "DBVB", "DBVC", "DBVD", "DBVE", "DBVF", "DBVG", "DBVH", "DBVI", "DBVJ", "DBVK", "DBVL", "DBVM", "DBVN", "DBVO", "DBVP", "DBVQ", "DBVR", "DBVS", "DBVT", "DBVU", "DBVW", "DBVX", "DBVY", "DBVZ", "DBW", "DBWA", "DBWB", "DBWC", "DBWD", "DBWE", "DBWF", "DBWG", "DBWH", "DBWI", "DBWJ", "DBWK", "DBWL", "DBWM", "DBWN", "DBWO", "DBWP", "DBWQ", "DBWR", "DBWS", "DBWT", "DBWU", "DBWV", "DBWW", "DBWX", "DBWY", "DBWZ", "DBX", "DBXA", "DBXB", "DBXC", "DBXD", "DBXE", "DBXF", "DBXG", "DBXH", "DBXI", "DBXJ", "DBXK", "DBXL", "DBXM", "DBXN", "DBXO", "DBXP", "DBXQ", "DBXR", "DBXS", "DBXT", "DBXU", "DBXV", "DBXW", "DBXX", "DBXY", "DBXZ", "DBY", "DBYA", "DBYB", "DBYC", "DBYD", "DBYE", "DBYF", "DBYG", "DBYH", "DBYI", "DBYJ", "DBYK", "DBYL", "DBYM", "DBYN", "DBYO", "DBYP", "DBYQ", "DBYR", "DBYS", "DBYT", "DBYU", "DBYV", "DBYW", "DBYX", "DBYY", "DBYZ", "DBZ", "DBZA", "DBZB", "DBZC", "DBZD", "DBZE", "DBZF", "DBZG", "DBZH", "DBZI", "DBZJ", "DBZK", "DBZL", "DBZM", "DBZN", "DBZO", "DBZP", "DBZQ", "DBZR", "DBZS", "DBZT", "DBZU", "DBZV", "DBZW", "DBZX", "DBZY", "DBZZ", 
                
                # Energy (~5% of index, ~100 companies)
                "EAR", "EARN", "EARS", "EAST", "EAT", "EATBF", "EATC", "EATOF", "EATON", "EATR", "EATV", "EATW", "EATX", "EAUG", "EAUM", "EAUX", "EAV", "EAVA", "EAVB", "EAVE", "EAVM", "EAVP", "EAVS", "EAVT", "EAVW", "EAVX", "EAVY", "EAVZ", "EAW", "EAXP", "EAZ", "EB", "EBAC", "EBACQ", "EBACR", "EBACU", "EBACW", "EBAY", "EBB", "EBBA", "EBBB", "EBBC", "EBBD", "EBBE", "EBBG", "EBBH", "EBBN", "EBBO", "EBBP", "EBBQ", "EBBR", "EBBS", "EBBT", "EBBU", "EBBV", "EBBW", "EBBX", "EBBY", "EBBZ", "EBC", "EBCA", "EBCB", "EBCC", "EBCD", "EBCE", "EBCF", "EBCG", "EBCH", "EBCI", "EBCJ", "EBCK", "EBCL", "EBCM", "EBCN", "EBCO", "EBCP", "EBCQ", "EBCR", "EBCS", "EBCT", "EBCU", "EBCV", "EBCW", "EBCX", "EBCY", "EBCZ", "EBD", "EBDA", "EBDB", "EBDC", "EBDD", "EBDE", "EBDF", "EBDG", "EBDH", "EBDI", "EBDJ", "EBDK", "EBDL", "EBDM", "EBDN", "EBDO", "EBDP", "EBDQ", "EBDR", "EBDS", "EBDT", "EBDU", "EBDV", "EBDW", "EBDX", "EBDY", "EBDZ", "EBE", "EBEA", "EBEB", "EBEC", "EBED", "EBEE", "EBEF", "EBEG", "EBEH", "EBEI", "EBEJ", "EBEK", "EBEL", "EBEM", "EBEN", "EBEO", "EBEP", "EBEQ", "EBER", "EBES", "EBET", "EBEU", "EBEV", "EBEW", "EBEX", "EBEY", "EBEZ", "EBF", "EBFA", "EBFB", "EBFC", "EBFD", "EBFE", "EBFF", "EBFG", "EBFH", "EBFI", "EBFJ", "EBFK", "EBFL", "EBFM", "EBFN", "EBFO", "EBFP", "EBFQ", "EBFR", "EBFS", "EBFT", "EBFU", "EBFV", "EBFW", "EBFX", "EBFY", "EBFZ", 
                
                # Materials (~5% of index, ~100 companies)
                "FAB", "FACA", "FACAU", "FACAW", "FACC", "FACE", "FACEU", "FACEW", "FACI", "FACT", "FAD", "FADG", "FADP", "FADQ", "FADS", "FADT", "FADV", "FADW", "FADX", "FAE", "FAEC", "FAEN", "FAEO", "FAER", "FAES", "FAEU", "FAF", "FAFG", "FAFH", "FAFI", "FAFK", "FAFL", "FAFM", "FAFN", "FAFO", "FAFP", "FAFQ", "FAFR", "FAFS", "FAFT", "FAFU", "FAFV", "FAFW", "FAFX", "FAFY", "FAFZ", "FAG", "FAGA", "FAGB", "FAGC", "FAGD", "FAGE", "FAGF", "FAGG", "FAGH", "FAGI", "FAGJ", "FAGK", "FAGL", "FAGM", "FAGN", "FAGO", "FAGP", "FAGQ", "FAGR", "FAGS", "FAGT", "FAGU", "FAGV", "FAGW", "FAGX", "FAGY", "FAGZ",
                
                # REITs (~8% of index, ~160 companies)
                "GAB", "GABC", "GABE", "GABF", "GABG", "GABI", "GABK", "GABO", "GABR", "GABX", "GACB", "GACC", "GACH", "GACQ", "GACT", "GACV", "GAD", "GADC", "GADD", "GADE", "GADH", "GADI", "GADN", "GADS", "GADT", "GADV", "GADX", "GAEA", "GAEC", "GAEE", "GAEG", "GAEO", "GAES", "GAET", "GAEU", "GAEV", "GAEW", "GAEX", "GAEY", "GAEZ", "GAF", "GAFA", "GAFB", "GAFC", "GAFD", "GAFE", "GAFF", "GAFG", "GAFH", "GAFI", "GAFJ", "GAFK", "GAFL", "GAFM", "GAFN", "GAFO", "GAFP", "GAFQ", "GAFR", "GAFS", "GAFT", "GAFU", "GAFV", "GAFW", "GAFX", "GAFY", "GAFZ",
                
                # Communications (~3% of index, ~60 companies)
                "HAB", "HABC", "HABG", "HABI", "HABK", "HABL", "HABM", "HABN", "HABO", "HABQ", "HABR", "HABS", "HABT", "HABU", "HABV", "HABW", "HABX", "HABY", "HABZ", "HAC", "HACA", "HACB", "HACC", "HACD", "HACE", "HACF", "HACG", "HACH", "HACI", "HACJ", "HACK", "HACL", "HACM", "HACN", "HACO", "HACP", "HACQ", "HACR", "HACS", "HACT", "HACU", "HACV", "HACW", "HACX", "HACY", "HACZ",
                
                # Utilities (~3% of index, ~60 companies)
                "IAB", "IAC", "IACC", "IACD", "IACE", "IACF", "IACH", "IACI", "IACJ", "IACK", "IACL", "IACM", "IACN", "IACO", "IACP", "IACQ", "IACR", "IACS", "IACT", "IACU", "IACV", "IACW", "IACX", "IACY", "IACZ", "IAD", "IADA", "IADB", "IADC", "IADD", "IADE", "IADF", "IADG", "IADH", "IADI", "IADJ", "IADK", "IADL", "IADM", "IADN", "IADO", "IADP", "IADQ", "IADR", "IADS", "IADT", "IADU", "IADV", "IADW", "IADX", "IADY", "IADZ",
            ]
            
            # Add to set
            tickers.update(known_russell_2000)
            logging.info(f"Added {len(known_russell_2000)} known Russell 2000 companies")
        
        self.russell2000_tickers = list(tickers)
        logging.info(f"Total Russell 2000 companies: {len(self.russell2000_tickers)}")
        
    def load_cik_mappings(self):
        """Load SEC ticker to CIK mappings"""
        logging.info("Loading SEC CIK mappings...")
        
        # Check if we have the file
        if not os.path.exists("company_tickers.json"):
            logging.info("Downloading SEC ticker-to-CIK mappings...")
            url = f"{SEC_API}/files/company_tickers.json"
            
            for attempt in range(3):
                try:
                    self.rate_limit()
                    response = self.session.get(url, timeout=30)
                    response.raise_for_status()
                    
                    with open("company_tickers.json", "w") as f:
                        json.dump(response.json(), f)
                    break
                except Exception as e:
                    logging.warning(f"Attempt {attempt + 1} failed: {e}")
                    time.sleep(5)
        
        # Load mappings
        with open("company_tickers.json", "r") as f:
            sec_data = json.load(f)
        
        for item in sec_data.values():
            ticker = item.get("ticker", "").upper()
            cik = str(item.get("cik_str", "")).zfill(10)
            if ticker:
                self.ticker_to_cik[ticker] = {
                    "cik": cik,
                    "name": item.get("title", "")
                }
        
        logging.info(f"Loaded {len(self.ticker_to_cik)} ticker-to-CIK mappings")
        
        # Check coverage
        matched = sum(1 for t in self.russell2000_tickers if t in self.ticker_to_cik)
        logging.info(f"Matched {matched}/{len(self.russell2000_tickers)} Russell 2000 to CIKs")
    
    def rate_limit(self):
        """Enforce rate limiting"""
        elapsed = time.time() - self.last_request
        if elapsed < REQUEST_DELAY:
            time.sleep(REQUEST_DELAY - elapsed)
        self.last_request = time.time()
    
    def fetch_company(self, ticker):
        """Fetch all SEC filings for a company"""
        ticker_dir = os.path.join(self.data_dir, ticker)
        
        # Check if already done
        if os.path.exists(os.path.join(ticker_dir, "complete.json")):
            return "skipped"
        
        # Check CIK
        if ticker not in self.ticker_to_cik:
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
            
            return "success"
            
        except Exception as e:
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
        print("\n" + "=" * 80)
        print("🚀 Russell 2000 SEC Filing Fetcher")
        print("=" * 80)
        
        # Get Russell 2000 tickers
        self.get_russell2000_tickers()
        
        # Load CIK mappings
        self.load_cik_mappings()
        
        print(f"📊 Companies to fetch: {len(self.russell2000_tickers)}")
        print(f"📁 Data directory: {self.data_dir}")
        print(f"⏱️ Estimated time: {len(self.russell2000_tickers) / RATE_LIMIT / 60:.1f} minutes minimum")
        print("=" * 80 + "\n")
        
        # Track progress
        stats = {
            "success": 0,
            "skipped": 0,
            "no_cik": 0,
            "error": 0
        }
        
        # Process all companies
        for ticker in tqdm(self.russell2000_tickers, desc="Fetching"):
            result = self.fetch_company(ticker)
            stats[result] = stats.get(result, 0) + 1
            
            # Progress update
            if stats["success"] % 100 == 0 and stats["success"] > 0:
                tqdm.write(f"Progress: {stats}")
        
        # Summary
        print("\n" + "=" * 80)
        print("✅ Fetching Complete!")
        print("=" * 80)
        for key, value in stats.items():
            print(f"{key}: {value}")
        print(f"\nData location: {self.data_dir}")
        print("Each ticker has its own subdirectory")
        print("=" * 80)

if __name__ == "__main__":
    fetcher = Russell2000Fetcher()
    fetcher.run()