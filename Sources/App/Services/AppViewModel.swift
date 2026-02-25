import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: [UsageData] = []
    @Published var isLoading = false
    @Published var settings = Storage.shared.loadSettings()
    @Published var secondsUntilTokenRefresh: Int = 0
    
    private var refreshTimer: Timer?
    var onSettingsSaved: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    
    init() {
        loadSettings()
        loadCachedData()
        Storage.shared.saveRefreshInterval(settings.refreshInterval)
        startCountdownTimer()
    }
    
    func loadSettings() {
        settings = Storage.shared.loadSettings()
    }
    
    private func loadCachedData() {
        let cached = Storage.shared.loadUsageData()
        if !cached.isEmpty {
            usageData = cached
        }
    }
    
    private func startCountdownTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        updateTokenRefreshCountdown()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.secondsUntilTokenRefresh > 0 {
                    self.secondsUntilTokenRefresh -= 1
                } else {
                    self.updateTokenRefreshCountdown()
                }
            }
        }
    }
    
    private func updateTokenRefreshCountdown() {
        let now = Date()
        var earliestRefresh: Date?
        
        for data in usageData {
            if let refreshTime = data.refreshTime, refreshTime > now {
                if earliestRefresh == nil || refreshTime < earliestRefresh! {
                    earliestRefresh = refreshTime
                }
            }
        }
        
        if let refresh = earliestRefresh {
            secondsUntilTokenRefresh = Int(refresh.timeIntervalSince(now))
        } else {
            secondsUntilTokenRefresh = 0
        }
    }
    
    func resetCountdown() {
        startCountdownTimer()
    }
    
    func refreshAll() async {
        isLoading = true
        loadSettings()
        
        var newData: [UsageData] = []
        
        for account in settings.accounts where account.isEnabled && !account.apiKey.isEmpty {
            let service = getService(for: account.provider)
            
            do {
                let result = try await service.fetchUsage(apiKey: account.apiKey)
                newData.append(UsageData(
                    accountId: account.id,
                    accountName: account.name.isEmpty ? account.provider.displayName : account.name,
                    provider: account.provider,
                    tokenRemaining: result.remaining,
                    tokenUsed: result.used,
                    tokenTotal: result.total,
                    refreshTime: result.refreshTime,
                    lastUpdated: Date(),
                    errorMessage: nil,
                    monthlyRemaining: result.monthlyRemaining,
                    monthlyTotal: result.monthlyTotal,
                    monthlyUsed: result.monthlyUsed,
                    monthlyRefreshTime: result.monthlyRefreshTime,
                    nextRefreshTime: result.nextRefreshTime
                ))
            } catch {
                newData.append(UsageData(
                    accountId: account.id,
                    accountName: account.name.isEmpty ? account.provider.displayName : account.name,
                    provider: account.provider,
                    tokenRemaining: nil,
                    tokenUsed: nil,
                    tokenTotal: nil,
                    refreshTime: nil,
                    lastUpdated: Date(),
                    errorMessage: error.localizedDescription,
                    monthlyRemaining: nil,
                    monthlyTotal: nil,
                    monthlyUsed: nil,
                    monthlyRefreshTime: nil,
                    nextRefreshTime: nil
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
        Storage.shared.saveRefreshInterval(newSettings.refreshInterval)
        onSettingsSaved?()
    }
    
    func openSettings() {
        onOpenSettings?()
    }
    
    var hotkeyDisplayString: String {
        settings.hotkey.displayString
    }
}
