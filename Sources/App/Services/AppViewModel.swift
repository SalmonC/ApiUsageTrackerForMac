import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    @Published var settings = Storage.shared.loadSettings()
    
    private let services: [UsageService] = [MiniMaxCodingService()]
    
    init() {
        loadCachedData()
    }
    
    private func loadCachedData() {
        usageData = Storage.shared.loadUsageData()
    }
    
    func refreshAll() async {
        isLoading = true
        var newData: [UsageData] = []
        
        for service in services {
            let apiKey: String
            switch service.serviceType {
            case .miniMaxCoding:
                apiKey = settings.miniMaxCodingAPIKey
            case .miniMaxPayAsGo:
                apiKey = settings.miniMaxPayAsGoAPIKey
            case .glm:
                apiKey = settings.glmAPIKey
            }
            
            guard !apiKey.isEmpty else {
                newData.append(UsageData(
                    serviceType: service.serviceType,
                    tokenRemaining: nil,
                    tokenUsed: nil,
                    tokenTotal: nil,
                    refreshTime: nil,
                    lastUpdated: Date(),
                    errorMessage: "API Key not configured"
                ))
                continue
            }
            
            do {
                let data = try await service.fetchUsage(apiKey: apiKey)
                newData.append(data)
            } catch {
                newData.append(UsageData(
                    serviceType: service.serviceType,
                    tokenRemaining: nil,
                    tokenUsed: nil,
                    tokenTotal: nil,
                    refreshTime: nil,
                    lastUpdated: Date(),
                    errorMessage: error.localizedDescription
                ))
            }
        }
        
        usageData = newData
        Storage.shared.saveUsageData(newData)
        
        WidgetCenter.shared.reloadAllTimelines()
        
        isLoading = false
    }
    
    func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings
        Storage.shared.saveSettings(newSettings)
    }
}
