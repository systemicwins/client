import Foundation

/// Calibration system that learns from top-performing companies' filing patterns
class SECBERTCalibration {
    
    // Gold standard companies - known to be excellent (100% across the board)
    static let goldStandardCompanies = [
        "AAPL",  // Apple
        "MSFT",  // Microsoft
        "GOOGL", // Google/Alphabet
        "GOOG",  // Google/Alphabet Class C
        "AMZN",  // Amazon
        "META",  // Meta/Facebook
        "NVDA",  // NVIDIA
        "TSM"    // Taiwan Semiconductor Manufacturing Company
    ]
    
    // Learned patterns from gold standard companies
    struct GoldStandardPatterns {
        // Management Excellence Patterns (from FAANG+ and TSMC filings)
        static let managementExcellence = [
            // Strategic vision
            "artificial intelligence", "ai", "machine learning", "cloud",
            "platform", "ecosystem", "innovation", "transform",
            "strategic initiative", "long-term growth", "competitive moat",
            
            // Execution excellence
            "record", "exceeded expectations", "outperformed",
            "market leadership", "industry-leading", "best-in-class",
            "operational excellence", "efficiency gains", "margin expansion",
            
            // Forward guidance
            "accelerating growth", "strong momentum", "robust pipeline",
            "significant opportunity", "expanding addressable market",
            "positive outlook", "confident", "well-positioned",
            
            // TSMC-specific excellence patterns
            "technology leadership", "advanced node", "leading-edge technology",
            "foundry", "capacity expansion", "technology roadmap",
            "process technology", "yield improvement", "technology migration"
        ]
        
        // Financial Strength Patterns
        static let financialStrength = [
            // Revenue & profitability
            "revenue growth", "double-digit growth", "year-over-year increase",
            "operating leverage", "margin improvement", "profitable growth",
            "strong cash generation", "free cash flow", "return on investment",
            
            // Balance sheet strength
            "strong balance sheet", "substantial cash", "financial flexibility",
            "investment grade", "capital allocation", "shareholder returns",
            "dividend", "share repurchase", "capital return program",
            
            // TSMC-specific financial strength
            "capital expenditure", "capex", "gross margin", "utilization rate",
            "average selling price", "wafer shipments", "revenue contribution"
        ]
        
        // Operational Excellence Patterns
        static let operationalExcellence = [
            // Scale & efficiency
            "economies of scale", "network effects", "operating leverage",
            "automation", "productivity", "streamlined operations",
            "cost optimization", "operational efficiency", "synergies",
            
            // Customer & market
            "customer satisfaction", "retention", "engagement",
            "market share gains", "user growth", "active users",
            "subscription growth", "recurring revenue", "customer lifetime value",
            
            // TSMC-specific operational excellence
            "manufacturing excellence", "fab", "fabrication facility",
            "production capacity", "nanometer", "nm technology",
            "high-performance computing", "hpc", "automotive platform",
            "5g", "iot", "smartphone", "data center", "edge computing"
        ]
        
        // Innovation & R&D Patterns
        static let innovationPatterns = [
            "research and development", "r&d investment", "innovation pipeline",
            "product roadmap", "technology leadership", "patents",
            "next-generation", "breakthrough", "cutting-edge",
            "product launches", "new features", "enhanced capabilities",
            
            // TSMC-specific innovation patterns
            "3nm", "2nm", "1nm", "angstrom", "euv", "extreme ultraviolet",
            "finfet", "gate-all-around", "gaa", "nanosheet",
            "chiplet", "3d ic", "advanced packaging", "cowos", "soic",
            "technology platform", "design enablement"
        ]
        
        // Risk Management Excellence (how top companies discuss risks)
        static let riskMitigationPatterns = [
            "risk mitigation", "diversified", "multiple revenue streams",
            "strong competitive position", "barriers to entry", "switching costs",
            "long-term contracts", "recurring revenue model", "subscription base",
            "geographical diversification", "product diversification",
            
            // TSMC-specific risk mitigation
            "supply chain resilience", "strategic partnerships", "customer diversification",
            "technology differentiation", "manufacturing redundancy", "capacity allocation",
            "intellectual property protection", "trade secret protection"
        ]
    }
    
