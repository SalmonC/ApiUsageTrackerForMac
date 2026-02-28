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
    @State private var isCapabilityNoticeExpanded: Bool = false
    @State private var language: AppLanguage = .chinese
    
    enum SaveButtonState {
        case normal
        case saved
    }
    
    var body: some View {
        TabView {
            generalSettingsView
                .tabItem {
                    Label(language == .english ? "General" : "通用", systemImage: "gear")
                }
            
            accountsSettingsView
                .tabItem {
                    Label(language == .english ? "API Accounts" : "API 账号", systemImage: "key")
                }
        }
        .onAppear {
            loadSettings()
        }
        .alert(language == .english ? "Delete Account?" : "删除账号？", isPresented: pendingDeleteBinding) {
            Button(language == .english ? "Delete" : "删除", role: .destructive) {
                if let account = pendingDeleteAccount {
                    deleteAccount(account)
                }
                pendingDeleteAccount = nil
            }
            Button(language == .english ? "Cancel" : "取消", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: {
            Text(language == .english
                 ? "This removes account config and deletes stored API key from Keychain."
                 : "将删除该账号配置，并移除钥匙串中已保存的 API Key。")
        }
    }
    
    private var generalSettingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                HStack {
                    Text(language == .english ? "Language" : "语言")
                        .font(.headline)
                    Spacer()
                }
                Picker("", selection: $language) {
                    Text(language == .english ? "Chinese" : "中文").tag(AppLanguage.chinese)
                    Text(language == .english ? "English" : "英文").tag(AppLanguage.english)
                }
                .pickerStyle(.segmented)

                Divider()

                HStack {
                    Text(language == .english ? "Refresh Interval" : "刷新间隔")
                        .font(.headline)
                    Spacer()
                    if hasUnsavedChanges {
                        Label(language == .english ? "Unsaved Changes" : "未保存更改", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Picker("", selection: $refreshInterval) {
                    Text(language == .english ? "1 minute" : "1 分钟").tag(1)
                    Text(language == .english ? "5 minutes" : "5 分钟").tag(5)
                    Text(language == .english ? "15 minutes" : "15 分钟").tag(15)
                    Text(language == .english ? "30 minutes" : "30 分钟").tag(30)
                    Text(language == .english ? "1 hour" : "1 小时").tag(60)
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            Group {
                Text(language == .english ? "Hotkey" : "快捷键")
                    .font(.headline)
                Text(language == .english
                     ? "Press below and input a key combo (must include at least one modifier: ⌘⇧⌥⌃)"
                     : "点击下方按钮并录入按键组合（至少包含一个修饰键：⌘⇧⌥⌃）")
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
                                Text(language == .english ? "Press keys..." : "请按下组合键...")
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
                            language: language,
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
                        Text(language == .english ? "Restore Default" : "恢复默认")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if isRecordingHotkey {
                        Button(language == .english ? "Cancel" : "取消") {
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
                
                Text(language == .english ? "Current hotkey: \(hotkey.displayString)" : "当前快捷键：\(hotkey.displayString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isRecordingHotkey {
                    Text(language == .english
                         ? "Click elsewhere, press Esc, or use Cancel to stop recording"
                         : "点击其他位置、按 Esc 或使用取消按钮停止录入")
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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language == .english ? "API Accounts" : "API 账号")
                        .font(.headline)
                    Text(language == .english ? "Added accounts will appear on dashboard" : "添加账号后可在看板中显示实时状态")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if hasUnsavedChanges {
                    Text(language == .english ? "Unsaved" : "未保存")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Button(action: addAccount) {
                    Label(language == .english ? "Add" : "新增", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            if accounts.isEmpty {
                VStack {
                    Text(language == .english ? "No API accounts configured" : "当前没有配置 API 账号")
                        .foregroundColor(.secondary)
                    Text(language == .english ? "Click + to add an account" : "点击 + 新增账号")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if !APIProvider.providersWithCapabilityDescription.isEmpty {
                    providerCapabilityNoticeSection
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
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
                                },
                                language: language
                            )
                        }

                        if !APIProvider.providersWithCapabilityDescription.isEmpty {
                            providerCapabilityNoticeSection
                                .padding(.top, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
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

    private var providerCapabilityNoticeSection: some View {
        DisclosureGroup(isExpanded: $isCapabilityNoticeExpanded) {
            providerCapabilityNoticeCard
                .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text(language == .english ? "Provider Capabilities" : "供应商能力说明")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(language == .english ? "\(APIProvider.providersWithCapabilityDescription.count) items" : "\(APIProvider.providersWithCapabilityDescription.count)项")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }

    private var providerCapabilityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                language == .english
                ? "API fields vary by provider; below are known limits and rendering rules."
                : "不同平台返回字段不同，以下为当前已知限制与展示规则"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(APIProvider.providersWithCapabilityDescription) { provider in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.10))
                                .frame(width: 28, height: 28)
                            Image(systemName: provider.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(provider.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let hint = provider.restrictionHint(language: language) {
                                    Text(hint)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(provider.capabilityDescription(language: language) ?? (language == .english ? "No extra notes" : "暂无说明"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.14), lineWidth: 1)
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
                            Color.blue.opacity(0.06),
                            Color.blue.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.16), lineWidth: 1)
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
        language = settings.language
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
        hotkeyError = nil
        saveButtonState = .normal
        isCapabilityNoticeExpanded = false
        collapseAllAccounts()
        savedDraftSignature = currentDraftSignature()
    }
    
    private func saveSettings() {
        let settings = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey,
            language: language
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
            return language == .english ? "Saved!" : "已保存"
        }
        if !hasUnsavedChanges {
            return language == .english ? "No Changes" : "无改动"
        }
        return primary
            ? (language == .english ? "Save Settings" : "保存设置")
            : (language == .english ? "Save" : "保存")
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
        let draft = AppSettings(accounts: accounts, refreshInterval: refreshInterval, hotkey: hotkey, language: language)
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
    var language: AppLanguage = .chinese
    @FocusState private var isNameFieldFocused: Bool
    @State private var isEditingName: Bool = false
    @State private var nameAtEditStart: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
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
                    Text(language == .english ? "Show" : "显示")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $account.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
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
                    Picker(language == .english ? "Provider" : "供应商", selection: $account.provider) {
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
                            Text(
                                language == .english
                                ? "Paste ChatGPT Web accessToken or full session cookie (accessToken will be exchanged automatically)"
                                : "粘贴 ChatGPT Web accessToken，或完整 session cookie（将自动换取 accessToken）"
                            )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Link(destination: Self.chatGPTGuideURL) {
                                Label(language == .english ? "How to get ChatGPT credentials?" : "如何获取 ChatGPT 凭证？", systemImage: "questionmark.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    TestConnectionButton(account: account, language: language)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isExpanded ? 12 : 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.10), lineWidth: 1)
        )
        .onChange(of: isNameFieldFocused) { _, focused in
            if !focused && isEditingName {
                endNameEditing()
            }
        }
    }

    @ViewBuilder
    private var nameEditorOrLabel: some View {
        if isEditingName {
            TextField(language == .english ? "Account Name" : "账号名称", text: Binding(
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
            .help(language == .english ? "Click name to edit" : "点击名称可改名")
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
            return language == .english
                ? "ChatGPT Access Token / Session Cookie"
                : "ChatGPT Access Token / Session Cookie"
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
        return language == .english
            ? "\(provider.displayName) (remaining quota unsupported)"
            : "\(provider.displayName)（暂不支持余量查询）"
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeySetting
    var language: AppLanguage = .chinese
    var onValidationError: ((String) -> Void)?
    var onRecordingCancelled: (() -> Void)?
    var onRecordingCompleted: (() -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = { keyCode, modifiers in
            let validationError = HotkeySetting.validate(keyCode: keyCode, modifiers: modifiers, language: language)
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
    var language: AppLanguage = .chinese
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
            return language == .english ? "Testing..." : "测试中..."
        } else if testResult != nil {
            return language == .english ? "Test Again" : "重新测试"
        }
        return language == .english ? "Test Connection" : "测试连接"
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
                        testResult = .success(language == .english ? "Connection successful!" : "连接成功")
                    } else {
                        testResult = .failure(language == .english ? "Invalid response from API" : "API 返回数据无效")
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
