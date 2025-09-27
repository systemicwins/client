import Foundation

/// Russell 2000 calibration system - using small-cap leaders as gold standards
class Russell2000Calibration {
    
    // Russell 2000 top performers by sector (as of 2024)
    // These represent the gold standard for small-cap companies
    struct Russell2000Leaders {
        // Technology sector leaders
        static let technology = [
            "SMCI",  // Super Micro Computer
            "COHR",  // Coherent Corp
            "RMBS",  // Rambus
            "AEIS",  // Advanced Energy Industries
            "WOLF",  // Wolfspeed
            "ONTO",  // Onto Innovation
            "POWI",  // Power Integrations
            "DIOD",  // Diodes Inc
            "SITM",  // SiTime Corporation
            "AMBA"   // Ambarella
        ]
        
        // Healthcare/Biotech leaders
        static let healthcare = [
            "INSM",  // Insmed
            "KRYS",  // Krystal Biotech
            "ROIV",  // Roivant Sciences
            "HALO",  // Halozyme Therapeutics
            "ACAD",  // ACADIA Pharmaceuticals
            "ITCI",  // Intra-Cellular Therapies
            "SAGE",  // Sage Therapeutics
            "ARVN",  // Arvinas
            "RVMD",  // Revolution Medicines
            "TGTX"   // TG Therapeutics
        ]
        
        // Energy sector leaders
        static let energy = [
            "TALO",  // Talos Energy
            "VTLE",  // Vital Energy
            "SM",    // SM Energy
            "MGY",   // Magnolia Oil & Gas
            "CRC",   // California Resources
            "GPOR",  // Gulfport Energy
            "NOG",   // Northern Oil and Gas
            "DINO",  // HF Sinclair
            "PBF",   // PBF Energy
            "DK"     // Delek US Holdings
        ]
        
        // Financial sector leaders
        static let financials = [
            "SFBS",  // ServisFirst Bancshares
            "EWBC",  // East West Bancorp
            "TFSL",  // TFS Financial
            "OZK",   // Bank OZK
            "SSB",   // SouthState Corporation
            "FHN",   // First Horizon
            "GBCI",  // Glacier Bancorp
            "UBSI",  // United Bankshares
            "FFIN",  // First Financial Bankshares
            "TCBI"   // Texas Capital Bancshares
        ]
        
        // Industrial sector leaders
        static let industrials = [
            "FELE",  // Franklin Electric
            "TTC",   // Toro Company
            "GWW",   // W.W. Grainger
            "RBC",   // Regal Beloit
            "AIT",   // Applied Industrial Technologies
            "MSM",   // MSC Industrial Direct
            "GGG",   // Graco Inc
            "MIDD",  // Middleby Corporation
            "AAON",  // AAON Inc
            "TREX"   // Trex Company
        ]
        
        // Consumer sector leaders
        static let consumer = [
            "SHAK",  // Shake Shack
            "WING",  // Wingstop
            "TXRH",  // Texas Roadhouse
            "PLAY",  // Dave & Buster's
            "DKS",   // Dick's Sporting Goods
            "BOOT",  // Boot Barn Holdings
            "OLLI",  // Ollie's Bargain Outlet
            "FIVE",  // Five Below
            "BURL",  // Burlington Stores
            "RVLV"   // Revolve Group
        ]
    }
    
    // Small-cap specific excellence patterns (different from mega-cap)
    struct SmallCapExcellencePatterns {
        
        // Growth patterns for small caps
        static let growthIndicators = [
            // Revenue growth (small caps often have higher growth rates)
            "revenue increased", "sales growth", "top-line growth",
            "20% growth", "30% growth", "40% growth", "50% growth",
            "accelerating revenue", "sequential improvement",
            
            // Market expansion
            "new markets", "geographic expansion", "new customers",
            "market penetration", "customer acquisition", "win rate",
            "expanding footprint", "new locations", "new territories",
            
            // Product/Service expansion
            "new product launch", "product line expansion", "service expansion",
            "cross-selling", "upselling", "attach rates"
        ]
        
