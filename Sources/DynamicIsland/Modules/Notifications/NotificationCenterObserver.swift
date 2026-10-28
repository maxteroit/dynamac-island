import AppKit
import ApplicationServices
import OSLog

/// Watches Notification Center's banners through the Accessibility API.
/// Requires the Accessibility permission; waits quietly until it is granted.
@MainActor
final class NotificationCenterObserver {
    static let bundleIdentifier = "com.apple.notificationcenterui"
    static let dumpURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DynamicIsland/notification-ax.txt")

    var onAppear: ((ParsedNotification) -> Void)?
    var onDisappear: ((String) -> Void)?
    /// Writes the Notification Center tree to `dumpURL` on every change. Contains
    /// notification text, so it is off by default.
    var debugDump = UserDefaults.standard.bool(forKey: "debugNotificationDump")

    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "Notifications")
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var visibleKeys: Set<String> = []
    private var trustPollTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?

    var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        if isTrusted {
            attach()
        } else {
            waitForTrust()
        }
    }

    /// Shows the system prompt and opens the Accessibility pane.
    func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        waitForTrust()
    }

    private func waitForTrust() {
        guard trustPollTask == nil else { return }
        trustPollTask = Task { [weak self] in
            while let self, !self.isTrusted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
            }
            guard let self, !Task.isCancelled else { return }
            self.trustPollTask = nil
            self.logger.info("Accessibility granted")
            self.attach()
        }
    }

    @objc private func appLaunched(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == Self.bundleIdentifier, isTrusted {
            attach()
        }
    }

    // MARK: - AX observation

    private func attach() {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
            .first?.processIdentifier else {
            logger.error("Notification Center is not running")
            return
        }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let owner = Unmanaged<NotificationCenterObserver>.fromOpaque(refcon).takeUnretainedValue()
            // Run loop source lives on the main run loop.
            MainActor.assumeIsolated { owner.scheduleScan() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            logger.error("AXObserverCreate failed")
            return
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Lives for the whole app run, so an unretained pointer is safe.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let events = [
            kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXCreatedNotification,
            kAXLayoutChangedNotification, kAXValueChangedNotification, kAXFocusedUIElementChangedNotification,
        ]
        for event in events {
            AXObserverAddNotification(created, app, event as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        appElement = app
        logger.info("Observing Notification Center (pid \(pid))")
        scan()
    }

    /// Coalesces bursts of AX events into one scan.
    private func scheduleScan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            self.scan()
        }
    }

    private func scan() {
        guard let appElement else { return }
        let root = Self.snapshotWindows(of: appElement)
        if debugDump {
            writeDump(root)
        }
        let notifications = NotificationParser.notifications(in: root)
        let keys = Set(notifications.map(\.key))

        for notification in notifications where !visibleKeys.contains(notification.key) {
            if notification.isCall, let element = notification.node.element, let observer {
                // Calls end when their alert goes away.
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            }
            logger.info("Banner appeared (call: \(notification.isCall))")
            onAppear?(notification)
        }
        for key in visibleKeys.subtracting(keys) {
            logger.info("Banner disappeared")
            onDisappear?(key)
        }
        visibleKeys = keys
    }

    private func writeDump(_ root: AXNode) {
        let text = "Dumped \(Date.now)\n\n" + root.outline()
        try? FileManager.default.createDirectory(at: Self.dumpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: Self.dumpURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Actions

    /// Presses a button on the banner (Accept, Decline, Reply...).
    static func press(_ button: ParsedNotification.Button) {
        guard let element = button.node.element else { return }
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// Opens the notification's source, like clicking the banner. Once the macOS
    /// banner is gone (expired or closed) the app itself is opened instead.
    static func open(_ notification: ParsedNotification) {
        let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "Notifications")
        if let element = notification.node.element {
            let action = notification.node.actions.first { NotificationParser.actionName($0) == "Show" }
                ?? kAXPressAction as String
            let result = AXUIElementPerformAction(element, action as CFString)
            logger.info("Show banner: AXError \(result.rawValue)")
            if result == .success { return }
        }
        guard let url = NotificationsModule.appURL(named: notification.appName) else {
            logger.error("Open: app not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Closes the system banner; the notification stays in Notification Center.
    /// Retries because the banner may still be animating in.
    static func dismissSystemBanner(_ notification: ParsedNotification, attempt: Int = 1) {
        let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "Notifications")
        var result = AXError.actionUnsupported
        if let element = notification.node.element,
           let close = notification.node.actions.first(where: {
               NotificationParser.matches(NotificationParser.actionName($0), NotificationParser.closeWords)
           }) {
            result = AXUIElementPerformAction(element, close as CFString)
        } else if let button = notification.buttons.first(where: { NotificationParser.matches($0.name, NotificationParser.closeWords) }),
                  let element = button.node.element {
            result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
        logger.info("Close banner attempt \(attempt): AXError \(result.rawValue)")
        guard result != .success, attempt < 3 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            dismissSystemBanner(notification, attempt: attempt + 1)
        }
    }

    // MARK: - Snapshot

    /// Only the windows hold banners; the app's menu bar is large and irrelevant.
    static func snapshotWindows(of app: AXUIElement) -> AXNode {
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let elements = windows as? [AXUIElement] else { return AXNode(role: "AXApplication") }
        return AXNode(role: "AXApplication", children: elements.map { snapshot($0, depth: 10) })
    }

    static func snapshot(_ element: AXUIElement, depth: Int) -> AXNode {
        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }
        var node = AXNode(
            role: string(kAXRoleAttribute),
            subrole: string(kAXSubroleAttribute),
            title: string(kAXTitleAttribute),
            label: string(kAXDescriptionAttribute),
            value: string(kAXValueAttribute),
            identifier: string(kAXIdentifierAttribute),
            element: element
        )
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success, let names = actionNames as? [String] {
            node.actions = names
        }
        if depth > 0 {
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let elements = children as? [AXUIElement] {
                node.children = elements.map { snapshot($0, depth: depth - 1) }
            }
        }
        return node
    }
}
