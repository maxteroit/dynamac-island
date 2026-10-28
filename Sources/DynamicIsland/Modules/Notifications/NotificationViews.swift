import SwiftUI

private struct AppIconView: View {
    let icon: NSImage?
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.22).fill(.white.opacity(0.15)))
            }
        }
        .frame(width: size, height: size)
    }
}

struct NotificationCardView: View {
    let notification: ParsedNotification
    let icon: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIconView(icon: icon)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(notification.appName ?? "Notification")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(notification.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let body = notification.body {
                    Text(body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

struct IncomingCallView: View {
    let notification: ParsedNotification
    let icon: NSImage?
    let onHandled: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(notification.body ?? "Incoming call")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let decline = notification.declineButton {
                callButton("phone.down.fill", color: .red) {
                    NotificationCenterObserver.press(decline)
                    onHandled()
                }
            }
            if let accept = notification.acceptButton {
                callButton("phone.fill", color: .green) {
                    NotificationCenterObserver.press(accept)
                    onHandled()
                }
                .symbolEffect(.pulse, options: .repeating)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func callButton(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
