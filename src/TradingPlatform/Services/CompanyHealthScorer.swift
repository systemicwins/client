import Foundation

/// Unified company health scoring system (0-100%)
class CompanyHealthScorer {
    
    /// Calculate single comprehensive health score for a company
    static func calculateHealthScore(
        filingText: String,
        symbol: String,
        formType: String = "10-K"
    ) -> (score: Double, confidence: Double, insights: [String]) {
        
        let upperSymbol = symbol.uppercased()
        let lowerText = filingText.lowercased()
        
        // Determine company tier and sector
        let (tier, sector) = Russell2000Calibration.classifyCompany(symbol: upperSymbol)
        let isMegaCap = SECBERTCalibration.goldStandardCompanies.contains(upperSymbol)
        let isRussell2000Leader = isRussell2000Leader(symbol: upperSymbol)
        
        // Start with baseline based on tier
        var healthScore: Double
        switch tier {
        case .megaCap:
            healthScore = 75.0  // FAANG+ companies start high
        case .smallCap where isRussell2000Leader:
            healthScore = 65.0  // Russell 2000 leaders get good baseline
        case .smallCap, .midCap:
            healthScore = 50.0  // Regular small/mid caps start neutral
        default:
            healthScore = 50.0  // Unknown companies start neutral
        }
        
        // Analyze all aspects and adjust score
        var insights: [String] = []
        var confidenceFactors = 0
        
        // 1. Financial Health Analysis (30% weight)
        let financialScore = analyzeFinancialHealth(text: lowerText, tier: tier)
        healthScore += financialScore.adjustment * 0.30
        insights.append(contentsOf: financialScore.insights)
        confidenceFactors += financialScore.signals
        
        // 2. Growth Trajectory Analysis (25% weight)
        let growthScore = analyzeGrowthTrajectory(text: lowerText, tier: tier)
        healthScore += growthScore.adjustment * 0.25
        insights.append(contentsOf: growthScore.insights)
        confidenceFactors += growthScore.signals
        
        // 3. Operational Excellence Analysis (20% weight)
        let operationalScore = analyzeOperationalExcellence(text: lowerText, tier: tier)
        healthScore += operationalScore.adjustment * 0.20
        insights.append(contentsOf: operationalScore.insights)
        confidenceFactors += operationalScore.signals
        
        // 4. Risk Assessment (15% weight - negative factors)
        let riskScore = analyzeRisks(text: lowerText, tier: tier)
        healthScore -= riskScore.adjustment * 0.15  // Subtract risk penalty
        insights.append(contentsOf: riskScore.insights)
        confidenceFactors += riskScore.signals
        
        // 5. Innovation & Competitive Position (10% weight)
        let innovationScore = analyzeInnovation(text: lowerText, tier: tier, sector: sector)
        healthScore += innovationScore.adjustment * 0.10
        insights.append(contentsOf: innovationScore.insights)
        confidenceFactors += innovationScore.signals
        
        // Add tier/classification insight at the beginning
        if isMegaCap {
            insights.insert("📊 Mega-cap leader (FAANG+)", at: 0)
        } else if isRussell2000Leader {
            insights.insert("⭐ Russell 2000 sector leader", at: 0)
        } else if tier == .smallCap {
            insights.insert("🎯 Small-cap company", at: 0)
        }
        
        // Apply bounds
        if healthScore > 95 { healthScore = 95 }
        if healthScore < 5 { healthScore = 5 }
        
        // Calculate confidence (0-1 based on number of signals found)
        let confidence = min(Double(confidenceFactors) / 20.0, 1.0)
        
        // Add overall health assessment
        let healthAssessment = getHealthAssessment(score: healthScore)
        insights.append(healthAssessment)
        
        return (score: healthScore, confidence: confidence, insights: insights)
    }
    
    // MARK: - Component Analysis Functions
    
