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
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var appActivateObserver: NSObjectProtocol?
    private var preferredPopoverContentHeight: CGFloat?
    private var pendingPopoverResizeWorkItem: DispatchWorkItem?
    private var pendingPopoverSize: NSSize?
    private var isTrackingContentResizeAnimation = false
    private var contentResizeAnimationEndTime: CFTimeInterval?
    private let synchronizedContentResizeDuration: TimeInterval = 0.24
    private var synchronizedPopoverResizeTimer: Timer?
    private var synchronizedPopoverResizeStartTime: CFTimeInterval = 0
    private var synchronizedPopoverResizeDuration: CFTimeInterval = 0
    private var synchronizedPopoverResizeStartFrame: NSRect?
    private var synchronizedPopoverResizeTargetFrame: NSRect?
    private var synchronizedPopoverResizeTargetContentSize: NSSize?
    private let synchronizedPopoverResizeFrameInterval: TimeInterval = 1.0 / 60.0
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
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "API Tracker")
            button.action = #selector(leftClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func setupGlobalHotKey() {
        updateGlobalHotKey()
    }
    
    private func updateGlobalHotKey() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        
        let hotkey = viewModel.settings.hotkey
        let targetKeyCode = hotkey.keyCode
        let targetModifiers = hotkey.modifiers
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && self?.checkModifiers(event.modifierFlags, target: targetModifiers) == true {
                DispatchQueue.main.async {
                    self?.showPopover()
                }
            }
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && self?.checkModifiers(event.modifierFlags, target: targetModifiers) == true {
                DispatchQueue.main.async {
                    self?.showPopover()
                }
                return nil
            }
            return event
        }
    }
    
    private func checkModifiers(_ flags: NSEvent.ModifierFlags, target: UInt32) -> Bool {
        let hasCommand = (target & UInt32(NSEvent.ModifierFlags.command.rawValue)) != 0
        let hasShift = (target & UInt32(NSEvent.ModifierFlags.shift.rawValue)) != 0
        let hasOption = (target & UInt32(NSEvent.ModifierFlags.option.rawValue)) != 0
        let hasControl = (target & UInt32(NSEvent.ModifierFlags.control.rawValue)) != 0
        
        return flags.contains(.command) == hasCommand &&
               flags.contains(.shift) == hasShift &&
               flags.contains(.option) == hasOption &&
               flags.contains(.control) == hasControl
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
        stopSynchronizedPopoverResize()
        isTrackingContentResizeAnimation = false
        contentResizeAnimationEndTime = nil
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
                    },
                    onExpansionAnimationPhaseChange: { [weak self] isAnimating in
                        Task { @MainActor in
                            guard let self else { return }
                            let now = CACurrentMediaTime()
                            if isAnimating {
                                if self.isTrackingContentResizeAnimation {
                                    let extendedEnd = now + self.synchronizedContentResizeDuration
                                    self.contentResizeAnimationEndTime = max(self.contentResizeAnimationEndTime ?? 0, extendedEnd)
                                } else {
                                    self.isTrackingContentResizeAnimation = true
                                    self.contentResizeAnimationEndTime = now + self.synchronizedContentResizeDuration
                                }
                            } else {
                                self.isTrackingContentResizeAnimation = false
                                self.contentResizeAnimationEndTime = nil
                            }
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
            stopSynchronizedPopoverResize()
            popover.contentSize = newSize
            return
        }
        
        let currentVisibleSize = currentPopoverVisibleContentSize(popover)
        if abs(currentVisibleSize.height - newSize.height) < 1 &&
            abs(currentVisibleSize.width - newSize.width) < 1 {
            return
        }

        if isTrackingContentResizeAnimation {
            pendingPopoverResizeWorkItem?.cancel()
            pendingPopoverResizeWorkItem = nil
            pendingPopoverSize = nil
            applyPopoverSizeDuringContentAnimation(newSize, to: popover)
            return
        }

        stopSynchronizedPopoverResize()
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    private func applyPopoverSizeImmediately(_ targetSize: NSSize, to popover: NSPopover) {
        if let window = popover.contentViewController?.view.window {
            let currentFrame = window.frame
            let targetFrame = popoverFrame(forContentSize: targetSize, basedOn: currentFrame, in: window)
            window.setFrame(targetFrame, display: true)
        }
        popover.contentSize = targetSize
    }

    private func applyPopoverSizeDuringContentAnimation(_ targetSize: NSSize, to popover: NSPopover) {
        guard let window = popover.contentViewController?.view.window else {
            applyPopoverSizeImmediately(targetSize, to: popover)
            return
        }

        let now = CACurrentMediaTime()
        let animationEnd = contentResizeAnimationEndTime ?? (now + synchronizedContentResizeDuration)
        let remaining = max(animationEnd - now, 0.001)
        let duration = min(max(remaining, 0.08), synchronizedContentResizeDuration)
        let targetFrame = popoverFrame(forContentSize: targetSize, basedOn: window.frame, in: window)

        if synchronizedPopoverResizeTimer == nil {
            let timer = Timer(timeInterval: synchronizedPopoverResizeFrameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stepSynchronizedPopoverResize()
                }
            }
            timer.tolerance = 0
            synchronizedPopoverResizeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        // Rebase every target update onto the current window frame so long rows
        // do not keep stretching a single animation timeline and causing lag.
        synchronizedPopoverResizeStartTime = now
        synchronizedPopoverResizeDuration = duration
        synchronizedPopoverResizeStartFrame = window.frame
        synchronizedPopoverResizeTargetFrame = targetFrame
        synchronizedPopoverResizeTargetContentSize = targetSize

        // Apply the first interpolation step immediately to reduce one-tick latency.
        stepSynchronizedPopoverResize()
    }

    private func stepSynchronizedPopoverResize() {
        guard
            let popover,
            let window = popover.contentViewController?.view.window,
            let startFrame = synchronizedPopoverResizeStartFrame,
            let targetFrame = synchronizedPopoverResizeTargetFrame
        else {
            stopSynchronizedPopoverResize()
            return
        }

        let duration = max(synchronizedPopoverResizeDuration, 0.08)
        let elapsed = CACurrentMediaTime() - synchronizedPopoverResizeStartTime
        let progress = min(max(elapsed / duration, 0), 1)
        let easedProgress = easeInOutCubic(progress)
        let frame = interpolatedFrame(from: startFrame, to: targetFrame, progress: easedProgress)
        window.setFrame(frame, display: true)

        if progress >= 1 {
            if let targetSize = synchronizedPopoverResizeTargetContentSize {
                popover.contentSize = targetSize
            }
            stopSynchronizedPopoverResize()
        }
    }

    private func stopSynchronizedPopoverResize() {
        synchronizedPopoverResizeTimer?.invalidate()
        synchronizedPopoverResizeTimer = nil
        synchronizedPopoverResizeStartTime = 0
        synchronizedPopoverResizeDuration = 0
        synchronizedPopoverResizeStartFrame = nil
        synchronizedPopoverResizeTargetFrame = nil
        synchronizedPopoverResizeTargetContentSize = nil
    }

    private func popoverFrame(forContentSize targetSize: NSSize, basedOn currentFrame: NSRect, in window: NSWindow) -> NSRect {
        var targetContentRect = window.contentRect(forFrameRect: currentFrame)
        targetContentRect.size = targetSize
        var targetFrame = window.frameRect(forContentRect: targetContentRect)

        // Keep the popover visually anchored to the menu bar by preserving top edge.
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height
        targetFrame.origin.x = currentFrame.midX - (targetFrame.width / 2)
        return targetFrame
    }

    private func interpolatedFrame(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        let t = max(0, min(progress, 1))
        return NSRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * t,
            y: start.origin.y + (end.origin.y - start.origin.y) * t,
            width: start.size.width + (end.size.width - start.size.width) * t,
            height: start.size.height + (end.size.height - start.size.height) * t
        )
    }

    private func easeInOutCubic(_ progress: CGFloat) -> CGFloat {
        if progress < 0.5 {
            return 4 * progress * progress * progress
        }
        let p = -2 * progress + 2
        return 1 - (p * p * p) / 2
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
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        pendingPopoverResizeWorkItem?.cancel()
        stopSynchronizedPopoverResize()
        refreshTimer?.invalidate()
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
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
