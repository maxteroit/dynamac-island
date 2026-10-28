import ApplicationServices
import Foundation

/// Plain copy of an accessibility element subtree. Parsing works on this
/// snapshot so it can be tested without a live Notification Center.
struct AXNode {
    var role: String?
    var subrole: String?
    var title: String?
    var label: String?
    var value: String?
    var identifier: String?
    var actions: [String] = []
    var children: [AXNode] = []
    /// Live element, nil in tests.
    var element: AXUIElement?

    func descendants() -> [AXNode] {
        children.flatMap { [$0] + $0.descendants() }
    }

    /// Indented outline for the debug dump.
    func outline(indent: Int = 0) -> String {
        let fields = [
            role.map { "role=\($0)" },
            subrole.map { "subrole=\($0)" },
            identifier.map { "id=\($0)" },
            title.map { "title=\"\($0)\"" },
            label.map { "desc=\"\($0)\"" },
            value.map { "value=\"\($0)\"" },
            actions.isEmpty ? nil : "actions=\(actions)",
        ].compactMap { $0 }
        let line = String(repeating: "  ", count: indent) + fields.joined(separator: " ")
        return ([line] + children.map { $0.outline(indent: indent + 1) }).joined(separator: "\n")
    }
}

struct ParsedNotification {
    struct Button {
        let name: String
        let node: AXNode
    }

    /// Stable while the same banner stays on screen.
    let key: String
    let appName: String?
    let title: String
    let body: String?
    let isCall: Bool
    let buttons: [Button]
    let node: AXNode

    var acceptButton: Button? {
        buttons.first { NotificationParser.matches($0.name, NotificationParser.acceptWords) }
    }

    var declineButton: Button? {
        buttons.first { NotificationParser.matches($0.name, NotificationParser.declineWords) }
    }
}

enum NotificationParser {
    static let acceptWords = ["accept", "answer", "terima", "jawab"]
    static let declineWords = ["decline", "reject", "tolak"]
    static let closeWords = ["close", "clear", "tutup"]
    static let callApps: Set<String> = ["FaceTime", "Phone", "Telepon", "WhatsApp", "Telegram", "Zoom", "Microsoft Teams"]

    /// Custom AX actions look like "Name:Show\nTarget:0x0\nSelector:(null)".
    static func actionName(_ action: String) -> String {
        guard action.hasPrefix("Name:") else { return action }
        return String(action.dropFirst(5).prefix { $0 != "\n" })
    }

    static func matches(_ text: String, _ words: [String]) -> Bool {
        let lowered = text.lowercased()
        return words.contains { lowered.contains($0) }
    }

    /// Notification Center marks cards with subroles like
    /// `AXNotificationCenterBanner` and `AXNotificationCenterAlert` (calls).
    static func isCard(_ node: AXNode) -> Bool {
        guard let subrole = node.subrole, subrole.hasPrefix("AXNotificationCenter") else { return false }
        return subrole.contains("Banner") || subrole.contains("Alert")
    }

    /// Innermost cards in the tree (stack containers are skipped).
    static func notifications(in root: AXNode) -> [ParsedNotification] {
        var cards: [AXNode] = []
        func visit(_ node: AXNode) {
            let nested = node.descendants().contains(where: isCard)
            if isCard(node) && !nested {
                cards.append(node)
            } else {
                node.children.forEach(visit)
            }
        }
        visit(root)
        return cards.compactMap(parse)
    }

    static func parse(_ card: AXNode) -> ParsedNotification? {
        var texts: [String] = []
        var tagged: [String: String] = [:]
        var buttons: [ParsedNotification.Button] = []
        func collect(_ node: AXNode) {
            if node.role == "AXButton" {
                if let name = [node.title, node.label].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                    buttons.append(.init(name: name, node: node))
                }
                return
            }
            if node.role == "AXStaticText", let text = node.value ?? node.label, !text.isEmpty {
                texts.append(text)
                // macOS 26 tags the fields with identifiers: title, subtitle, body.
                if let identifier = node.identifier {
                    tagged[identifier] = text
                }
            }
            node.children.forEach(collect)
        }
        card.children.forEach(collect)

        // The card's description reads "App, Title, Body"; use it when no text children exist.
        let labelParts = (card.label ?? "").components(separatedBy: ", ").filter { !$0.isEmpty }
        if texts.isEmpty {
            texts = Array(labelParts.dropFirst())
        }
        guard let title = tagged["title"] ?? texts.first else { return nil }

        var appName: String?
        if let first = labelParts.first, first != title {
            appName = first
        }
        let body: String
        if tagged["title"] != nil {
            body = [tagged["subtitle"], tagged["body"]].compactMap { $0 }.joined(separator: " — ")
        } else {
            body = texts.dropFirst().joined(separator: " ")
        }
        let actionButtons = buttons.filter { !matches($0.name, closeWords) }
        let hasCallButtons = actionButtons.contains { matches($0.name, acceptWords) }
            && actionButtons.contains { matches($0.name, declineWords) }
        let isCall = hasCallButtons || (card.subrole?.contains("Alert") == true && appName.map(callApps.contains) == true)

        let hash = card.element.map { String(CFHash($0)) } ?? ""
        return ParsedNotification(
            key: [hash, appName ?? "", title, body].joined(separator: "|"),
            appName: appName,
            title: title,
            body: body.isEmpty ? nil : body,
            isCall: isCall,
            buttons: buttons,
            node: card
        )
    }
}