        // Profitability transition (key for small caps)
        static let profitabilityPatterns = [
            "achieving profitability", "positive ebitda", "cash flow positive",
            "gross margin improvement", "operating leverage", "scale benefits",
            "path to profitability", "inflection point", "margin expansion",
            "unit economics", "contribution margin", "breakeven"
        ]
        
        // Small-cap financial health
        static let financialHealthPatterns = [
            "debt reduction", "improved liquidity", "working capital improvement",
            "cash runway", "burn rate improvement", "capital efficiency",
            "self-funded growth", "organic growth", "bootstrapped",
            "no dilution", "insider buying", "management ownership"
        ]
        
        // Competitive advantages for small caps
        static let competitiveAdvantagePatterns = [
            "niche market", "specialized", "differentiated", "unique",
            "first mover", "disruptive", "innovative solution",
            "proprietary technology", "patent portfolio", "trade secrets",
            "customer stickiness", "high switching costs", "network effects",
            "regulatory moat", "exclusive contracts", "sole source"
        ]
        
        // Execution excellence for small caps
        static let executionPatterns = [
            "ahead of plan", "beat guidance", "raised outlook",
            "exceeded expectations", "milestone achieved", "on track",
            "successful integration", "synergies realized", "cost savings",
            "operational improvements", "efficiency gains", "automation"
        ]
    }
    
    // Small-cap specific warning signs
    struct SmallCapWarningPatterns {
        static let severeWarnings = [
            "going concern", "covenant breach", "nasdaq deficiency",
            "delisting notice", "bankruptcy", "liquidation",
            "discontinued operations", "material weakness", "auditor resignation",
            "sec investigation", "class action", "fraud allegations"
        ]
        
        static let moderateWarnings = [
            "customer concentration", "key customer loss", "contract loss",
            "increased competition", "margin pressure", "pricing pressure",
            "inventory buildup", "accounts receivable aging", "bad debt",
            "cash burn", "need for financing", "dilutive financing",
            "workforce reduction", "executive turnover", "founder departure"
        ]
        
        static let growthChallenges = [
            "slowing growth", "deceleration", "tough comps", "difficult comparisons",
            "seasonality impact", "cyclical headwinds", "macro challenges",
            "supply chain issues", "labor shortage", "inflation impact",
            "delayed orders", "pushed deliveries", "extended sales cycles"
        ]
    }
    
    /// Determine company tier and sector
    static func classifyCompany(symbol: String, marketCap: Double? = nil) -> (tier: CompanyTier, sector: CompanySector?) {
        let upperSymbol = symbol.uppercased()
        
        // Check if it's a mega-cap gold standard
        if SECBERTCalibration.goldStandardCompanies.contains(upperSymbol) {
            return (.megaCap, nil)
        }
        
        // Check Russell 2000 sectors
        if Russell2000Leaders.technology.contains(upperSymbol) {
            return (.smallCap, .technology)
        }
        if Russell2000Leaders.healthcare.contains(upperSymbol) {
            return (.smallCap, .healthcare)
        }
        if Russell2000Leaders.energy.contains(upperSymbol) {
            return (.smallCap, .energy)
        }
        if Russell2000Leaders.financials.contains(upperSymbol) {
            return (.smallCap, .financials)
        }
        if Russell2000Leaders.industrials.contains(upperSymbol) {
            return (.smallCap, .industrials)
        }
        if Russell2000Leaders.consumer.contains(upperSymbol) {
            return (.smallCap, .consumer)
        }
        
        // Default classification based on market cap if provided
        if let marketCap = marketCap {
            if marketCap > 10_000_000_000 { // > $10B
                return (.largeCap, nil)
            } else if marketCap > 2_000_000_000 { // > $2B
                return (.midCap, nil)
            } else {
                return (.smallCap, nil)
            }
        }
        
        return (.unknown, nil)
    }
    
