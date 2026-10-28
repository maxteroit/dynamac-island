import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "App")
    private let activities = ActivityManager()
    private let modules: IslandModules
    private let viewModel: IslandViewModel
    private var windowController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var demoMenuItem: NSMenuItem?
    private var hoverMenuItem: NSMenuItem?
    private var volumeMonitor: VolumeMonitor?
    private var brightnessMonitor: BrightnessMonitor?
    private var notifications: NotificationsModule?
    private var notificationModeItems: [NSMenuItem] = []
    private var notificationAccessItem: NSMenuItem?
    private var notificationDumpItem: NSMenuItem?

    override init() {
        modules = IslandModules(
            timer: TimerActivity(manager: activities),
            battery: BatteryMonitor(manager: activities),
            nowPlaying: NowPlayingActivity.makeDefault(),
            demo: DemoActivity()
        )
        activities.register(modules.timer)
        activities.register(modules.nowPlaying)
        activities.register(modules.demo)
        viewModel = IslandViewModel(activities: activities, modules: modules)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.preferredIslandScreen else {
            logger.error("No screen available")
            return
        }
        windowController = IslandWindowController(screen: screen, viewModel: viewModel)
        volumeMonitor = VolumeMonitor(manager: activities)
        brightnessMonitor = BrightnessMonitor(manager: activities)
        if brightnessMonitor == nil {
            logger.notice("Brightness HUD disabled: no built-in display or DisplayServices unavailable")
        }
        notifications = NotificationsModule(manager: activities)
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func screensDidChange() {
        guard let screen = NSScreen.preferredIslandScreen else { return }
        windowController?.move(to: screen)
    }

    // MARK: - Status item (dev controls until Settings exists)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")

        let menu = NSMenu()
        demoMenuItem = menu.addItem(withTitle: "Demo Live Activity", action: #selector(toggleDemoActivity), keyEquivalent: "d")
        menu.addItem(withTitle: "Start 10s Timer", action: #selector(startShortTimer), keyEquivalent: "t")
        menu.addItem(withTitle: "Simulate Charger", action: #selector(simulateCharger), keyEquivalent: "c")
        menu.addItem(.separator())
        hoverMenuItem = menu.addItem(withTitle: "Expand on Hover", action: #selector(toggleExpandOnHover), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(makeNotificationsMenuItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dynamic Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshMenuState()
    }

    @objc private func toggleDemoActivity() {
        modules.demo.toggle()
        refreshMenuState()
    }

    @objc private func startShortTimer() {
        modules.timer.start(minutes: 10.0 / 60)
    }

    @objc private func simulateCharger() {
        modules.battery.simulatePlugIn()
    }

    @objc private func toggleExpandOnHover() {
        viewModel.expandOnHover.toggle()
        refreshMenuState()
    }

    private func makeNotificationsMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        notificationAccessItem = submenu.addItem(
            withTitle: "Enable Notification Access…", action: #selector(requestNotificationAccess), keyEquivalent: ""
        )
        submenu.addItem(.separator())
        notificationModeItems = NotificationDisplayMode.allCases.map { mode in
            let item = submenu.addItem(withTitle: mode.title, action: #selector(selectNotificationMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            return item
        }
        submenu.addItem(.separator())
        notificationDumpItem = submenu.addItem(
            withTitle: "Log Notification Tree (debug)", action: #selector(toggleNotificationDump), keyEquivalent: ""
        )
        submenu.items.forEach { $0.target = self }

        let item = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func requestNotificationAccess() {
        notifications?.requestAccess()
    }

    @objc private func selectNotificationMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = NotificationDisplayMode(rawValue: raw) else { return }
        notifications?.mode = mode
        refreshMenuState()
    }

    @objc private func toggleNotificationDump() {
        guard let observer = notifications?.observer else { return }
        observer.debugDump.toggle()
        UserDefaults.standard.set(observer.debugDump, forKey: "debugNotificationDump")
        refreshMenuState()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func refreshMenuState() {
        demoMenuItem?.state = modules.demo.isEnabled ? .on : .off
        hoverMenuItem?.state = viewModel.expandOnHover ? .on : .off
        let hasAccess = notifications?.hasAccess ?? false
        notificationAccessItem?.title = hasAccess ? "Notification Access Enabled" : "Enable Notification Access…"
        notificationAccessItem?.isEnabled = !hasAccess
        for item in notificationModeItems {
            item.state = item.representedObject as? String == notifications?.mode.rawValue ? .on : .off
        }
        notificationDumpItem?.state = notifications?.observer.debugDump == true ? .on : .off
    }
}
