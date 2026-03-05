import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var updateService: UpdateService
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
    @State private var alertsEnabled: Bool = true
    @State private var warningThreshold: Int = 80
    @State private var criticalThreshold: Int = 90
    @State private var alertCooldownMinutes: Int = 120
    @State private var showTrendInDashboard: Bool = true
    @State private var editingAccountID: UUID?
    @State private var nameDraftByAccountID: [UUID: String] = [:]
    @State private var nameAtEditStartByAccountID: [UUID: String] = [:]
    @State private var defocusObserverTokens: [NSObjectProtocol] = []
    @State private var localClickMonitor: Any?
    
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
            installDefocusObserversIfNeeded()
            installLocalClickMonitorIfNeeded()
        }
        .onDisappear {
            removeDefocusObservers()
            removeLocalClickMonitor()
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(language == .english ? "General Settings" : "通用设置")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                        if hasUnsavedChanges {
                            Label(language == .english ? "Unsaved" : "未保存", systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }

                    generalCard(
                        title: language == .english ? "Language & Refresh" : "语言与刷新",
                        subtitle: language == .english ? "UI language and background refresh cadence" : "界面语言与后台自动刷新频率",
                        icon: "globe"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(language == .english ? "Language" : "语言")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $language) {
                                Text(language == .english ? "Chinese" : "中文").tag(AppLanguage.chinese)
                                Text(language == .english ? "English" : "英文").tag(AppLanguage.english)
                            }
                            .pickerStyle(.segmented)

                            Text(language == .english ? "Refresh interval" : "刷新间隔")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Picker("", selection: $refreshInterval) {
                                Text(language == .english ? "1 minute" : "1 分钟").tag(1)
                                Text(language == .english ? "5 minutes" : "5 分钟").tag(5)
                                Text(language == .english ? "15 minutes" : "15 分钟").tag(15)
                                Text(language == .english ? "30 minutes" : "30 分钟").tag(30)
                                Text(language == .english ? "1 hour" : "1 小时").tag(60)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    generalCard(
                        title: language == .english ? "Usage Alerts" : "用量提醒",
                        subtitle: language == .english ? "Notify when quota usage reaches thresholds" : "在用量达到阈值时发送提醒",
                        icon: "bell.badge"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $alertsEnabled) {
                                Text(language == .english ? "Enable low-quota notifications" : "开启低余量通知")
                            }
                            .toggleStyle(.switch)

                            if alertsEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(language == .english ? "Warning threshold" : "预警阈值")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(warningThreshold)%")
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                    Picker("", selection: $warningThreshold) {
                                        Text("70%").tag(70)
                                        Text("75%").tag(75)
                                        Text("80%").tag(80)
                                        Text("85%").tag(85)
                                        Text("90%").tag(90)
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: warningThreshold) { _, newValue in
                                        if criticalThreshold <= newValue {
                                            criticalThreshold = min(100, newValue + 5)
                                        }
                                    }

                                    HStack {
                                        Text(language == .english ? "Critical threshold" : "告警阈值")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(criticalThreshold)%")
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                    Picker("", selection: $criticalThreshold) {
                                        Text("85%").tag(85)
                                        Text("90%").tag(90)
                                        Text("95%").tag(95)
                                        Text("100%").tag(100)
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: criticalThreshold) { _, newValue in
                                        if newValue <= warningThreshold {
                                            warningThreshold = max(70, newValue - 5)
                                        }
                                    }

                                    HStack {
                                        Text(language == .english ? "Notification cooldown" : "通知冷却时间")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(cooldownLabel(alertCooldownMinutes))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                    Picker("", selection: $alertCooldownMinutes) {
                                        Text(language == .english ? "30m" : "30 分钟").tag(30)
                                        Text(language == .english ? "1h" : "1 小时").tag(60)
                                        Text(language == .english ? "2h" : "2 小时").tag(120)
                                        Text(language == .english ? "4h" : "4 小时").tag(240)
                                        Text(language == .english ? "8h" : "8 小时").tag(480)
                                        Text(language == .english ? "24h" : "24 小时").tag(1440)
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(10)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(10)
                            }
                        }
                    }

                    generalCard(
                        title: language == .english ? "Dashboard" : "看板显示",
                        subtitle: language == .english ? "Choose whether trend charts are shown in cards" : "控制卡片中趋势图的显示",
                        icon: "chart.line.uptrend.xyaxis"
                    ) {
                        Toggle(isOn: $showTrendInDashboard) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language == .english ? "Show usage trends in dashboard" : "在看板显示用量趋势")
                                Text(
                                    language == .english
                                    ? "Turn off to simplify cards and reduce chart rendering."
                                    : "关闭后可简化卡片内容并减少图表渲染。"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    generalCard(
                        title: language == .english ? "Hotkey" : "快捷键",
                        subtitle: language == .english ? "Global shortcut to open the dashboard quickly" : "用于快速打开看板的全局快捷键",
                        icon: "keyboard"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language == .english
                                 ? "Click below and press a key combo (include at least one modifier: ⌘⇧⌥⌃)"
                                 : "点击下方并录入组合键（至少包含一个修饰键：⌘⇧⌥⌃）")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                            HStack(spacing: 8) {
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
                                                .fontWeight(.medium)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
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
                                    Text(language == .english ? "Default" : "默认")
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
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Text(language == .english ? "Current: \(hotkey.displayString)" : "当前快捷键：\(hotkey.displayString)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    generalCard(
                        title: language == .english ? "Updates & Project" : "更新与项目",
                        subtitle: language == .english ? "Check stable releases and open project docs" : "检查正式版更新并打开项目文档",
                        icon: "arrow.triangle.2.circlepath"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            let buttonHeight: CGFloat = 32
                            HStack(spacing: 8) {
                                Button(action: {
                                    updateService.checkForUpdates()
                                }) {
                                    HStack(spacing: 6) {
                                        ZStack {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12, weight: .semibold))
                                                .opacity(updateService.isChecking ? 0 : 1)
                                            ProgressView()
                                                .controlSize(.small)
                                                .opacity(updateService.isChecking ? 1 : 0)
                                        }
                                        .frame(width: 14, height: 14)
                                        Text(language == .english ? "Check for Updates" : "检查更新")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(updateService.isChecking)
                                .animation(.none, value: updateService.isChecking)

                                Button(action: {
                                    updateService.openGitHubReadme()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book")
                                        Text(language == .english ? "GitHub README" : "GitHub 文档")
                                    }
                                    .frame(maxWidth: .infinity, minHeight: buttonHeight, maxHeight: buttonHeight)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }

                            Text(language == .english
                                 ? "Mode: manual download updates (unsigned build)"
                                 : "更新模式：手动下载更新（未签名构建）")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                            Text(language == .english
                                 ? "Current app version: \(currentAppVersion)"
                                 : "当前应用版本：\(currentAppVersion)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                            if let statusMessage = updateService.statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let lastCheckTime = updateService.lastCheckTime {
                                Text(
                                    language == .english
                                    ? "Last checked: \(formattedUpdateCheckTime(lastCheckTime))"
                                    : "上次检查：\(formattedUpdateCheckTime(lastCheckTime))"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                }
                .padding(16)
                .padding(.bottom, 8)
            }

            stickySaveBar(primary: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func generalCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var accountsSettingsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == .english ? "API Accounts" : "API 账号")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(language == .english ? "Added accounts will appear on dashboard" : "添加账号后可在看板中显示实时状态")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if hasUnsavedChanges {
                        Text(language == .english ? "Unsaved" : "未保存")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.16))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    Button(action: addAccount) {
                        Label(language == .english ? "Add" : "新增", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
                        LazyVStack(spacing: 12) {
                            ForEach($accounts) { $account in
                                AccountRowView(
                                    account: $account,
                                    isExpanded: Binding(
                                        get: { expandedStates[account.id] ?? false },
                                        set: { expandedStates[account.id] = $0 }
                                    ),
                                    isEditingName: editingAccountID == account.id,
                                    nameDraft: nameDraftByAccountID[account.id] ?? account.name,
                                    onDelete: {
                                        forceCommitCurrentEditor()
                                        pendingDeleteAccount = account
                                    },
                                    onNameLabelTapped: {
                                        beginNameEditing(for: account.id)
                                    },
                                    onNameDraftChanged: { draft in
                                        updateNameDraft(for: account.id, draft: draft)
                                    },
                                    onNameEditCommitted: {
                                        commitNameEdit(for: account.id)
                                    },
                                    onProviderChanged: { _, newProvider in
                                        let shouldFollowProvider = autoNamedAccountIDs.contains(account.id)
                                        if shouldFollowProvider {
                                            account.name = newProvider.displayName
                                            autoNamedAccountIDs.insert(account.id)
                                            nameDraftByAccountID[account.id] = newProvider.displayName
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            stickySaveBar(primary: false)
        }
    }

    private func stickySaveBar(primary: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button(action: {
                    commitEditsThenSave()
                }) {
                    HStack {
                        if saveButtonState == .saved {
                            Image(systemName: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(saveButtonTitle(primary: primary))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(saveButtonTintColor)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasUnsavedChanges && saveButtonState != .saved)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
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
        alertsEnabled = settings.alertSettings.isEnabled
        warningThreshold = settings.alertSettings.warningPercentage
        criticalThreshold = settings.alertSettings.criticalPercentage
        alertCooldownMinutes = settings.alertSettings.cooldownMinutes
        showTrendInDashboard = settings.showTrendInDashboard
        isRecordingHotkey = false
        hotkeyBeforeRecording = nil
        hotkeyError = nil
        saveButtonState = .normal
        isCapabilityNoticeExpanded = false
        editingAccountID = nil
        nameDraftByAccountID = [:]
        nameAtEditStartByAccountID = [:]
        collapseAllAccounts()
        savedDraftSignature = currentDraftSignature()
    }
    
    private func saveSettings() {
        accounts = accounts.map { account in
            var normalized = account
            normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.name.isEmpty {
                normalized.name = normalized.provider.displayName
            }
            return normalized
        }

        let settings = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey,
            language: language,
            alertSettings: normalizedAlertSettings(),
            showTrendInDashboard: showTrendInDashboard
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

    private func commitEditsThenSave() {
        forceCommitCurrentEditor()
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async {
            saveSettings()
        }
    }

    private func installDefocusObserversIfNeeded() {
        guard defocusObserverTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let windowToken = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            forceCommitCurrentEditor()
        }
        let appToken = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            forceCommitCurrentEditor()
        }
        defocusObserverTokens = [windowToken, appToken]
    }

    private func removeDefocusObservers() {
        let center = NotificationCenter.default
        defocusObserverTokens.forEach { center.removeObserver($0) }
        defocusObserverTokens.removeAll()
    }

    private func installLocalClickMonitorIfNeeded() {
        guard localClickMonitor == nil else { return }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            DispatchQueue.main.async {
                guard editingAccountID != nil else { return }
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return
                }
                // Some control clicks transition focus asynchronously; verify once more
                // on the next runloop turn before committing the edit.
                if NSApp.keyWindow?.firstResponder == nil {
                    DispatchQueue.main.async {
                        guard editingAccountID != nil else { return }
                        if NSApp.keyWindow?.firstResponder is NSTextView {
                            return
                        }
                        forceCommitCurrentEditor()
                    }
                    return
                }
                forceCommitCurrentEditor()
            }
            return event
        }
    }

    private func removeLocalClickMonitor() {
        guard let monitor = localClickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        localClickMonitor = nil
    }

    private func beginNameEditing(for accountID: UUID) {
        if editingAccountID != accountID {
            forceCommitCurrentEditor()
        }
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        editingAccountID = accountID
        nameDraftByAccountID[accountID] = accounts[index].name
        nameAtEditStartByAccountID[accountID] = accounts[index].name
    }

    private func updateNameDraft(for accountID: UUID, draft: String) {
        nameDraftByAccountID[accountID] = draft
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].name = draft
    }

    private func commitNameEdit(for accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            editingAccountID = nil
            nameDraftByAccountID.removeValue(forKey: accountID)
            nameAtEditStartByAccountID.removeValue(forKey: accountID)
            return
        }

        let originalName = nameAtEditStartByAccountID[accountID] ?? accounts[index].name
        var committedName = (nameDraftByAccountID[accountID] ?? accounts[index].name)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if committedName.isEmpty {
            committedName = accounts[index].provider.displayName
            autoNamedAccountIDs.insert(accountID)
        } else if committedName != originalName {
            autoNamedAccountIDs.remove(accountID)
        }

        accounts[index].name = committedName
        nameDraftByAccountID[accountID] = committedName
        nameAtEditStartByAccountID.removeValue(forKey: accountID)
        if editingAccountID == accountID {
            editingAccountID = nil
        }
    }

    private func forceCommitCurrentEditor() {
        guard let accountID = editingAccountID else { return }
        commitNameEdit(for: accountID)
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
        if editingAccountID == account.id {
            editingAccountID = nil
        }
        nameDraftByAccountID.removeValue(forKey: account.id)
        nameAtEditStartByAccountID.removeValue(forKey: account.id)
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
        let draft = AppSettings(
            accounts: accounts,
            refreshInterval: refreshInterval,
            hotkey: hotkey,
            language: language,
            alertSettings: normalizedAlertSettings(),
            showTrendInDashboard: showTrendInDashboard
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(draft) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func normalizedAlertSettings() -> ThresholdAlertSettings {
        ThresholdAlertSettings(
            isEnabled: alertsEnabled,
            warningPercentage: warningThreshold,
            criticalPercentage: criticalThreshold,
            cooldownMinutes: alertCooldownMinutes
        ).normalized
    }

    private func cooldownLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hour = minutes / 60
            return language == .english ? "\(hour)h" : "\(hour)小时"
        }
        return language == .english ? "\(minutes)m" : "\(minutes)分钟"
    }

    private func formattedUpdateCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .english ? Locale(identifier: "en_US_POSIX") : Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

}

struct AccountRowView: View {
    private static let chatGPTGuideURL = URL(string: "https://github.com/SalmonC/ApiUsageTrackerForMac/blob/main/Docs/ACCOUNT_CREDENTIALS_GUIDE.md")!
    @Binding var account: APIAccount
    @Binding var isExpanded: Bool
    var isEditingName: Bool
    var nameDraft: String
    var onDelete: () -> Void
    var onNameLabelTapped: () -> Void
    var onNameDraftChanged: (String) -> Void
    var onNameEditCommitted: () -> Void
    var onProviderChanged: ((APIProvider, APIProvider) -> Void)?
    var language: AppLanguage = .chinese
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            HStack(alignment: .center, spacing: 8) {
                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    nameEditorOrLabel
                } else {
                    Button(action: toggleExpanded) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name.isEmpty ? account.provider.displayName : account.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(account.provider.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(language == .english ? "Show" : "显示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $account.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language == .english ? "Provider" : "供应商")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker(language == .english ? "Provider" : "供应商", selection: $account.provider) {
                            ForEach(providerOptions) { provider in
                                Text(providerOptionLabel(provider)).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: account.provider) { oldValue, newValue in
                            onNameEditCommitted()
                            onProviderChanged?(oldValue, newValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(apiKeyPlaceholder)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        SecureField(apiKeyPlaceholder, text: $account.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
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
                    
                    Divider()
                    TestConnectionButton(account: $account, language: language)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isExpanded ? 12 : 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isExpanded ? Color.accentColor.opacity(0.30) : Color.gray.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private var nameEditorOrLabel: some View {
        if isEditingName {
            AccountNameEditor(
                text: Binding(
                    get: { nameDraft },
                    set: onNameDraftChanged
                ),
                isFocused: isEditingName,
                onBeginEditing: {},
                onEndEditing: {
                    onNameEditCommitted()
                }
            )
            .frame(width: 200)
        } else {
            Button(action: onNameLabelTapped) {
                HStack(spacing: 4) {
                    Text(account.name.isEmpty ? account.provider.displayName : account.name)
                        .font(.system(size: 15, weight: .semibold))
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
            onNameEditCommitted()
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

private struct AccountNameEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onBeginEditing: () -> Void
    var onEndEditing: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AccountNameEditor
        var isProgrammaticTextUpdate = false

        init(parent: AccountNameEditor) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onBeginEditing()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isProgrammaticTextUpdate else { return }
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            context.coordinator.isProgrammaticTextUpdate = true
            nsView.stringValue = text
            context.coordinator.isProgrammaticTextUpdate = false
        }

        guard let window = nsView.window else { return }
        if isFocused {
            if window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
        }
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
    @Binding var account: APIAccount
    var language: AppLanguage = .chinese
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showDetails = false
    
    enum TestResult {
        case success(summary: String, details: String?)
        case failure(summary: String, details: String?)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "network")
                                .font(.caption)
                        }
                        Text(buttonText)
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)

                if let result = testResult {
                    Label(messageForResult(result), systemImage: iconForResult(result))
                        .font(.caption)
                        .foregroundColor(colorForResult(result))
                        .lineLimit(1)
                }
            }

            if let result = testResult,
               let details = detailsForResult(result),
               !details.isEmpty {
                Button(showDetails ? (language == .english ? "Hide details" : "收起详情") : (language == .english ? "Show details" : "展开详情")) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showDetails.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.secondary)

                if showDetails {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .onChange(of: account.apiKey) { _, _ in
            testResult = nil
            showDetails = false
        }
        .onChange(of: account.provider) { _, _ in
            testResult = nil
            showDetails = false
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
        // Force commit editing so SecureField value is synchronized before test.
        NSApp.keyWindow?.makeFirstResponder(nil)

        let credential = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
            testResult = .failure(
                summary: language == .english ? "Please enter credential first" : "请先输入凭证",
                details: nil
            )
            return
        }
        
        isTesting = true
        testResult = nil
        showDetails = false
        
        // Capture current state before entering async context
        let currentAccount = account
        let currentLanguage = language
        
        Task {
            let service = getService(for: currentAccount.provider)
            do {
                let result = try await service.fetchUsage(apiKey: credential)
                try Task.checkCancellation()
                await MainActor.run {
                    if result.remaining != nil ||
                        result.used != nil ||
                        result.total != nil ||
                        result.monthlyRemaining != nil ||
                        result.monthlyUsed != nil ||
                        result.monthlyTotal != nil ||
                        result.subscriptionPlan != nil ||
                        result.refreshTime != nil ||
                        result.monthlyRefreshTime != nil ||
                        result.nextRefreshTime != nil {
                        testResult = .success(
                            summary: currentLanguage == .english ? "Connection successful" : "连接成功",
                            details: currentLanguage == .english
                            ? "Provider: \(currentAccount.provider.displayName)"
                            : "供应商：\(currentAccount.provider.displayName)"
                        )
                    } else {
                        testResult = .failure(
                            summary: currentLanguage == .english ? "Connected but no usable fields" : "连接成功但无可用字段",
                            details: currentLanguage == .english
                            ? "Provider endpoint returned success without known usage/subscription fields."
                            : "接口返回成功，但没有识别到可用的用量/订阅字段。"
                        )
                    }
                    isTesting = false
                }
            } catch is CancellationError {
                // Task was cancelled, ignore
                await MainActor.run {
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(
                        summary: currentLanguage == .english ? "Connection failed" : "连接失败",
                        details: classifiedFailureDetail(error, language: currentLanguage)
                    )
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
        case .success(let msg, _):
            return msg
        case .failure(let msg, _):
            return msg
        }
    }

    private func detailsForResult(_ result: TestResult) -> String? {
        switch result {
        case .success(_, let details):
            return details
        case .failure(_, let details):
            return details
        }
    }

    private func classifiedFailureDetail(_ error: Error, language: AppLanguage? = nil) -> String {
        let lang = language ?? self.language
        if let apiError = error as? APIError {
            switch apiError {
            case .noAPIKey:
                return lang == .english
                    ? "Type: Missing credential\nPlease input API key/token and retry."
                    : "类型：缺少凭证\n请先输入 API Key/Token 后重试。"
            case .httpError(let code), .httpErrorWithMessage(let code, _):
                if code == 401 || code == 403 {
                    return lang == .english
                        ? "Type: Authentication failed (HTTP \(code))\nCredential is invalid, expired, or has insufficient permissions."
                        : "类型：鉴权失败（HTTP \(code)）\n凭证无效、已过期或权限不足。"
                }
                if code == 429 {
                    return lang == .english
                        ? "Type: Rate limited (HTTP 429)\nPlease retry later."
                        : "类型：触发频率限制（HTTP 429）\n请稍后重试。"
                }
                if code >= 500 {
                    return lang == .english
                        ? "Type: Provider service error (HTTP \(code))\nThis is usually temporary."
                        : "类型：供应商服务异常（HTTP \(code)）\n通常为临时问题。"
                }
                return lang == .english
                    ? "Type: API request failed (HTTP \(code))\n\(error.localizedDescription)"
                    : "类型：接口请求失败（HTTP \(code)）\n\(error.localizedDescription)"
            case .decodingError:
                return lang == .english
                    ? "Type: Response parse failure\nProvider response schema may have changed."
                    : "类型：响应解析失败\n可能是供应商返回结构发生变化。"
            case .networkError(let wrapped):
                return classifyWrappedError(wrapped, language: lang)
            case .invalidURL, .invalidResponse:
                return lang == .english
                    ? "Type: Invalid response\nProvider endpoint returned unexpected payload."
                    : "类型：响应无效\n供应商接口返回了异常数据。"
            }
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("401") || lowered.contains("403") || lowered.contains("unauthorized") || lowered.contains("forbidden") {
            return lang == .english
                ? "Type: Authentication failed\nCredential is invalid, expired, or unauthorized."
                : "类型：鉴权失败\n凭证无效、过期或权限不足。"
        }
        if lowered.contains("429") || lowered.contains("rate") {
            return lang == .english
                ? "Type: Rate limited\nPlease retry later."
                : "类型：触发频率限制\n请稍后重试。"
        }
        if lowered.contains("decode") || lowered.contains("json") || lowered.contains("parse") {
            return lang == .english
                ? "Type: Response parse failure\nProvider response schema may have changed."
                : "类型：响应解析失败\n可能是供应商返回结构发生变化。"
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return lang == .english
                ? "Type: Request timeout\nNetwork is slow or provider endpoint is overloaded."
                : "类型：请求超时\n可能是网络较慢或供应商接口拥塞。"
        }
        return lang == .english
            ? "Type: Unknown failure\n\(error.localizedDescription)"
            : "类型：未知错误\n\(error.localizedDescription)"
    }

    private func classifyWrappedError(_ wrapped: Error, language: AppLanguage? = nil) -> String {
        let lang = language ?? self.language
        if let urlError = wrapped as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return lang == .english
                    ? "Type: Network unavailable\nPlease check internet connection."
                    : "类型：网络不可用\n请检查网络连接。"
            case .timedOut:
                return lang == .english
                    ? "Type: Request timeout\nProvider did not respond in time."
                    : "类型：请求超时\n供应商接口响应超时。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return lang == .english
                    ? "Type: Endpoint unreachable\nPlease check network/proxy/DNS."
                    : "类型：接口不可达\n请检查网络、代理或 DNS。"
            default:
                return lang == .english
                    ? "Type: Network error\n\(wrapped.localizedDescription)"
                    : "类型：网络错误\n\(wrapped.localizedDescription)"
            }
        }

        let nsError = wrapped as NSError
        if nsError.domain == NSURLErrorDomain {
            return lang == .english
                ? "Type: Network error\n\(wrapped.localizedDescription)"
                : "类型：网络错误\n\(wrapped.localizedDescription)"
        }

        // Many providers wrap auth/schema/business failures into a custom NSError
        // (domain != NSURLErrorDomain), so classify them as provider/API failures.
        let lowered = wrapped.localizedDescription.lowercased()
        if lowered.contains("auth") || lowered.contains("token") || lowered.contains("key") || lowered.contains("permission") {
            return lang == .english
                ? "Type: Authentication/permission failure\n\(wrapped.localizedDescription)"
                : "类型：鉴权或权限失败\n\(wrapped.localizedDescription)"
        }
        return lang == .english
            ? "Type: Provider/API failure\n\(wrapped.localizedDescription)"
            : "类型：供应商接口失败\n\(wrapped.localizedDescription)"
    }
}
