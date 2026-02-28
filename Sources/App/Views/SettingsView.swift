import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var accounts: [APIAccount] = []
    @State private var autoNamedAccountIDs: Set<UUID> = []
    @State private var expandedStates: [UUID: Bool] = [:]
    @State private var refreshInterval: Int = 5
    @State private var hotkey: HotkeySetting = HotkeySetting(keyCode: 32, modifiers: UInt32(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue))
    @State private var isRecordingHotkey: Bool = false
    @State private var hotkeyBeforeRecording: HotkeySetting?
    @State private var hotkeyError: String?
    @State private var saveButtonState: SaveButtonState = .normal
    @State private var savedDraftSignature: String = ""
    @State private var pendingDeleteAccount: APIAccount?
    
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
        .alert("Delete Account?", isPresented: pendingDeleteBinding) {
            Button("Delete", role: .destructive) {
                if let account = pendingDeleteAccount {
                    deleteAccount(account)
                }
                pendingDeleteAccount = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: {
            Text("This will remove the account configuration and delete the stored API key from Keychain.")
        }
    }
    
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                HStack {
                    Text("Refresh Interval")
                        .font(.headline)
                    Spacer()
                    if hasUnsavedChanges {
                        Label("Unsaved Changes", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
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
                        hotkeyBeforeRecording = hotkey
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
                        HotkeyRecorderView(
                            isRecording: $isRecordingHotkey,
                            hotkey: $hotkey,
                            onValidationError: { error in
                                hotkeyError = error
                                hotkeyBeforeRecording = nil
                            },
                            onRecordingCancelled: {
                                cancelHotkeyRecording()
                            },
                            onRecordingCompleted: {
                                hotkeyBeforeRecording = nil
                            }
                        )
                    )
                    
                    Button(action: {
                        hotkey = HotkeySetting.defaultHotkey
                        hotkeyError = nil
                    }) {
                        Text("Restore Default")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if isRecordingHotkey {
                        Button("Cancel") {
                            cancelHotkeyRecording()
                        }
                        .buttonStyle(.bordered)
                    }
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
                if isRecordingHotkey {
                    Text("点击其他位置、按 Esc 或使用 Cancel 按钮取消录入")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
                    Text(saveButtonTitle(primary: true))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(saveButtonTintColor)
            .disabled(!hasUnsavedChanges && saveButtonState != .saved)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var accountsSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("API Accounts")
                    .font(.headline)
                Spacer()
                if hasUnsavedChanges {
                    Text("Unsaved")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Button(action: addAccount) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            if accounts.isEmpty {
                VStack {
                    Text("No API accounts configured")
                        .foregroundColor(.secondary)
                    Text("Click + to add an account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                                    pendingDeleteAccount = account
                                },
                                onNameEditFinished: { originalName, editedName in
                                    let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        account.name = account.provider.displayName
                                        autoNamedAccountIDs.insert(account.id)
                                    } else if editedName != originalName {
                                        autoNamedAccountIDs.remove(account.id)
                                    }
                                },
                                onProviderChanged: { oldProvider, newProvider in
                                    let shouldFollowProvider = autoNamedAccountIDs.contains(account.id)
                                    if shouldFollowProvider {
                                        account.name = newProvider.displayName
                                        autoNamedAccountIDs.insert(account.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            }

            if !APIProvider.unsupportedForRemainingQuotaQuery.isEmpty {
                unsupportedProviderNoticeCard
            }
            
            Button(action: {
                saveSettings()
                collapseAllAccounts()
            }) {
                HStack {
                    if saveButtonState == .saved {
                        Image(systemName: "checkmark")
                    }
                    Text(saveButtonTitle(primary: false))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(saveButtonTintColor)
            .disabled(!hasUnsavedChanges && saveButtonState != .saved)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unsupportedProviderNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text("暂不支持余量查询的供应商")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("以下供应商不会出现在新增条目的 Provider 选项中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(APIProvider.unsupportedForRemainingQuotaQuery) { provider in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: provider.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(provider.remainingQuotaQueryUnsupportedReason ?? "暂不支持")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.07),
                            Color.orange.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
    
    private func loadSettings() {
        // Reuse the in-memory settings from the shared view model to avoid an extra
        // Keychain read prompt every time the settings window is opened.
        let settings = viewModel.settings
        accounts = settings.accounts
        autoNamedAccountIDs = []
        refreshInterval = settings.refreshInterval
        hotkey = settings.hotkey
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
        hotkeyError = nil
        saveButtonState = .normal
        collapseAllAccounts()
        savedDraftSignature = currentDraftSignature()
    }
    
    private func saveSettings() {
        let settings = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey
        )
        viewModel.saveSettings(settings)
        savedDraftSignature = currentDraftSignature()
        
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
        let defaultProvider: APIProvider = .miniMax
        let newAccount = APIAccount(name: defaultProvider.displayName, provider: defaultProvider, apiKey: "", isEnabled: true)
        accounts.insert(newAccount, at: 0)
        autoNamedAccountIDs.insert(newAccount.id)
        
        for i in accounts.indices {
            if accounts[i].id != newAccount.id {
                expandedStates[accounts[i].id] = false
            }
        }
        expandedStates[newAccount.id] = true
    }

    private func cancelHotkeyRecording() {
        guard isRecordingHotkey else { return }
        if let original = hotkeyBeforeRecording {
            hotkey = original
        }
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
    }
    
    private func deleteAccount(_ account: APIAccount) {
        accounts.removeAll { $0.id == account.id }
        autoNamedAccountIDs.remove(account.id)
        expandedStates.removeValue(forKey: account.id)
        // Keychain deletion is handled on save via Storage.saveSettings(_:), so draft edits
        // (add/remove before save) do not trigger extra Keychain authorization prompts.
    }
    
    private func collapseAllAccounts() {
        for i in accounts.indices {
            expandedStates[accounts[i].id] = false
        }
    }

    private var hasUnsavedChanges: Bool {
        currentDraftSignature() != savedDraftSignature
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteAccount != nil },
            set: { newValue in
                if !newValue { pendingDeleteAccount = nil }
            }
        )
    }

    private func saveButtonTitle(primary: Bool) -> String {
        if saveButtonState == .saved {
            return "Saved!"
        }
        if !hasUnsavedChanges {
            return primary ? "No Changes" : "No Changes"
        }
        return primary ? "Save Settings" : "Save"
    }

    private var saveButtonTintColor: Color {
        if saveButtonState == .saved {
            return .green
        }
        if hasUnsavedChanges {
            return .blue
        }
        return .gray
    }

    private func currentDraftSignature() -> String {
        let draft = AppSettings(accounts: accounts, refreshInterval: refreshInterval, hotkey: hotkey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(draft) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

}

struct AccountRowView: View {
    private static let chatGPTGuideURL = URL(string: "https://github.com/SalmonC/ApiUsageTrackerForMac/blob/main/Docs/ACCOUNT_CREDENTIALS_GUIDE.md")!
    @Binding var account: APIAccount
    @Binding var isExpanded: Bool
    var onDelete: () -> Void
    var onNameEditFinished: ((String, String) -> Void)?
    var onProviderChanged: ((APIProvider, APIProvider) -> Void)?
    @FocusState private var isNameFieldFocused: Bool
    @State private var isEditingName: Bool = false
    @State private var nameAtEditStart: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    nameEditorOrLabel
                } else {
                    Button(action: toggleExpanded) {
                        Text(account.name.isEmpty ? account.provider.displayName : account.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                
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
                        ForEach(providerOptions) { provider in
                            Text(providerOptionLabel(provider)).tag(provider)
                        }
                    }
                    .onChange(of: account.provider) { oldValue, newValue in
                        endNameEditing()
                        onProviderChanged?(oldValue, newValue)
                    }
                    
                    SecureField(apiKeyPlaceholder, text: $account.apiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    if account.provider == .chatGPT {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("粘贴 ChatGPT Web accessToken，或完整 session cookie（将自动换取 accessToken）")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Link(destination: Self.chatGPTGuideURL) {
                                Label("如何获取 ChatGPT 凭证？", systemImage: "questionmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    TestConnectionButton(account: account)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onChange(of: isNameFieldFocused) { _, focused in
            if !focused && isEditingName {
                endNameEditing()
            }
        }
    }

    @ViewBuilder
    private var nameEditorOrLabel: some View {
        if isEditingName {
            TextField("Account Name", text: Binding(
                get: { account.name },
                set: { newValue in
                    account.name = newValue
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 170)
            .focused($isNameFieldFocused)
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
            }
            .onSubmit {
                endNameEditing()
            }
        } else {
            Button(action: beginNameEditing) {
                HStack(spacing: 4) {
                    Text(account.name.isEmpty ? account.provider.displayName : account.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.75)
                }
            }
            .buttonStyle(.plain)
            .help("点击名称可改名")
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
        if !isExpanded {
            endNameEditing()
        }
    }

    private func beginNameEditing() {
        nameAtEditStart = account.name
        isEditingName = true
        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func endNameEditing() {
        let shouldCommit = isEditingName
        let originalName = nameAtEditStart
        let editedName = account.name
        isEditingName = false
        isNameFieldFocused = false
        if shouldCommit {
            onNameEditFinished?(originalName, editedName)
        }
    }
    
    private var apiKeyPlaceholder: String {
        switch account.provider {
        case .chatGPT:
            return "ChatGPT Access Token / Session Cookie"
        default:
            return "API Key"
        }
    }

    private var providerOptions: [APIProvider] {
        if APIProvider.selectableForNewAccounts.contains(account.provider) {
            return APIProvider.selectableForNewAccounts
        }
        return APIProvider.selectableForNewAccounts + [account.provider]
    }

    private func providerOptionLabel(_ provider: APIProvider) -> String {
        if provider.supportsRemainingQuotaQuery {
            return provider.displayName
        }
        return "\(provider.displayName)（暂不支持余量查询）"
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeySetting
    var onValidationError: ((String) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var onRecordingCompleted: (() -> Void)?
    
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
                onRecordingCompleted?()
            }
        }
        view.onRecordingCancelled = {
            onRecordingCancelled?()
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
    var onRecordingCancelled: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 { // Esc
            isRecording = false
            onRecordingCancelled?()
            return
        }
        
        let modifiers = event.modifierFlags.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.control.rawValue)
        
        guard modifiers != 0 else { return }
        
        onKeyRecorded?(UInt16(event.keyCode), UInt32(modifiers))
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign && isRecording {
            isRecording = false
            onRecordingCancelled?()
        }
        return didResign
    }
}

struct TestConnectionButton: View {
    let account: APIAccount
    @State private var isTesting = false
    @State private var testResult: TestResult?
    
    enum TestResult {
        case success(String)
        case failure(String)
    }
    
    var body: some View {
        HStack {
            Button(action: testConnection) {
                HStack(spacing: 4) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else if let result = testResult {
                        Image(systemName: iconForResult(result))
                            .foregroundColor(colorForResult(result))
                    } else {
                        Image(systemName: "network")
                    }
                    Text(buttonText)
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isTesting || account.apiKey.isEmpty)
            
            if let result = testResult {
                Text(messageForResult(result))
                    .font(.caption)
                    .foregroundColor(colorForResult(result))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var buttonText: String {
        if isTesting {
            return "Testing..."
        } else if testResult != nil {
            return "Test Again"
        }
        return "Test Connection"
    }
    
    private func testConnection() {
        guard !account.apiKey.isEmpty else { return }
        
        isTesting = true
        testResult = nil
        
        Task {
            let service = getService(for: account.provider)
            do {
                let result = try await service.fetchUsage(apiKey: account.apiKey)
                await MainActor.run {
                    if result.remaining != nil ||
                        result.used != nil ||
                        result.total != nil ||
                        result.monthlyRemaining != nil ||
                        result.monthlyUsed != nil ||
                        result.monthlyTotal != nil {
                        testResult = .success("Connection successful!")
                    } else {
                        testResult = .failure("Invalid response from API")
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
    
    private func iconForResult(_ result: TestResult) -> String {
        switch result {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }
    
    private func colorForResult(_ result: TestResult) -> Color {
        switch result {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
    
    private func messageForResult(_ result: TestResult) -> String {
        switch result {
        case .success(let msg):
            return msg
        case .failure(let msg):
            return msg
        }
    }
}
