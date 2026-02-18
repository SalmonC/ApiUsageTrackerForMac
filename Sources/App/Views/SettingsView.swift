import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var accounts: [APIAccount] = []
    @State private var expandedStates: [UUID: Bool] = [:]
    @State private var refreshInterval: Int = 5
    @State private var hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    @State private var isRecordingHotkey: Bool = false
    @State private var hotkeyError: String?
    @State private var saveButtonState: SaveButtonState = .normal
    
    enum SaveButtonState {
        case normal
        case saved
    }
    
    var body: some View {
        TabView {
            generalSettingsView
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            accountsSettingsView
                .tabItem {
                    Label("API Accounts", systemImage: "key")
                }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                Text("Refresh Interval")
                    .font(.headline)
                Picker("", selection: $refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            Group {
                Text("Hotkey")
                    .font(.headline)
                Text("Press the button below and enter your desired key combination (must include at least one modifier: ⌘⇧⌥⌃)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button(action: {
                        hotkeyError = nil
                        isRecordingHotkey = true
                    }) {
                        HStack {
                            if isRecordingHotkey {
                                Text("Press keys...")
                                    .foregroundColor(.red)
                            } else {
                                Text(hotkey.displayString)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .background(
                        HotkeyRecorderView(isRecording: $isRecordingHotkey, hotkey: $hotkey, onValidationError: { error in
                            hotkeyError = error
                        })
                    )
                    
                    Button(action: {
                        hotkey = HotkeySetting.defaultHotkey
                        hotkeyError = nil
                    }) {
                        Text("Restore Default")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                if let error = hotkeyError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.orange)
                    }
                    .font(.caption)
                }
                
                Text("Current hotkey: \(hotkey.displayString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                saveSettings()
                collapseAllAccounts()
            }) {
                HStack {
                    if saveButtonState == .saved {
                        Image(systemName: "checkmark")
                    }
                    Text(saveButtonState == .saved ? "Saved!" : "Save Settings")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(saveButtonState == .saved ? .green : .gray)
        }
        .padding()
    }
    
    private var accountsSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("API Accounts")
                    .font(.headline)
                Spacer()
                Button(action: addAccount) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            
            if accounts.isEmpty {
                VStack {
                    Spacer()
                    Text("No API accounts configured")
                        .foregroundColor(.secondary)
                    Text("Click + to add an account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($accounts) { $account in
                            AccountRowView(
                                account: $account,
                                isExpanded: Binding(
                                    get: { expandedStates[account.id] ?? false },
                                    set: { expandedStates[account.id] = $0 }
                                ),
                                onDelete: {
                                    deleteAccount(account)
                                },
                                onProviderChanged: { newProvider in
                                    if account.name.isEmpty || account.name == "New Account" {
                                        account.name = newProvider.displayName
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            Button(action: {
                saveSettings()
                collapseAllAccounts()
            }) {
                HStack {
                    if saveButtonState == .saved {
                        Image(systemName: "checkmark")
                    }
                    Text(saveButtonState == .saved ? "Saved!" : "Save")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(saveButtonState == .saved ? .green : .gray)
        }
        .padding()
    }
    
    private func loadSettings() {
        let settings = Storage.shared.loadSettings()
        accounts = settings.accounts
        refreshInterval = settings.refreshInterval
        hotkey = settings.hotkey
        collapseAllAccounts()
    }
    
    private func saveSettings() {
        let settings = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey
        )
        viewModel.saveSettings(settings)
        
        withAnimation {
            saveButtonState = .saved
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                saveButtonState = .normal
            }
        }
    }
    
    private func addAccount() {
        let newAccount = APIAccount(name: "New Account", provider: .miniMax, apiKey: "", isEnabled: true)
        accounts.append(newAccount)
        
        for i in accounts.indices {
            if accounts[i].id != newAccount.id {
                expandedStates[accounts[i].id] = false
            }
        }
        expandedStates[newAccount.id] = true
    }
    
    private func deleteAccount(_ account: APIAccount) {
        accounts.removeAll { $0.id == account.id }
        expandedStates.removeValue(forKey: account.id)
    }
    
    private func collapseAllAccounts() {
        for i in accounts.indices {
            expandedStates[accounts[i].id] = false
        }
    }
}

struct AccountRowView: View {
    @Binding var account: APIAccount
    @Binding var isExpanded: Bool
    var onDelete: () -> Void
    var onProviderChanged: ((APIProvider) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                        
                        if isExpanded {
                            TextField("Account Name", text: $account.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        } else {
                            Text(account.name.isEmpty ? "New Account" : account.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text("Show")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $account.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Provider", selection: $account.provider) {
                        ForEach(APIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: account.provider) { _, newValue in
                        onProviderChanged?(newValue)
                    }
                    
                    SecureField("API Key", text: $account.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeySetting
    var onValidationError: ((String) -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let validationError = HotkeySetting.validate(keyCode: keyCode, modifiers: modifiers)
            if let error = validationError {
                onValidationError?(error)
                isRecording = false
            } else {
                hotkey = HotkeySetting(keyCode: keyCode, modifiers: modifiers)
                isRecording = false
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let recorderView = nsView as? KeyRecorderNSView {
            recorderView.isRecording = isRecording
        }
    }
}

class KeyRecorderNSView: NSView {
    var isRecording: Bool = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }
    var onKeyRecorded: ((UInt16, UInt32) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        let modifiers = event.modifierFlags.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.control.rawValue)
        
        guard modifiers != 0 else { return }
        
        onKeyRecorded?(UInt16(event.keyCode), UInt32(modifiers))
    }
}