    enum CompanyTier {
        case megaCap    // FAANG+ companies
        case largeCap   // $10B+
        case midCap     // $2B-$10B
        case smallCap   // <$2B (Russell 2000)
        case unknown
    }
    
    enum CompanySector {
        case technology
        case healthcare
        case energy
        case financials
        case industrials
        case consumer
    }
    
    /// Calculate small-cap calibrated score
    static func calculateSmallCapScore(
        text: String,
        symbol: String,
        sector: CompanySector?,
        category: SECBERTService.SentimentCategory
    ) -> Double {
        let lowerText = text.lowercased()
        let (tier, detectedSector) = classifyCompany(symbol: symbol)
        let actualSector = sector ?? detectedSector
        
        // Start with appropriate baseline
        let baseline: Double
        switch tier {
        case .megaCap:
            baseline = 75.0  // Mega-caps get higher baseline
        case .smallCap where actualSector != nil:
            baseline = 65.0  // Russell 2000 leaders get good baseline
        default:
            baseline = 50.0  // Others start neutral
        }
        
        var score = baseline
        
        // Check small-cap excellence patterns
        var excellenceMatches = 0
        var warningMatches = 0
        
        // Growth indicators (very important for small caps)
        for pattern in SmallCapExcellencePatterns.growthIndicators {
            if lowerText.contains(pattern) {
                excellenceMatches += 2  // Growth is critical for small caps
            }
        }
        
        // Profitability patterns
        for pattern in SmallCapExcellencePatterns.profitabilityPatterns {
            if lowerText.contains(pattern) {
                excellenceMatches += 3  // Profitability transition is huge for small caps
            }
        }
        
        // Financial health
        for pattern in SmallCapExcellencePatterns.financialHealthPatterns {
            if lowerText.contains(pattern) {
                excellenceMatches += 1
            }
        }
        
        // Competitive advantages
        for pattern in SmallCapExcellencePatterns.competitiveAdvantagePatterns {
            if lowerText.contains(pattern) {
                excellenceMatches += 2
            }
        }
        
        // Execution patterns
        for pattern in SmallCapExcellencePatterns.executionPatterns {
            if lowerText.contains(pattern) {
                excellenceMatches += 1
            }
        }
        
        // Check warning patterns
        for warning in SmallCapWarningPatterns.severeWarnings {
            if lowerText.contains(warning) {
                warningMatches += 5
            }
        }
        
        for warning in SmallCapWarningPatterns.moderateWarnings {
            if lowerText.contains(warning) {
                warningMatches += 2
            }
        }
        
        for warning in SmallCapWarningPatterns.growthChallenges {
            if lowerText.contains(warning) {
                warningMatches += 1
            }
        }
        
        // Sector-specific adjustments
        if let actualSector = actualSector {
            score = applySectorAdjustments(
                score: score,
                sector: actualSector,
                text: lowerText,
                category: category
            )
        }
        
        // Calculate final score
        score += Double(excellenceMatches) * 2.5
        score -= Double(warningMatches) * 3.0
        
        // Small-cap specific bounds (wider range than mega-caps)
        if score > 95 { return 95.0 }
        if score < 5 { return 5.0 }
        
        return score
    }
    
