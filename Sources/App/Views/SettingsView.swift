import SwiftUI

struct SettingsView: View {
    private let suiteName = "group.com.mactools.macusagetracker"
    
    @AppStorage("miniMaxCodingAPIKey", store: UserDefaults(suiteName: "group.com.mactools.macusagetracker"))
    private var miniMaxCodingAPIKey = ""
    
    @AppStorage("miniMaxPayAsGoAPIKey", store: UserDefaults(suiteName: "group.com.mactools.macusagetracker"))
    private var miniMaxPayAsGoAPIKey = ""
    
    @AppStorage("glmAPIKey", store: UserDefaults(suiteName: "group.com.mactools.macusagetracker"))
    private var glmAPIKey = ""
    
    @AppStorage("refreshInterval", store: UserDefaults(suiteName: "group.com.mactools.macusagetracker"))
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
        .frame(width: 450, height: 300)
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
        Form {
            Section {
                SecureField("MiniMax Coding Plan API Key", text: $miniMaxCodingAPIKey)
                SecureField("MiniMax Pay-As-You-Go API Key", text: $miniMaxPayAsGoAPIKey)
                SecureField("GLM (智谱AI) API Key", text: $glmAPIKey)
            } header: {
                Text("API Keys")
            } footer: {
                Text("Your API keys are stored in the app's shared container.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
