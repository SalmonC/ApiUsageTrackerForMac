import SwiftUI
import ServiceManagement
import Carbon
import UserNotifications
import QuartzCore

@main
struct ApiUsageTrackerForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsWindow(viewModel: appDelegate.viewModel)
        }
    }
}

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        SettingsView(viewModel: viewModel)
            .frame(width: 560, height: 560)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var refreshTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private let hotKeyIdentifier: UInt32 = 1
    private let hotKeySignature: OSType = 0x4155544B // "AUTK"
    private var appActivateObserver: NSObjectProtocol?
    private var preferredPopoverContentHeight: CGFloat?
    private var pendingPopoverResizeWorkItem: DispatchWorkItem?
    private var pendingPopoverSize: NSSize?
    private let storage = Storage.shared
    var viewModel = AppViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupMenuBar()
        setupGlobalHotKey()
        setupAppActivateObserver()
        setupRefreshTimer()
        setupSettingsCallback()
        setupNotifications()
        
        NSApp.setActivationPolicy(.accessory)
        
        Task {
            await viewModel.refreshAll(reloadSettings: false)
            updatePopoverSize()  // Update height after initial data load
        }
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Logger.log("Notification permission: \(granted)")
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func checkLowUsageAndNotify() {
        for data in viewModel.usageData {
            guard let total = data.tokenTotal, total > 0 else { continue }
            let percentage = data.usagePercentage
            
            if percentage > 90 {
                sendNotification(
                    title: "⚠️ API Usage Alert",
                    body: "\(data.accountName) has used \(Int(percentage))% of quota"
                )
            } else if percentage > 80 {
                sendNotification(
                    title: "📊 API Usage Warning",
                    body: "\(data.accountName) has used \(Int(percentage))% of quota"
                )
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.log("Failed to send notification: \(error)")
            }
        }
    }
    
    private func setupSettingsCallback() {
        viewModel.onSettingsSaved = { [weak self] in
            Task { @MainActor in
                await self?.viewModel.refreshAll(reloadSettings: false)
                self?.updatePopoverSize()  // Update height after settings change
                self?.updateGlobalHotKey()
                self?.viewModel.resetCountdown()
                self?.setupRefreshTimer()
            }
        }
        viewModel.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let iconURL = Bundle.main.url(forResource: "MenuBarIconWhite", withExtension: "png"),
               let menuIcon = NSImage(contentsOf: iconURL) {
                menuIcon.size = NSSize(width: 18, height: 18)
                button.image = menuIcon
            } else {
                button.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "QuotaPulse")
            }
            button.image?.isTemplate = false
            button.image?.accessibilityDescription = "QuotaPulse"
            button.action = #selector(leftClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupGlobalHotKey() {
        installGlobalHotKeyHandlerIfNeeded()
        updateGlobalHotKey()
    }
    
    private func updateGlobalHotKey() {
        unregisterGlobalHotKey()

        let hotkey = viewModel.settings.hotkey
        let eventHotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers(from: hotkey.modifiers),
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            Logger.log("Failed to register global hotkey, status: \(status)")
        }
    }
    
    private func installGlobalHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                return appDelegate.handleGlobalHotKeyEvent(eventRef)
            },
            1,
            &eventSpec,
            pointer,
            &hotKeyHandlerRef
        )

        if status != noErr {
            Logger.log("Failed to install global hotkey handler, status: \(status)")
        }
    }

    private func handleGlobalHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == hotKeySignature, hotKeyID.id == hotKeyIdentifier else {
            return noErr
        }

        Task { @MainActor [weak self] in
            self?.showPopover()
        }
        return noErr
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func carbonModifiers(from modifiers: UInt32) -> UInt32 {
        var carbonFlags: UInt32 = 0

        if (modifiers & UInt32(NSEvent.ModifierFlags.command.rawValue)) != 0 {
            carbonFlags |= UInt32(cmdKey)
        }
        if (modifiers & UInt32(NSEvent.ModifierFlags.shift.rawValue)) != 0 {
            carbonFlags |= UInt32(shiftKey)
        }
        if (modifiers & UInt32(NSEvent.ModifierFlags.option.rawValue)) != 0 {
            carbonFlags |= UInt32(optionKey)
        }
        if (modifiers & UInt32(NSEvent.ModifierFlags.control.rawValue)) != 0 {
            carbonFlags |= UInt32(controlKey)
        }

        return carbonFlags
    }
    
    private func setupAppActivateObserver() {
        appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    Task { @MainActor in
                        self.closePopover()
                    }
                }
            }
        }
    }
    
    @objc private func leftClick() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        updatePopoverSize()
        guard let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func closePopover() {
        pendingPopoverResizeWorkItem?.cancel()
        pendingPopoverResizeWorkItem = nil
        pendingPopoverSize = nil
        popover?.performClose(nil)
    }
    
    private func showContextMenu() {
        closePopover()
        
        let menu = NSMenu()
        
        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let launchAtLoginItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLogin() ? .on : .off
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func refreshAction() {
        Task { @MainActor in
            await viewModel.refreshAll()
            updatePopoverSize()  // Update height after refresh
        }
    }
    
    @objc private func openSettingsAction() {
        openSettingsWindow()
    }
    
    private func openSettingsWindow() {
        closePopover()
        
        if settingsWindow == nil {
            let settingsView = SettingsView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: settingsView)
            if #available(macOS 13.0, *) {
                // Disable automatic size propagation to avoid a SwiftUI/AppKit
                // constraint feedback loop when opening the resizable settings window.
                hostingController.sizingOptions = []
            }
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 560))
            window.minSize = NSSize(width: 500, height: 440)
            window.maxSize = NSSize(width: 980, height: 820)
            window.contentMinSize = NSSize(width: 500, height: 440)
            window.contentMaxSize = NSSize(width: 980, height: 820)
            window.center()
            window.isReleasedWhenClosed = false
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func toggleLaunchAtLogin() {
        let isEnabled = isLaunchAtLogin()
        if isEnabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
    
    private func isLaunchAtLogin() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func setupPopover() {
        updatePopoverSize()
    }
    
    private func updatePopoverSize(preferredContentHeight: CGFloat? = nil) {
        if let preferredContentHeight {
            preferredPopoverContentHeight = preferredContentHeight
        }
        
        let dataCount = viewModel.usageData.count
        let hasMonthlyData = viewModel.usageData.contains { $0.monthlyTotal != nil || $0.monthlyRemaining != nil }
        
        // Fixed heights for components
        let headerHeight: CGFloat = 60
        let footerHeight: CGFloat = 40
        let dividerHeight: CGFloat = 1
        let summaryHeight: CGFloat = (viewModel.isLoading || dataCount == 0) ? 0 : 32
        
        // Fallback estimate before MainView reports measured preferred height.
        // Keep this conservative to reduce initial blank area, and let measured value
        // take over for expanded rows.
        let estimatedRowHeight: CGFloat = hasMonthlyData ? 92 : 82
        let baseHeight = headerHeight + footerHeight + dividerHeight * 2 + summaryHeight + 18
        let itemCount = max(dataCount, 1)
        let idealHeight: CGFloat = viewModel.isLoading || dataCount == 0
            ? 260
            : (baseHeight + CGFloat(itemCount) * estimatedRowHeight)
        
        let fallbackIdealHeight = idealHeight
        let targetHeight = preferredPopoverContentHeight ?? fallbackIdealHeight
        
        let screenLimitedMaxHeight = currentPopoverMaxHeight()
        let minPopoverHeight = min(CGFloat(260), screenLimitedMaxHeight)
        let finalHeight = ceil(min(max(targetHeight, minPopoverHeight), screenLimitedMaxHeight))
        
        if popover == nil {
            popover = NSPopover()
            popover?.behavior = .transient
            popover?.contentViewController = NSHostingController(
                rootView: MainView(
                    viewModel: viewModel,
                    onPreferredHeightChange: { [weak self] preferredHeight in
                        Task { @MainActor in
                            self?.updatePopoverSize(preferredContentHeight: preferredHeight)
                        }
                    }
                )
            )
        }
        
        let newSize = NSSize(width: 340, height: finalHeight)
        applyPopoverSize(newSize)
        
        // Keep popover resize path quiet during rapid expansion updates to avoid
        // unnecessary main-thread work from high-frequency logging.
    }
    
    private func applyPopoverSize(_ newSize: NSSize) {
        guard let popover else { return }
        
        if !popover.isShown {
            pendingPopoverResizeWorkItem?.cancel()
            pendingPopoverResizeWorkItem = nil
            pendingPopoverSize = nil
            popover.contentSize = newSize
            return
        }
        
        let currentVisibleSize = currentPopoverVisibleContentSize(popover)
        if abs(currentVisibleSize.height - newSize.height) < 1 &&
            abs(currentVisibleSize.width - newSize.width) < 1 {
            return
        }

        pendingPopoverSize = newSize
        pendingPopoverResizeWorkItem?.cancel()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self, let popover = self.popover, let targetSize = self.pendingPopoverSize else { return }
            self.pendingPopoverResizeWorkItem = nil
            self.pendingPopoverSize = nil
            
            let currentSize = self.currentPopoverVisibleContentSize(popover)
            let delta = abs(currentSize.height - targetSize.height)
            let duration = min(max(0.16 + (delta / 300.0) * 0.10, 0.16), 0.30)

            if let window = popover.contentViewController?.view.window {
                let currentFrame = window.frame
                var targetContentRect = window.contentRect(forFrameRect: currentFrame)
                targetContentRect.size = targetSize
                var targetFrame = window.frameRect(forContentRect: targetContentRect)

                // Keep the popover visually anchored to the menu bar by preserving top edge.
                targetFrame.origin.y = currentFrame.maxY - targetFrame.height
                targetFrame.origin.x = currentFrame.midX - (targetFrame.width / 2)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                } completionHandler: {
                    popover.contentSize = targetSize
                }
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    popover.contentSize = targetSize
                }
            }
        }
        
        pendingPopoverResizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: work)
    }

    private func currentPopoverVisibleContentSize(_ popover: NSPopover) -> NSSize {
        if let window = popover.contentViewController?.view.window,
           let contentView = window.contentView {
            return contentView.bounds.size
        }
        return popover.contentSize
    }
    
    private func currentPopoverMaxHeight() -> CGFloat {
        let screen =
            statusItem?.button?.window?.screen ??
            popover?.contentViewController?.view.window?.screen ??
            NSScreen.main
        
        let visibleHeight = screen?.visibleFrame.height ?? 900
        let limitedHeight = floor(visibleHeight * (2.0 / 3.0))
        return max(260, limitedHeight)
    }
    
    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(storage.loadRefreshInterval() * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel.refreshAll()
                self?.updatePopoverSize()  // Update height after data changes
                self?.checkLowUsageAndNotify()
                self?.viewModel.setNextAutoRefreshDate(self?.refreshTimer?.fireDate)
            }
        }
        viewModel.setNextAutoRefreshDate(refreshTimer?.fireDate)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        pendingPopoverResizeWorkItem?.cancel()
        refreshTimer?.invalidate()
        unregisterGlobalHotKey()
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
        if let observer = appActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