    private static func analyzeFinancialHealth(text: String, tier: Russell2000Calibration.CompanyTier) 
        -> (adjustment: Double, signals: Int, insights: [String]) {
        
        var adjustment = 0.0
        var signals = 0
        var insights: [String] = []
        
        // Positive financial indicators
        let strongFinancials = [
            ("record revenue", 15.0, "Record revenue"),
            ("revenue growth", 10.0, "Revenue growth"),
            ("margin expansion", 12.0, "Expanding margins"),
            ("positive cash flow", 15.0, "Cash flow positive"),
            ("strong balance sheet", 10.0, "Strong balance sheet"),
            ("profitable", 8.0, "Profitable operations"),
            ("ebitda positive", 10.0, "EBITDA positive"),
            ("free cash flow", 12.0, "Free cash flow generation")
        ]
        
        for (pattern, weight, insight) in strongFinancials {
            if text.contains(pattern) {
                adjustment += weight
                signals += 1
                if insights.count < 3 && !insight.isEmpty {
                    insights.append("💰 \(insight)")
                }
            }
        }
        
        // Negative financial indicators
        let weakFinancials = [
            ("loss", -10.0, "Losses reported"),
            ("declining revenue", -15.0, "Revenue decline"),
            ("negative cash flow", -20.0, "Negative cash flow"),
            ("liquidity concern", -25.0, "Liquidity concerns"),
            ("going concern", -40.0, "Going concern warning"),
            ("covenant breach", -30.0, "Debt covenant breach"),
            ("impairment", -15.0, "Asset impairments")
        ]
        
        for (pattern, weight, insight) in weakFinancials {
            if text.contains(pattern) && !text.contains("no " + pattern) {
                adjustment += weight
                signals += 1
                if !insight.isEmpty {
                    insights.append("⚠️ \(insight)")
                }
            }
        }
        
        return (adjustment, signals, insights)
    }
    
    private static func analyzeGrowthTrajectory(text: String, tier: Russell2000Calibration.CompanyTier)
        -> (adjustment: Double, signals: Int, insights: [String]) {
        
        var adjustment = 0.0
        var signals = 0
        var insights: [String] = []
        
        // Check for specific growth rates
        if text.contains("50% growth") || text.contains("50% increase") {
            adjustment += 20.0
            signals += 2
            insights.append("🚀 50%+ growth rate")
        } else if text.contains("40% growth") || text.contains("40% increase") {
            adjustment += 15.0
            signals += 2
            insights.append("🚀 40%+ growth rate")
        } else if text.contains("30% growth") || text.contains("30% increase") {
            adjustment += 12.0
            signals += 1
            insights.append("📈 30%+ growth rate")
        } else if text.contains("20% growth") || text.contains("20% increase") {
            adjustment += 8.0
            signals += 1
            insights.append("📈 20%+ growth rate")
        } else if text.contains("double-digit growth") {
            adjustment += 6.0
            signals += 1
            insights.append("📈 Double-digit growth")
        }
        
        // Growth momentum indicators
        if text.contains("accelerat") {
            adjustment += 8.0
            signals += 1
            if insights.count < 3 { insights.append("📊 Accelerating growth") }
        }
        
        if text.contains("beat guidance") || text.contains("exceeded expectations") {
            adjustment += 10.0
            signals += 1
            if insights.count < 3 { insights.append("✅ Beating expectations") }
        }
        
        // Negative growth indicators
        if text.contains("slowing growth") || text.contains("decelerat") {
            adjustment -= 10.0
            signals += 1
            insights.append("⚠️ Growth deceleration")
        }
        
        if text.contains("flat") || text.contains("stagnant") {
            adjustment -= 5.0
            signals += 1
        }
        
        return (adjustment, signals, insights)
    }
    
    private static func analyzeOperationalExcellence(text: String, tier: Russell2000Calibration.CompanyTier)
        -> (adjustment: Double, signals: Int, insights: [String]) {
        
        var adjustment = 0.0
        var signals = 0
        var insights: [String] = []
        
        let operationalStrength = [
            ("operational excellence", 10.0, "Operational excellence"),
            ("efficiency gains", 8.0, "Efficiency improvements"),
            ("cost reduction", 6.0, "Cost optimization"),
            ("synergies realized", 8.0, "Synergy realization"),
            ("integration successful", 8.0, "Successful integration"),
            ("capacity expansion", 7.0, "Capacity expansion"),
            ("automation", 6.0, "Automation benefits"),
            ("streamlin", 5.0, "Streamlined operations")
        ]
        
        for (pattern, weight, insight) in operationalStrength {
            if text.contains(pattern) {
                adjustment += weight
                signals += 1
                if insights.count < 2 && !insight.isEmpty {
                    insights.append("⚙️ \(insight)")
                }
            }
        }
        
        // Customer metrics (very important)
        if text.contains("customer retention") || text.contains("retention rate") {
            adjustment += 10.0
            signals += 1
            insights.append("👥 Strong customer retention")
        }
        
        if text.contains("customer acquisition") || text.contains("new customers") {
            adjustment += 8.0
            signals += 1
        }
        
        return (adjustment, signals, insights)
    }
    