    // Negative patterns (rarely seen in FAANG+ filings)
    struct WarningPatterns {
        static let severeWarnings = [
            "going concern", "material weakness", "bankruptcy",
            "default", "covenant violation", "delisting",
            "restatement", "SEC investigation", "DOJ investigation",
            "criminal", "fraud", "misstatement"
        ]
        
        static let moderateWarnings = [
            "declining revenue", "market share loss", "customer churn",
            "supply chain disruption", "inventory writedown", "goodwill impairment",
            "restructuring charges", "layoffs", "facility closures",
            "competitive pressure", "pricing pressure", "margin compression",
            
            // Semiconductor-specific warnings
            "yield issues", "yield problems", "fab utilization decline",
            "technology migration challenges", "process delays", "node delays",
            "capacity constraints", "equipment shortages", "overcapacity"
        ]
    }
    
    /// Calculate calibrated sentiment score by comparing to gold standard patterns
    static func calculateCalibratedScore(
        text: String,
        category: SECBERTService.SentimentCategory,
        isGoldStandardCompany: Bool = false,
        symbol: String = ""
    ) -> Double {
        let lowerText = text.lowercased()
        
        // If it's a gold standard company, start with higher baseline
        let baseline: Double = isGoldStandardCompany ? 75.0 : 50.0
        
        // Count pattern matches
        var excellenceScore = 0.0
        var warningScore = 0.0
        
        // Check excellence patterns based on category
        let excellencePatterns: [String]
        switch category {
        case .management:
            excellencePatterns = GoldStandardPatterns.managementExcellence + 
                                GoldStandardPatterns.innovationPatterns
        case .financial:
            excellencePatterns = GoldStandardPatterns.financialStrength
        case .operational:
            excellencePatterns = GoldStandardPatterns.operationalExcellence
        case .risk:
            excellencePatterns = GoldStandardPatterns.riskMitigationPatterns
        }
        
        // Score based on pattern matches
        for pattern in excellencePatterns {
            if lowerText.contains(pattern) {
                // Longer patterns are more specific and valuable
                let weight = pattern.split(separator: " ").count > 1 ? 2.0 : 1.0
                excellenceScore += weight
            }
        }
        
        // Check warning patterns
        for warning in WarningPatterns.severeWarnings {
            if lowerText.contains(warning) {
                warningScore += 5.0 // Severe warnings heavily penalized
            }
        }
        
        for warning in WarningPatterns.moderateWarnings {
            if lowerText.contains(warning) {
                warningScore += 2.0
            }
        }
        
        // Calculate similarity to gold standard
        let maxExcellence = Double(excellencePatterns.count)
        let excellenceRatio = min(excellenceScore / max(maxExcellence * 0.3, 1.0), 1.0)
        
        // Adjust baseline based on patterns
        var score = baseline
        
        // Boost for excellence patterns
        score += excellenceRatio * 25.0
        
        // Penalty for warning patterns
        score -= min(warningScore * 5.0, 40.0)
        
        // Special adjustments for risk category
        if category == .risk {
            // For risk, good companies acknowledge risks but show mitigation
            if lowerText.contains("risk") && 
               (lowerText.contains("mitigat") || lowerText.contains("manage") || 
                lowerText.contains("address")) {
                score += 10.0
            }
        }
        
        // Apply bounds
        if score > 95 { return 95.0 }
        if score < 5 { return 5.0 }
        
        return score
    }
    
