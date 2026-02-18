import SwiftUI

struct SettingsView: View {
    private let suiteName = "group.com.mactools.apiusagetracker"
    
    @AppStorage("miniMaxCodingAPIKey", store: UserDefaults(suiteName: "group.com.mactools.apiusagetracker"))
    private var miniMaxCodingAPIKey = ""
    
    @AppStorage("miniMaxPayAsGoAPIKey", store: UserDefaults(suiteName: "group.com.mactools.apiusagetracker"))
    private var miniMaxPayAsGoAPIKey = ""
    
    @AppStorage("glmAPIKey", store: UserDefaults(suiteName: "group.com.mactools.apiusagetracker"))
    private var glmAPIKey = ""
    
    @AppStorage("refreshInterval", store: UserDefaults(suiteName: "group.com.mactools.apiusagetracker"))
    private var refreshInterval = 5
    
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
                Picker("Refresh Interval", selection: $refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
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
                    SecureField("Enter API Key", text: $miniMaxCodingAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("MiniMax Pay-As-You-Go API Key")
                        .font(.headline)
                    SecureField("Enter API Key", text: $miniMaxPayAsGoAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("GLM (智谱AI) API Key")
                        .font(.headline)
                    SecureField("Enter API Key", text: $glmAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                Spacer()
                
                Text("Your API keys are stored in the app's shared container.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}
