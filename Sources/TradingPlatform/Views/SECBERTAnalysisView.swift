import SwiftUI

struct SECBERTAnalysisView: View {
    let analysisResult: SECBERTService.AnalysisResult?
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                Text("AI Financial Health Analysis")
                    .font(.headline)
                
                Spacer()
            }
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView("Analyzing company health...")
                        .progressViewStyle(.linear)
                    Text("Processing SEC filings with AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let result = analysisResult {
                // Unified Health Score Display
                VStack(spacing: 16) {
                    // Main health score
                    HStack(spacing: 16) {
                        // Score circle
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .trim(from: 0, to: result.healthScore / 100)
                                .stroke(
                                    colorForScore(result.healthScore),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.5), value: result.healthScore)
                            
                            VStack(spacing: 0) {
                                Text("\(Int(result.healthScore))")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("%")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.label)
                                .font(.headline)
                                .foregroundColor(colorForScore(result.healthScore))
                            
                            Text("Company Health")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption)
                                Text("Confidence: \(Int(result.confidence * 100))%")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Key insights
                    if !result.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Insights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            
                            ForEach(Array(result.insights.prefix(5).enumerated()), id: \.offset) { _, insight in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(insight)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // Source indicator
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Based on SEC filings analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No analysis available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Select a stock to analyze SEC filings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
    
    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 70...100:
            return .green
        case 40..<70:
            return .orange
        default:
            return .red
        }
    }
}

struct ScoreCard: View {
    let title: String
    let score: SECBERTService.SentimentScore
    let icon: String
    let description: String
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(score.color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Score with visual indicator
            HStack(spacing: 8) {
                // Percentage
                Text("\(Int(score.score))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(score.color)
                
                // Visual bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(score.gradientColor)
                            .frame(width: geometry.size.width * (score.score / 100), height: 8)
                    }
                }
                .frame(height: 8)
            }
            
            // Sentiment label
            Text(score.label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Description
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Expandable snippets
            if !score.snippets.isEmpty {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.caption2)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(score.snippets, id: \.self) { snippet in
                            Text("• \(snippet)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(score.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// Preview removed - not supported in this build configuration