    /// Analyze filing with calibration against gold standards
    static func analyzeCalibratedSentiment(
        text: String,
        symbol: String,
        category: SECBERTService.SentimentCategory
    ) -> (score: Double, confidence: Double, insights: [String]) {
        
        // Check company classification
        let upperSymbol = symbol.uppercased()
        let isGoldStandard = goldStandardCompanies.contains(upperSymbol)
        let (tier, sector) = Russell2000Calibration.classifyCompany(symbol: upperSymbol)
        
        // Use appropriate scoring system
        let score: Double
        if tier == .smallCap || tier == .midCap {
            // Use Russell 2000 calibration for small/mid caps
            score = Russell2000Calibration.calculateSmallCapScore(
                text: text,
                symbol: symbol,
                sector: sector,
                category: category
            )
        } else {
            // Use FAANG+ calibration for large/mega caps
            score = calculateCalibratedScore(
                text: text,
                category: category,
                isGoldStandardCompany: isGoldStandard,
                symbol: symbol
            )
        }
        
        // Calculate confidence based on pattern matches
        let lowerText = text.lowercased()
        var patternMatches = 0
        var insights: [String] = []
        
        // Check for key patterns and generate insights
        if lowerText.contains("record") && lowerText.contains("revenue") {
            patternMatches += 2
            insights.append("Record revenue performance")
        }
        
        if lowerText.contains("margin") && lowerText.contains("expansion") {
            patternMatches += 2
            insights.append("Expanding margins")
        }
        
        if lowerText.contains("market leader") || lowerText.contains("market share gain") {
            patternMatches += 2
            insights.append("Strong market position")
        }
        
        if lowerText.contains("artificial intelligence") || lowerText.contains(" ai ") {
            patternMatches += 1
            insights.append("AI/ML initiatives")
        }
        
        if lowerText.contains("cloud") && lowerText.contains("growth") {
            patternMatches += 1
            insights.append("Cloud growth driver")
        }
        
        // Semiconductor-specific insights (TSMC patterns)
        if lowerText.contains("nm") || lowerText.contains("nanometer") || lowerText.contains("node") {
            patternMatches += 1
            insights.append("Advanced process technology")
        }
        
        if lowerText.contains("hpc") || lowerText.contains("high-performance computing") {
            patternMatches += 1
            insights.append("HPC market focus")
        }
        
        if lowerText.contains("fab") || lowerText.contains("fabrication") || lowerText.contains("foundry") {
            patternMatches += 1
            insights.append("Manufacturing/foundry excellence")
        }
        
        if lowerText.contains("euv") || lowerText.contains("extreme ultraviolet") {
            patternMatches += 1
            insights.append("Leading-edge lithography")
        }
        
        // Warning insights
        if lowerText.contains("restructuring") {
            insights.append("⚠️ Restructuring activities")
        }
        
        if lowerText.contains("litigation") || lowerText.contains("investigation") {
            insights.append("⚠️ Legal concerns")
        }
        
        if lowerText.contains("goodwill impairment") || lowerText.contains("writedown") {
            insights.append("⚠️ Asset impairments")
        }
        
        // Calculate confidence (0-1)
        let confidence = min(Double(patternMatches) / 5.0, 1.0)
        
        // Add comparative insight
        if isGoldStandard {
            let companyType = upperSymbol == "TSM" ? "FAANG+ & Semiconductor leader" : "FAANG+"
            insights.insert("📊 Gold standard company (\(companyType))", at: 0)
        } else if tier == .smallCap && sector != nil {
            // Add Russell 2000 insights
            let russell2000Insights = Russell2000Calibration.getSmallCapInsights(text: text, symbol: symbol)
            insights.append(contentsOf: russell2000Insights)
        } else if score >= 70 {
            if tier == .smallCap {
                insights.append("✨ Showing Russell 2000 leader characteristics")
            } else {
                insights.append("✨ Showing FAANG-like characteristics")
            }
        } else if score <= 30 {
            insights.append("⚠️ Significant divergence from sector leaders")
        }
        
        return (score: score, confidence: confidence, insights: insights)
    }
    
    /// Get benchmark score for comparison
    static func getBenchmarkScore(for category: SECBERTService.SentimentCategory, tier: Russell2000Calibration.CompanyTier = .megaCap) -> Double {
        // Different benchmarks for different company tiers
        switch tier {
        case .megaCap:
            // FAANG+ standards
            switch category {
            case .management: return 85.0
            case .financial: return 90.0
            case .operational: return 85.0
            case .risk: return 80.0
            }
        case .smallCap, .midCap:
            // Russell 2000 standards (slightly lower but still excellent)
            switch category {
            case .management: return 75.0
            case .financial: return 70.0
            case .operational: return 70.0
            case .risk: return 65.0
            }
        default:
            // General market standards
            switch category {
            case .management: return 60.0
            case .financial: return 60.0
            case .operational: return 60.0
            case .risk: return 55.0
            }
        }
    }
}