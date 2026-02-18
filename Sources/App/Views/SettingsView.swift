import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var settingsVM = SettingsViewModel()
    
    var body: some View {
        TabView {
            generalSettingsView
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            apiKeysSettingsView
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
        }
        .tabViewStyle(.automatic)
    }
    
    private var generalSettingsView: some View {
        Form {
            Section {
                Picker("Refresh Interval", selection: $settingsVM.refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                .onChange(of: settingsVM.refreshInterval) { _, _ in
                    saveAndRefresh()
                }
            } header: {
                Text("Refresh")
            }
        }
        .padding()
    }
    
    private var apiKeysSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MiniMax Coding Plan API Key")
                        .font(.headline)
                    SecureField("Enter API Key", text: $settingsVM.miniMaxCodingAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("MiniMax Pay-As-You-Go API Key")
                        .font(.headline)
                    SecureField("Enter API Key", text: $settingsVM.miniMaxPayAsGoAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("GLM (智谱AI) API Key")
                        .font(.headline)
                    SecureField("Enter API Key", text: $settingsVM.glmAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                Button(action: {
                    saveAndRefresh()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Settings")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                if settingsVM.showSavedMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings saved! Refreshing...")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
                
                Spacer()
                
                Text("Your API keys are stored in the app's shared container.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    private func saveAndRefresh() {
        settingsVM.save()
        viewModel.loadSettings()
        Task {
            await viewModel.refreshAll()
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var miniMaxCodingAPIKey: String = ""
    @Published var miniMaxPayAsGoAPIKey: String = ""
    @Published var glmAPIKey: String = ""
    @Published var refreshInterval: Int = 5
    @Published var showSavedMessage: Bool = false
    
    private let storage = Storage.shared
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        let settings = storage.loadSettings()
        miniMaxCodingAPIKey = settings.miniMaxCodingAPIKey
        miniMaxPayAsGoAPIKey = settings.miniMaxPayAsGoAPIKey
        glmAPIKey = settings.glmAPIKey
        refreshInterval = settings.refreshInterval
    }
    
    func save() {
        let settings = AppSettings(
            miniMaxCodingAPIKey: miniMaxCodingAPIKey,
            miniMaxPayAsGoAPIKey: miniMaxPayAsGoAPIKey,
            glmAPIKey: glmAPIKey,
            refreshInterval: refreshInterval,
            enabledServices: [.miniMaxCoding]
        )
        storage.saveSettings(settings)
        
        showSavedMessage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showSavedMessage = false
        }
    }
}
