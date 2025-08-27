import Foundation
import Combine

class TradingManager: ObservableObject {
    @Published var positions: [Position] = []
    @Published var orders: [Order] = []
    @Published var gapOpportunities: [GapOpportunity] = []
    @Published var accountInfo: AccountInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = APIService.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    
    init() {
        startPeriodicRefresh()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    func loadInitialData() {
        loadAccountInfo()
        loadPositions()
        loadOrders()
        loadGapOpportunities()
    }
    
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }
    
    private func refreshData() {
        loadAccountInfo()
        loadPositions()
        loadGapOpportunities()
    }
    
    // MARK: - Account Info
    func loadAccountInfo() {
        apiService.getAccountInfo()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load account info: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.accountInfo = response.data
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = response.error ?? "Failed to load account info"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Positions
    func loadPositions() {
        apiService.getPositions()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load positions: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.positions = response.data ?? []
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = response.error ?? "Failed to load positions"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Orders
    func loadOrders() {
        apiService.getOrders()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load orders: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.orders = response.data ?? []
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = response.error ?? "Failed to load orders"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func placeOrder(symbol: String, quantity: Double, side: String, orderType: String, limitPrice: Double? = nil) {
        isLoading = true
        
        apiService.placeOrder(symbol: symbol, quantity: quantity, side: side, orderType: orderType, limitPrice: limitPrice)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to place order: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.loadOrders() // Refresh orders
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = response.error ?? "Failed to place order"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Gap Scanner
    func loadGapOpportunities() {
        apiService.getGapOpportunities()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Failed to load gap opportunities: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.gapOpportunities = response.data ?? []
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = response.error ?? "Failed to load gap opportunities"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Computed Properties
    var totalPortfolioValue: Double {
        accountInfo?.portfolioValue ?? 0.0
    }
    
    var totalUnrealizedPnL: Double {
        positions.reduce(0) { $0 + $1.unrealizedPnL }
    }
    
    var totalUnrealizedPnLPercent: Double {
        let totalCost = positions.reduce(0) { $0 + ($1.quantity * $1.averagePrice) }
        return totalCost > 0 ? (totalUnrealizedPnL / totalCost) * 100 : 0
    }
}