    /// Apply sector-specific scoring adjustments
    private static func applySectorAdjustments(
        score: Double,
        sector: CompanySector,
        text: String,
        category: SECBERTService.SentimentCategory
    ) -> Double {
        var adjustedScore = score
        
        switch sector {
        case .technology:
            // Tech small-caps need strong growth and innovation
            if text.contains("arr growth") || text.contains("saas") || text.contains("recurring revenue") {
                adjustedScore += 5
            }
            if text.contains("churn") || text.contains("customer loss") {
                adjustedScore -= 10  // Customer retention critical for tech
            }
            
        case .healthcare:
            // Biotech/healthcare need pipeline and regulatory progress
            if text.contains("fda approval") || text.contains("clinical trial success") || text.contains("milestone") {
                adjustedScore += 10
            }
            if text.contains("clinical failure") || text.contains("fda rejection") {
                adjustedScore -= 15
            }
            
        case .energy:
            // Energy companies need commodity price discussion
            if text.contains("hedging") || text.contains("production growth") || text.contains("drilling success") {
                adjustedScore += 5
            }
            if text.contains("dry hole") || text.contains("write-down") {
                adjustedScore -= 10
            }
            
        case .financials:
            // Banks need asset quality and NIM discussion
            if text.contains("net interest margin") || text.contains("loan growth") || text.contains("credit quality") {
                adjustedScore += 5
            }
            if text.contains("charge-off") || text.contains("provision increase") {
                adjustedScore -= 8
            }
            
        case .industrials:
            // Industrials need backlog and margin discussion
            if text.contains("backlog growth") || text.contains("order book") || text.contains("contract wins") {
                adjustedScore += 5
            }
            if text.contains("project delays") || text.contains("cost overrun") {
                adjustedScore -= 7
            }
            
        case .consumer:
            // Consumer companies need same-store sales and traffic
            if text.contains("same-store") || text.contains("comp sales") || text.contains("traffic growth") {
                adjustedScore += 5
            }
            if text.contains("store closures") || text.contains("traffic decline") {
                adjustedScore -= 8
            }
        }
        
        return adjustedScore
    }
    
    /// Get insights for small-cap analysis
    static func getSmallCapInsights(text: String, symbol: String) -> [String] {
        var insights: [String] = []
        let lowerText = text.lowercased()
        let (tier, sector) = classifyCompany(symbol: symbol)
        
        // Tier insight
        switch tier {
        case .megaCap:
            insights.append("📊 Mega-cap leader (FAANG+)")
        case .smallCap where sector != nil:
            insights.append("⭐ Russell 2000 sector leader")
        case .smallCap:
            insights.append("🎯 Small-cap stock")
        case .midCap:
            insights.append("📈 Mid-cap stock")
        default:
            break
        }
        
        // Growth insights
        if lowerText.contains("30% growth") || lowerText.contains("40% growth") || lowerText.contains("50% growth") {
            insights.append("🚀 Exceptional growth rate")
        }
        
        if lowerText.contains("achieving profitability") || lowerText.contains("cash flow positive") {
            insights.append("💰 Reaching profitability inflection")
        }
        
        if lowerText.contains("beat guidance") || lowerText.contains("raised outlook") {
            insights.append("📊 Beating expectations")
        }
        
        // Warning insights
        if lowerText.contains("customer concentration") {
            insights.append("⚠️ Customer concentration risk")
        }
        
        if lowerText.contains("need for financing") || lowerText.contains("cash burn") {
            insights.append("⚠️ Funding concerns")
        }
        
        // Sector-specific insights
        if let sector = sector {
            switch sector {
            case .technology:
                if lowerText.contains("arr") || lowerText.contains("recurring revenue") {
                    insights.append("💻 SaaS/Recurring revenue model")
                }
            case .healthcare:
                if lowerText.contains("fda") || lowerText.contains("clinical") {
                    insights.append("🧬 Clinical/regulatory catalyst")
                }
            case .energy:
                if lowerText.contains("production") || lowerText.contains("drilling") {
                    insights.append("🛢️ Production growth focus")
                }
            case .financials:
                if lowerText.contains("loan growth") || lowerText.contains("nim") {
                    insights.append("🏦 Loan growth/NIM expansion")
                }
            case .industrials:
                if lowerText.contains("backlog") || lowerText.contains("order") {
                    insights.append("🏭 Strong order backlog")
                }
            case .consumer:
                if lowerText.contains("same-store") || lowerText.contains("traffic") {
                    insights.append("🛍️ Same-store sales driver")
                }
            }
        }
        
        return insights
    }
}