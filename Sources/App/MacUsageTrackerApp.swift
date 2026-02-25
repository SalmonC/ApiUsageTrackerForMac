import SwiftUI
import ServiceManagement
import Carbon

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
            .frame(width: 450, height: 350)
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
    private let storage = Storage.shared
    var viewModel = AppViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupMenuBar()
        setupGlobalHotKey()
        setupAppActivateObserver()
        setupRefreshTimer()
        setupSettingsCallback()
        
        NSApp.setActivationPolicy(.accessory)
        
        Task {
            await viewModel.refreshAll()
        }
    }
    
    private func setupSettingsCallback() {
        viewModel.onSettingsSaved = { [weak self] in
            Task { @MainActor in
                await self?.viewModel.refreshAll()
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
                    self.closePopover()
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
        Task {
            await viewModel.refreshAll()
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
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 450, height: 400))
            window.minSize = NSSize(width: 400, height: 300)
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
    
    private func updatePopoverSize() {
        viewModel.loadSettings()
        let enabledAccounts = viewModel.settings.accounts.filter { $0.isEnabled }.count
        let baseHeight: CGFloat = 120
        let itemHeight: CGFloat = 100
        let maxHeight: CGFloat = 500
        let minHeight: CGFloat = 200
        
        let calculatedHeight = baseHeight + CGFloat(max(enabledAccounts, 1)) * itemHeight
        let finalHeight = min(max(calculatedHeight, minHeight), maxHeight)
        
        if popover == nil {
            popover = NSPopover()
            popover?.behavior = .transient
            popover?.contentViewController = NSHostingController(
                rootView: MainView(viewModel: viewModel)
            )
        }
        popover?.contentSize = NSSize(width: 320, height: finalHeight)
    }
    
    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(storage.loadSettings().refreshInterval * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel.refreshAll()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
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