    private static func analyzeRisks(text: String, tier: Russell2000Calibration.CompanyTier)
        -> (adjustment: Double, signals: Int, insights: [String]) {
        
        var adjustment = 0.0  // This will be subtracted from health score
        var signals = 0
        var insights: [String] = []
        
        // Critical risks
        if text.contains("going concern") {
            adjustment += 50.0
            signals += 2
            insights.append("🚨 Going concern warning")
        }
        
        if text.contains("bankruptcy") || text.contains("liquidation") {
            adjustment += 40.0
            signals += 2
            insights.append("🚨 Bankruptcy risk")
        }
        
        if text.contains("sec investigation") || text.contains("doj investigation") {
            adjustment += 30.0
            signals += 1
            insights.append("⚠️ Regulatory investigation")
        }
        
        if text.contains("material weakness") {
            adjustment += 25.0
            signals += 1
            insights.append("⚠️ Material weakness identified")
        }
        
        // Moderate risks
        if text.contains("customer concentration") {
            adjustment += 15.0
            signals += 1
            if insights.count < 3 { insights.append("⚠️ Customer concentration risk") }
        }
        
        if text.contains("litigation") && !text.contains("no material litigation") {
            adjustment += 10.0
            signals += 1
        }
        
        if text.contains("restructuring") {
            adjustment += 12.0
            signals += 1
            if insights.count < 3 { insights.append("⚠️ Restructuring activities") }
        }
        
        return (adjustment, signals, insights)
    }
    
    private static func analyzeInnovation(text: String, tier: Russell2000Calibration.CompanyTier, sector: Russell2000Calibration.CompanySector?)
        -> (adjustment: Double, signals: Int, insights: [String]) {
        
        var adjustment = 0.0
        var signals = 0
        var insights: [String] = []
        
        // Innovation indicators
        if text.contains("artificial intelligence") || text.contains(" ai ") {
            adjustment += 12.0
            signals += 1
            insights.append("🤖 AI initiatives")
        }
        
        if text.contains("innovation") || text.contains("r&d") || text.contains("research and development") {
            adjustment += 8.0
            signals += 1
            if insights.isEmpty { insights.append("🔬 Innovation focus") }
        }
        
        if text.contains("new product") || text.contains("product launch") {
            adjustment += 10.0
            signals += 1
            if insights.count < 2 { insights.append("🎯 New product launches") }
        }
        
        if text.contains("market leader") || text.contains("competitive advantage") {
            adjustment += 15.0
            signals += 1
            if insights.count < 2 { insights.append("👑 Market leadership") }
        }
        
        // Sector-specific innovation
        if let sector = sector {
            switch sector {
            case .technology:
                if text.contains("saas") || text.contains("recurring revenue") {
                    adjustment += 8.0
                    signals += 1
                }
            case .healthcare:
                if text.contains("fda approval") || text.contains("clinical success") {
                    adjustment += 15.0
                    signals += 1
                    insights.append("💊 FDA/Clinical progress")
                }
            case .energy:
                if text.contains("drilling success") || text.contains("production growth") {
                    adjustment += 10.0
                    signals += 1
                }
            default:
                break
            }
        }
        
        return (adjustment, signals, insights)
    }
    
    // MARK: - Helper Functions
    
    private static func isRussell2000Leader(symbol: String) -> Bool {
        return Russell2000Calibration.Russell2000Leaders.technology.contains(symbol) ||
               Russell2000Calibration.Russell2000Leaders.healthcare.contains(symbol) ||
               Russell2000Calibration.Russell2000Leaders.energy.contains(symbol) ||
               Russell2000Calibration.Russell2000Leaders.financials.contains(symbol) ||
               Russell2000Calibration.Russell2000Leaders.industrials.contains(symbol) ||
               Russell2000Calibration.Russell2000Leaders.consumer.contains(symbol)
    }
    
    private static func getHealthAssessment(score: Double) -> String {
        switch score {
        case 85...100:
            return "💎 Excellent health (Top tier)"
        case 70..<85:
            return "✅ Strong health"
        case 55..<70:
            return "📊 Good health"
        case 40..<55:
            return "⚡ Fair health"
        case 25..<40:
            return "⚠️ Weak health"
        default:
            return "🚨 Poor health"
        }
    }
}