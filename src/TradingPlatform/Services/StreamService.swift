import Foundation
import Combine

// MARK: - SSE Event Types
enum SSEEventType: String {
    case connected
    case metadata
    case batch
    case match
    case progress
    case complete
    case error
}

// MARK: - SSE Event Data Models
struct SSEEvent {
    let type: SSEEventType
    let data: [String: Any]
}

struct StockBatch: Codable {
    let type: String
    let batchNumber: Int?
    let totalBatches: Int?
    let stocks: [StreamedStock]
    let count: Int
    let progress: Int?
    
    enum CodingKeys: String, CodingKey {
        case type
        case batchNumber = "batch_number"
        case totalBatches = "total_batches"
        case stocks
        case count
        case progress
    }
}

struct StreamedStock: Codable {
    let symbol: String
    let name: String?
    let exchange: String?
    let tradable: Bool?
    let marginable: Bool?
    let shortable: Bool?
    let easyToBorrow: Bool?
    let price: Double?
    let prevClose: Double?
    let change: Double?
    let changePercent: Double?
    let volume: Int?
    
    enum CodingKeys: String, CodingKey {
        case symbol, name, exchange, tradable, marginable, shortable, price, volume, change
        case easyToBorrow = "easy_to_borrow"
        case prevClose = "prev_close"
        case changePercent = "change_percent"
    }
}

// MARK: - Stream Service
class StreamService: NSObject, ObservableObject {
    static let shared = StreamService()
    
    @Published var isStreaming = false
    @Published var streamProgress = 0
    @Published var totalStocks = 0
    @Published var receivedStocks = 0
    @Published var lastError: String?
    
    // Publishers for stock data
    let stockBatchPublisher = PassthroughSubject<[StreamedStock], Never>()
    let filteredStockPublisher = PassthroughSubject<StreamedStock, Never>()
    let streamCompletePublisher = PassthroughSubject<Bool, Never>()
    
    private var eventSource: URLSession?
    private var streamTask: URLSessionDataTask?
    private let baseURL: String
    
    override init() {
        // Use the same base URL as API service
        let apiURL = AppConfiguration.apiBaseURL
        self.baseURL = apiURL
            .replacingOccurrences(of: "https://", with: "https://")
            .replacingOccurrences(of: "http://", with: "http://")
        
        super.init()
    }
    
    // MARK: - Stream All Stocks
    func streamAllStocks(batchSize: Int = 100) {
        guard !isStreaming else { return }
        
        let urlString = "\(baseURL)/stream/all-stocks?batch_size=\(batchSize)"
        guard let url = URL(string: urlString) else {
            print("Invalid stream URL: \(urlString)")
            return
        }
        
        startStream(from: url)
    }
    
    // MARK: - Stream Filtered Stocks
    func streamFilteredStocks(priceMin: Double = 2.0, priceMax: Double = 20.0, minGain: Double = 10.0) {
        guard !isStreaming else { return }
        
        let urlString = "\(baseURL)/stream/filtered-stocks?price_min=\(priceMin)&price_max=\(priceMax)&min_gain=\(minGain)"
        guard let url = URL(string: urlString) else {
            print("Invalid stream URL: \(urlString)")
            return
        }
        
        startStream(from: url)
    }
    
    // MARK: - Stop Streaming
    func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamProgress = 0
    }
    
    // MARK: - Private Methods
    private func startStream(from url: URL) {
        isStreaming = true
        streamProgress = 0
        receivedStocks = 0
        lastError = nil
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 300 // 5 minutes
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        streamTask = session.dataTask(with: request)
        streamTask?.resume()
        
        print("Started streaming from: \(url)")
    }
    
    private func processSSEData(_ data: String) {
        // SSE format: "data: {json}\n\n"
        let lines = data.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                processJSONEvent(jsonString)
            }
        }
    }
    
    private func processJSONEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                handleEvent(json)
            }
        } catch {
            print("Failed to parse SSE JSON: \(error)")
        }
    }
    
    private func handleEvent(_ json: [String: Any]) {
        guard let typeString = json["type"] as? String else { return }
        
        switch typeString {
        case "connected":
            print("Stream connected: \(json["message"] ?? "")")
            
        case "metadata":
            if let total = json["total"] as? Int {
                totalStocks = total
                print("Stream metadata: \(total) stocks to receive")
            }
            
        case "batch":
            if let stocks = json["stocks"] as? [[String: Any]] {
                let stockData = stocks.compactMap { dict -> StreamedStock? in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? JSONDecoder().decode(StreamedStock.self, from: data)
                }
                
                receivedStocks += stockData.count
                
                if let progress = json["progress"] as? Int {
                    streamProgress = progress
                }
                
                // Publish batch to subscribers
                stockBatchPublisher.send(stockData)
                
                print("Received batch: \(stockData.count) stocks (total: \(receivedStocks)/\(totalStocks))")
            }
            
        case "match":
            if let stockDict = json["stock"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: stockDict),
               let stock = try? JSONDecoder().decode(StreamedStock.self, from: data) {
                
                receivedStocks += 1
                filteredStockPublisher.send(stock)
                
                if let scanned = json["scanned"] as? Int,
                   let total = json["total"] as? Int {
                    streamProgress = Int((Double(scanned) / Double(total)) * 100)
                }
                
                print("Found match: \(stock.symbol) +\(stock.changePercent ?? 0)%")
            }
            
        case "progress":
            if let progress = json["progress"] as? Int {
                streamProgress = progress
            }
            if let scanned = json["scanned"] as? Int,
               let matches = json["matches"] as? Int {
                print("Scan progress: \(scanned) scanned, \(matches) matches")
            }
            
        case "complete":
            isStreaming = false
            streamProgress = 100
            streamCompletePublisher.send(true)
            
            if let total = json["total"] as? Int {
                print("Stream complete: \(total) stocks received")
            } else if let matches = json["matches"] as? Int {
                print("Scan complete: \(matches) matches found")
            }
            
        case "error":
            if let message = json["message"] as? String {
                lastError = message
                print("Stream error: \(message)")
            }
            isStreaming = false
            streamCompletePublisher.send(false)
            
        default:
            print("Unknown SSE event type: \(typeString)")
        }
    }
}

// MARK: - URLSession Delegate
extension StreamService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let string = String(data: data, encoding: .utf8) {
            processSSEData(string)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        isStreaming = false
        
        if let error = error {
            lastError = error.localizedDescription
            print("Stream error: \(error)")
            streamCompletePublisher.send(false)
        }
    }
}

// MARK: - Stock Conversion
extension StreamService {
    func convertToStock(_ streamedStock: StreamedStock) -> Stock {
        return Stock(
            symbol: streamedStock.symbol,
            name: streamedStock.name,
            price: streamedStock.price,
            changePercent: streamedStock.changePercent,
            changeAmount: streamedStock.change
        )
    }
}