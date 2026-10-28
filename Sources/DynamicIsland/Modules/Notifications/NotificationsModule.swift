import AppKit
import Observation
import SwiftUI

enum NotificationDisplayMode: String, CaseIterable, Sendable {
    /// Island card and the macOS banner.
    case both
    /// Island card only; the macOS banner is closed right away.
    case islandOnly
    /// macOS banner only; the island ignores notifications.
    case systemOnly

    var title: String {
        switch self {
        case .both: "Island + macOS Banner"
        case .islandOnly: "Island Only"
        case .systemOnly: "macOS Banner Only"
        }
    }
}

/// Mirrors messages and incoming calls from Notification Center into the island.
@MainActor
@Observable
final class NotificationsModule {
    static let modeKey = "notificationDisplayMode"

    var mode: NotificationDisplayMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    @ObservationIgnored private weak var manager: ActivityManager?
    @ObservationIgnored let observer = NotificationCenterObserver()
    /// Call banners end with their macOS alert; message cards outlive the macOS banner.
    @ObservationIgnored private var callKeys: Set<String> = []

    init(manager: ActivityManager) {
        self.manager = manager
        mode = UserDefaults.standard.string(forKey: Self.modeKey)
            .flatMap(NotificationDisplayMode.init(rawValue:)) ?? .both
        observer.onAppear = { [weak self] notification in self?.show(notification) }
        observer.onDisappear = { [weak self] key in
            guard let self, self.callKeys.remove(key) != nil else { return }
            self.manager?.dismissBanner(id: key)
        }
        observer.start()
    }

    var hasAccess: Bool { observer.isTrusted }

    func requestAccess() {
        observer.requestAccess()
    }

    private func show(_ notification: ParsedNotification) {
        guard mode != .systemOnly else { return }
        let icon = Self.icon(forApp: notification.appName)

        if notification.isCall {
            callKeys.insert(notification.key)
            // Calls keep their macOS alert: closing it could hang up.
            manager?.present(BannerEvent(
                id: notification.key,
                content: AnyView(IncomingCallView(notification: notification, icon: icon) { [weak self] in
                    self?.manager?.dismissBanner(id: notification.key)
                }),
                isPersistent: true
            ))
            return
        }

        manager?.present(BannerEvent(
            id: notification.key,
            content: AnyView(NotificationCardView(notification: notification, icon: icon)),
            onTap: { NotificationCenterObserver.open(notification) }
        ))
        if mode == .islandOnly {
            NotificationCenterObserver.dismissSystemBanner(notification)
        }
    }

    /// Icon of a running or installed app with the given display name.
    static func icon(forApp name: String?) -> NSImage? {
        appURL(named: name).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Bundle location of a running or installed app with the given display name.
    static func appURL(named name: String?) -> URL? {
        guard let name else { return nil }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
           let url = running.bundleURL {
            return url
        }
        return ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: "\($0)/\(name).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
