import Foundation
import SwiftUI
import Testing
@testable import DynamicIsland

private func text(_ value: String) -> AXNode { AXNode(role: "AXStaticText", value: value) }
private func button(_ title: String) -> AXNode { AXNode(role: "AXButton", title: title) }

struct NotificationParserTests {
    let messageCard = AXNode(
        role: "AXGroup",
        subrole: "AXNotificationCenterBanner",
        label: "Messages, John Appleseed, See you at 7",
        actions: ["AXPress", "Name:Close\nTarget:0x0\nSelector:(null)"],
        children: [text("John Appleseed"), text("See you at 7"), button("Close")]
    )

    @Test func parsesMessageBanner() throws {
        let parsed = try #require(NotificationParser.parse(messageCard))
        #expect(parsed.appName == "Messages")
        #expect(parsed.title == "John Appleseed")
        #expect(parsed.body == "See you at 7")
        #expect(!parsed.isCall)
    }

    /// Structure captured from Notification Center on macOS 26.6.
    @Test func parsesTaggedFieldsFromMacOS26() throws {
        func tagged(_ id: String, _ value: String) -> AXNode { AXNode(role: "AXStaticText", value: value, identifier: id) }
        let card = AXNode(
            role: "AXGroup",
            subrole: "AXNotificationCenterBanner",
            label: "Script Editor, Test Sender, Subjudul, Halo",
            identifier: "31DA7A15-8B33-428F-96E7-CDC55EFEEFC6",
            actions: ["AXPress", "Name:Show Details\nTarget:0x0\nSelector:(null)",
                      "Name:Show\nTarget:0x0\nSelector:(null)", "Name:Close\nTarget:0x0\nSelector:(null)"],
            children: [tagged("title", "Test Sender"), tagged("subtitle", "Subjudul"), tagged("body", "Halo")]
        )
        let parsed = try #require(NotificationParser.parse(card))
        #expect(parsed.appName == "Script Editor")
        #expect(parsed.title == "Test Sender")
        #expect(parsed.body == "Subjudul — Halo")
        #expect(card.actions.map(NotificationParser.actionName) == ["AXPress", "Show Details", "Show", "Close"])
    }

    @Test func fallsBackToDescriptionWithoutTextChildren() throws {
        let card = AXNode(role: "AXGroup", subrole: "AXNotificationCenterBanner", label: "Mail, Invoice, Your bill is ready")
        let parsed = try #require(NotificationParser.parse(card))
        #expect(parsed.appName == "Mail")
        #expect(parsed.title == "Invoice")
        #expect(parsed.body == "Your bill is ready")
    }

    @Test func detectsCallAndItsButtons() throws {
        let card = AXNode(
            role: "AXGroup",
            subrole: "AXNotificationCenterAlert",
            label: "FaceTime, Mom, iPhone",
            children: [text("Mom"), text("iPhone"), button("Decline"), button("Accept")]
        )
        let parsed = try #require(NotificationParser.parse(card))
        #expect(parsed.isCall)
        #expect(parsed.acceptButton?.name == "Accept")
        #expect(parsed.declineButton?.name == "Decline")
    }

    @Test func findsInnermostCardsInsideStack() {
        let stack = AXNode(
            role: "AXGroup",
            subrole: "AXNotificationCenterBannerStack",
            children: [messageCard, messageCard]
        )
        let root = AXNode(role: "AXApplication", children: [AXNode(role: "AXWindow", children: [stack])])
        #expect(NotificationParser.notifications(in: root).count == 2)
    }

    @Test func ignoresUnrelatedElements() {
        let root = AXNode(role: "AXApplication", children: [AXNode(role: "AXWindow", children: [text("Widgets")])])
        #expect(NotificationParser.notifications(in: root).isEmpty)
    }
}

@MainActor
struct BannerTests {
    func banner(_ id: String, persistent: Bool = false, duration: Duration = .milliseconds(50)) -> BannerEvent {
        BannerEvent(id: id, content: AnyView(EmptyView()), isPersistent: persistent, duration: duration)
    }

    @Test func messageExpiresButWaitsWhileHeld() async throws {
        let manager = ActivityManager()
        manager.isBannerHeld = true
        manager.present(banner("m"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(manager.banner?.id == "m")
        manager.isBannerHeld = false
        try await Task.sleep(for: .milliseconds(500))
        #expect(manager.banner == nil)
    }

    @Test func callIsNotReplacedByMessage() {
        let manager = ActivityManager()
        manager.present(banner("call", persistent: true))
        manager.present(banner("message"))
        #expect(manager.banner?.id == "call")
        manager.dismissBanner(id: "call")
        #expect(manager.banner == nil)
    }

    @Test func bannerLayoutDropsBelowNotch() {
        let metrics = IslandMetrics(notchSize: CGSize(width: 185, height: 32), hasPhysicalNotch: true)
        let layout = metrics.layout(for: .banner, peeking: true)
        #expect(layout.size.height == 32 + IslandMetrics.bannerContentHeight)
        #expect(layout.size.width >= IslandMetrics.bannerWidth)
        #expect(layout.shapeSize.width <= IslandMetrics.windowSize.width)
        #expect(metrics.isVisible(state: .banner, peeking: false))
    }
}
