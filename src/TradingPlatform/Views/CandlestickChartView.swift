import SwiftUI
import SwiftUICharts

struct CandlestickChartView: View {
    @ObservedObject var manager: CandlestickManager
    let symbol: String
    
    @State private var showVolume = true
    @State private var chartTimeframe: ChartTimeframe = .oneMinute
    @State private var zoomRange: ClosedRange<Date>?
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var dragEnd: CGPoint = .zero
    
    // Computed property for filtered candles
    var filteredCandlesForVolume: [Candle] {
        guard let range = zoomRange else { return manager.chartData.candles }
        return manager.chartData.candles.filter { range.contains($0.timestamp) }
    }
    
    enum ChartTimeframe: String, CaseIterable {
        case oneMinute = "1m"
        case fiveMinutes = "5m"
        case fifteenMinutes = "15m"
        case thirtyMinutes = "30m"
        case oneHour = "1h"
        
        var title: String {
            switch self {
            case .oneMinute: return "1 Min"
            case .fiveMinutes: return "5 Min"
            case .fifteenMinutes: return "15 Min"
            case .thirtyMinutes: return "30 Min"
            case .oneHour: return "1 Hour"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chart header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(symbol)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 12) {
                        Label(formatCurrency(manager.chartData.currentPrice), systemImage: "dollarsign.circle")
                            .font(.subheadline)
                        
                        if manager.chartData.bid > 0 && manager.chartData.ask > 0 {
                            Text("Bid: \(formatCurrency(manager.chartData.bid))")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Text("Ask: \(formatCurrency(manager.chartData.ask))")
                                .font(.caption)
                                .foregroundColor(.red)
                            
                            Text("Spread: \(formatCurrency(manager.chartData.spread))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Timeframe selector
                Picker("Timeframe", selection: $chartTimeframe) {
                    ForEach(ChartTimeframe.allCases, id: \.self) { timeframe in
                        Text(timeframe.title).tag(timeframe)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Toggle("Volume", isOn: $showVolume)
                    .toggleStyle(.button)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Market status notice
            if manager.marketStatus == .closed {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.orange)
                    Text("Market Closed - Showing historical data from last trading session")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(manager.marketStatus.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("- Real-time updates active")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            // Chart content
            if manager.isLoading {
                ProgressView("Loading chart data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.chartData.candles.isEmpty {
                VStack {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No chart data available")
                        .font(.headline)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Main candlestick chart
                        CandlestickChart(
                            candles: manager.chartData.candles,
                            geometry: geometry,
                            zoomRange: $zoomRange,
                            isDragging: $isDragging,
                            dragStart: $dragStart,
                            dragEnd: $dragEnd
                        )
                        .frame(height: showVolume ? geometry.size.height * 0.5 : geometry.size.height * 0.7)
                        
                        if showVolume {
                            Divider()
                            
                            // Volume chart
                            VolumeChart(
                                candles: filteredCandlesForVolume,
                                geometry: geometry
                            )
                            .frame(height: geometry.size.height * 0.2)
                        }
                        
                        Divider()
                        
                        // MACD chart
                        MACDChart(
                            candles: manager.chartData.candles,
                            macdLine: manager.chartData.macdLine,
                            signalLine: manager.chartData.signalLine,
                            histogram: manager.chartData.histogram,
                            geometry: geometry,
                            zoomRange: zoomRange
                        )
                        .frame(height: showVolume ? geometry.size.height * 0.3 : geometry.size.height * 0.3)
                    }
                }
                .padding()
            }
            
            // No controls below chart
        }
        .onAppear {
            manager.loadCandlesticks(for: symbol)
        }
        .onDisappear {
            // Don't stop updates - keep WebSocket connections alive
            // manager.stopUpdates()
        }
        .onChange(of: symbol) { newSymbol in
            // Load candlesticks for the new symbol
            manager.loadCandlesticks(for: newSymbol)
        }
        .onChange(of: chartTimeframe) { _ in
            // Reload with new timeframe
            manager.loadCandlesticks(for: symbol)
        }
        .focusable(false)
    }
}

// MARK: - Candlestick Chart Component

struct CandlestickChart: View {
    let candles: [Candle]
    let geometry: GeometryProxy
    @Binding var zoomRange: ClosedRange<Date>?
    @Binding var isDragging: Bool
    @Binding var dragStart: CGPoint
    @Binding var dragEnd: CGPoint
    
    @State private var animatedCandles: [Candle] = []
    @State private var lastCandleCount = 0
    
    var priceRange: ClosedRange<Double> {
        guard !candles.isEmpty else { return 0...100 }
        let prices = candles.flatMap { [$0.high, $0.low] }
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 100
        let padding = (maxPrice - minPrice) * 0.1
        return (minPrice - padding)...(maxPrice + padding)
    }
    
    // Filter candles based on zoom range
    var visibleCandles: [Candle] {
        guard let range = zoomRange else { return animatedCandles }
        return animatedCandles.filter { range.contains($0.timestamp) }
    }
    
    var body: some View {
        ZStack {
            // Grid lines
            GridLinesView(priceRange: priceRange)
            
            // Candles with animation
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(visibleCandles) { candle in
                    CandleView(
                        candle: candle,
                        priceRange: priceRange,
                        geometry: geometry
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.easeInOut(duration: 0.3), value: visibleCandles.count)
                }
            }
            .padding(.horizontal, 4)
            
            // Selection overlay (full height, only x-axis selection)
            if isDragging {
                SelectionOverlay(
                    start: dragStart,
                    end: dragEnd,
                    geometry: geometry,
                    fullHeight: true
                )
            }
            
            // Price axis
            HStack {
                Spacer()
                PriceAxisView(priceRange: priceRange)
                    .frame(width: 60)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .focusable(false)
        .onAppear {
            // Initialize animated candles
            animatedCandles = candles
            lastCandleCount = candles.count
        }
        .onChange(of: candles) { newCandles in
            // Animate new candles
            withAnimation(.easeInOut(duration: 0.5)) {
                // Check if a new candle was added
                if newCandles.count > lastCandleCount {
                    // Add new candles with animation
                    animatedCandles = newCandles
                } else {
                    // Update existing candles
                    animatedCandles = newCandles
                }
                lastCandleCount = newCandles.count
            }
        }
        .onTapGesture(count: 2) {
            // Double-click to reset zoom
            if zoomRange != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    zoomRange = nil
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // Store the start location but only track X position
                        dragStart = CGPoint(x: value.startLocation.x, y: 0)
                    }
                    // Only track horizontal movement
                    dragEnd = CGPoint(x: value.location.x, y: 0)
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Calculate selected time range based on X coordinates only
                    let width = geometry.size.width
                    let startX = min(dragStart.x, dragEnd.x)
                    let endX = max(dragStart.x, dragEnd.x)
                    
                    // Require minimum selection width (at least 20 pixels)
                    guard abs(endX - startX) > 20 else {
                        dragStart = .zero
                        dragEnd = .zero
                        return
                    }
                    
                    // Map x coordinates to candle indices
                    let candleWidth = width / CGFloat(visibleCandles.count)
                    let startIndex = max(0, Int(startX / candleWidth))
                    let endIndex = min(visibleCandles.count - 1, Int(endX / candleWidth))
                    
                    if startIndex < endIndex && endIndex < visibleCandles.count {
                        let startDate = visibleCandles[startIndex].timestamp
                        let endDate = visibleCandles[endIndex].timestamp
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            zoomRange = startDate...endDate
                        }
                    }
                    
                    // Reset drag positions
                    dragStart = .zero
                    dragEnd = .zero
                }
        )
    }
}

// MARK: - Individual Candle View

struct CandleView: View {
    let candle: Candle
    let priceRange: ClosedRange<Double>
    let geometry: GeometryProxy
    
    var body: some View {
        GeometryReader { geo in
            let candleWidth = max(2, geo.size.width - 2)
            let wickWidth = max(1, candleWidth * 0.2)
            
            let yScale = geo.size.height / (priceRange.upperBound - priceRange.lowerBound)
            let highY = CGFloat(priceRange.upperBound - candle.high) * yScale
            let lowY = CGFloat(priceRange.upperBound - candle.low) * yScale
            let openY = CGFloat(priceRange.upperBound - candle.open) * yScale
            let closeY = CGFloat(priceRange.upperBound - candle.close) * yScale
            
            ZStack {
                // Wick
                Rectangle()
                    .fill(candle.isGreen ? Color.green : Color.red)
                    .frame(width: wickWidth, height: lowY - highY)
                    .position(x: geo.size.width / 2, y: (highY + lowY) / 2)
                
                // Body
                Rectangle()
                    .fill(candle.isGreen ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                    .frame(width: candleWidth, height: abs(closeY - openY))
                    .position(x: geo.size.width / 2, y: (openY + closeY) / 2)
                    .overlay(
                        Rectangle()
                            .stroke(candle.isGreen ? Color.green : Color.red, lineWidth: 1)
                            .frame(width: candleWidth, height: abs(closeY - openY))
                            .position(x: geo.size.width / 2, y: (openY + closeY) / 2)
                    )
                
                // No selection or hover highlights
            }
        }
    }
}

// MARK: - Volume Chart Component

struct VolumeChart: View {
    let candles: [Candle]
    let geometry: GeometryProxy
    
    var maxVolume: Int {
        candles.map { $0.volume }.max() ?? 1
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(candles) { candle in
                VolumeBar(
                    candle: candle,
                    maxVolume: maxVolume
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
                .animation(.easeInOut(duration: 0.3), value: candles.count)
            }
        }
        .padding(.horizontal, 4)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}

struct VolumeBar: View {
    let candle: Candle
    let maxVolume: Int
    
    var body: some View {
        GeometryReader { geo in
            let barHeight = CGFloat(candle.volume) / CGFloat(maxVolume) * geo.size.height
            
            VStack {
                Spacer()
                Rectangle()
                    .fill(candle.isGreen ? Color.green.opacity(0.6) : Color.red.opacity(0.6))
                    .frame(height: barHeight)
            }
        }
    }
}

// MARK: - Supporting Views

struct GridLinesView: View {
    let priceRange: ClosedRange<Double>
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Horizontal grid lines
                ForEach(0..<5) { i in
                    let y = geo.size.height * CGFloat(i) / 4
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
    }
}

struct PriceAxisView: View {
    let priceRange: ClosedRange<Double>
    
    var body: some View {
        VStack {
            ForEach(0..<5) { i in
                let price = priceRange.upperBound - (priceRange.upperBound - priceRange.lowerBound) * Double(i) / 4
                Text(formatCurrency(price))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if i < 4 {
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Removed CandleInfoBar and InfoItem - no longer showing OHLCV on hover

// MARK: - Selection Overlay

struct SelectionOverlay: View {
    let start: CGPoint
    let end: CGPoint
    let geometry: GeometryProxy
    let fullHeight: Bool
    
    var selectionRect: CGRect {
        let x = min(start.x, end.x)
        let width = abs(end.x - start.x)
        
        if fullHeight {
            // Use full height of the chart
            return CGRect(x: x, y: 0, width: width, height: geometry.size.height)
        } else {
            // Original behavior (not used anymore but kept for compatibility)
            let y = min(start.y, end.y)
            let height = abs(end.y - start.y)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.1))
            .overlay(
                Rectangle()
                    .stroke(Color.blue, lineWidth: 1)
            )
            .frame(width: selectionRect.width, height: selectionRect.height)
            .position(x: selectionRect.midX, y: geometry.size.height / 2)
    }
}

// Removed ZoomControlBar - no UI elements below chart

// MARK: - Formatting Helpers

func formatVolume(_ volume: Int) -> String {
    if volume >= 1_000_000 {
        return String(format: "%.2fM", Double(volume) / 1_000_000)
    } else if volume >= 1_000 {
        return String(format: "%.1fK", Double(volume) / 1_000)
    }
    return "\(volume)"
}

// MARK: - MACD Chart Component

struct MACDChart: View {
    let candles: [Candle]
    let macdLine: [Double]
    let signalLine: [Double]
    let histogram: [Double]
    let geometry: GeometryProxy
    let zoomRange: ClosedRange<Date>?
    
    var visibleRange: ClosedRange<Int> {
        guard let zoomRange = zoomRange else {
            return 0...(candles.count - 1)
        }
        
        let startIndex = candles.firstIndex { zoomRange.contains($0.timestamp) } ?? 0
        let endIndex = candles.lastIndex { zoomRange.contains($0.timestamp) } ?? (candles.count - 1)
        return startIndex...endIndex
    }
    
    var macdRange: ClosedRange<Double> {
        let allValues = macdLine + signalLine + histogram
        guard !allValues.isEmpty else { return -1...1 }
        
        let validValues = allValues.filter { !$0.isNaN && !$0.isInfinite }
        guard !validValues.isEmpty else { return -1...1 }
        
        let minValue = validValues.min() ?? -1
        let maxValue = validValues.max() ?? 1
        let padding = abs(maxValue - minValue) * 0.1
        return (minValue - padding)...(maxValue + padding)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(NSColor.textBackgroundColor)
            
            // Grid lines
            MACDGridLines(range: macdRange)
            
            // Zero line
            GeometryReader { geo in
                let zeroY = mapValueToY(0, in: macdRange, height: geo.size.height)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: zeroY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: zeroY))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            }
            
            // Histogram bars
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 1) {
                    ForEach(visibleRange, id: \.self) { index in
                        if index < histogram.count {
                            MACDHistogramBar(
                                value: histogram[index],
                                range: macdRange,
                                height: geo.size.height
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // MACD line
            if !macdLine.isEmpty {
                GeometryReader { geo in
                    Path { path in
                        let width = geo.size.width
                        let count = visibleRange.count
                        
                        for (offset, index) in visibleRange.enumerated() {
                            if index < macdLine.count {
                                let x = (CGFloat(offset) / CGFloat(max(1, count - 1))) * width
                                let y = mapValueToY(macdLine[index], in: macdRange, height: geo.size.height)
                                
                                if offset == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                }
                .padding(.horizontal, 4)
            }
            
            // Signal line
            if !signalLine.isEmpty {
                GeometryReader { geo in
                    Path { path in
                        let width = geo.size.width
                        let count = visibleRange.count
                        
                        for (offset, index) in visibleRange.enumerated() {
                            if index < signalLine.count {
                                let x = (CGFloat(offset) / CGFloat(max(1, count - 1))) * width
                                let y = mapValueToY(signalLine[index], in: macdRange, height: geo.size.height)
                                
                                if offset == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                    }
                    .stroke(Color.orange, lineWidth: 2)
                }
                .padding(.horizontal, 4)
            }
            
            // Labels
            VStack {
                HStack {
                    Text("MACD")
                        .font(.caption)
                        .fontWeight(.bold)
                    
                    if let lastMACD = macdLine.last {
                        Text(String(format: "%.4f", lastMACD))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let lastSignal = signalLine.last {
                        Text(String(format: "Signal: %.4f", lastSignal))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }
                .padding(4)
                
                Spacer()
            }
            
            // Value axis
            HStack {
                Spacer()
                MACDValueAxis(range: macdRange)
                    .frame(width: 60)
            }
        }
        .cornerRadius(8)
    }
    
    func mapValueToY(_ value: Double, in range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1 - normalizedValue)
    }
}

struct MACDHistogramBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let zeroY = mapValueToY(0, in: range, height: height)
            let valueY = mapValueToY(value, in: range, height: height)
            let barHeight = abs(valueY - zeroY)
            let barY = min(zeroY, valueY)
            
            Rectangle()
                .fill(value >= 0 ? Color.green.opacity(0.6) : Color.red.opacity(0.6))
                .frame(height: barHeight)
                .position(x: geo.size.width / 2, y: barY + barHeight / 2)
        }
    }
    
    func mapValueToY(_ value: Double, in range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1 - normalizedValue)
    }
}

struct MACDGridLines: View {
    let range: ClosedRange<Double>
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Horizontal grid lines
                ForEach(0..<5) { i in
                    let y = geo.size.height * CGFloat(i) / 4
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
    }
}

struct MACDValueAxis: View {
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack {
            ForEach(0..<5) { i in
                let value = range.upperBound - (range.upperBound - range.lowerBound) * Double(i) / 4
                Text(String(format: "%.4f", value))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if i < 4 {
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}