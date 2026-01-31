//
//  BioNotificationsView.swift
//  BioSDK
//
//  Reusable BioUI components for displaying notifications from BioNotificationsStore.
//  Includes: BioNotificationsView, BioNotificationRow, BioNotificationBadge
//

import SwiftUI
import BioSDK

// MARK: - BioNotificationsView

/// Full-page notifications view with connection status and list.
/// Use this as the main view for a notifications tab.
public struct BioNotificationsView: View {
    @ObservedObject var notifications: BioNotificationsStore

    public init(notifications: BioNotificationsStore) {
        self.notifications = notifications
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Connection status banner
            BioNotificationConnectionBanner(notifications: notifications)

            if notifications.notifications.isEmpty {
                emptyStateView
            } else {
                notificationsList
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Notifications")
                .font(.title2)
                .fontWeight(.semibold)
            Text("When you receive notifications from your care team, they'll appear here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        List {
            ForEach(notifications.notifications, id: \.id) { notification in
                BioNotificationRow(
                    notification: notification,
                    onAcknowledge: { notifications.acknowledge(notificationId: notification.id) },
                    onDismiss: { notifications.dismiss(notificationId: notification.id) }
                )
            }
        }
        .listStyle(.plain)
        .refreshable {
            // Allow refresh when disconnected or failed
            switch notifications.connectionState {
            case .disconnected, .failed:
                notifications.retryNow()
            default:
                break
            }
        }
    }
}

// MARK: - BioNotificationConnectionBanner

/// Displays connection status banner for notifications WebSocket.
/// Shows connecting/reconnecting/disconnected states with reconnect button.
public struct BioNotificationConnectionBanner: View {
    @ObservedObject var notifications: BioNotificationsStore

    public init(notifications: BioNotificationsStore) {
        self.notifications = notifications
    }

    public var body: some View {
        switch notifications.connectionState {
        case .connecting:
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting...")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.2))

        case .waitingToReconnect(let delay, let attempt, let maxAttempts):
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconnecting in \(Int(delay))s...")
                        .font(.caption)
                    Text("Attempt \(attempt) of \(maxAttempts)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Retry Now") {
                    notifications.retryNow()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.2))

        case .disconnected:
            HStack {
                Image(systemName: "wifi.slash")
                Text("Disconnected")
                    .font(.caption)
                Spacer()
                Button("Connect") {
                    notifications.retryNow()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.2))

        case .failed(let reason):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.red)
                Spacer()
                Button("Retry") {
                    notifications.retryNow()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.2))

        case .connected:
            EmptyView()
        }
    }
}

// MARK: - BioNotificationConnectionIndicator

/// Small connection indicator showing a colored dot and status text.
/// Use this in navigation bar or header areas.
public struct BioNotificationConnectionIndicator: View {
    @ObservedObject var notifications: BioNotificationsStore

    public init(notifications: BioNotificationsStore) {
        self.notifications = notifications
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(connectionStatusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var connectionStatusText: String {
        switch notifications.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .waitingToReconnect(let delay, _, _): return "Retry in \(Int(delay))s"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    private var connectionColor: Color {
        switch notifications.connectionState {
        case .connected: return .green
        case .connecting, .waitingToReconnect: return .orange
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
}

// MARK: - BioNotificationBadge

/// Badge showing unread notification count.
/// Use this on tab bar items or buttons.
public struct BioNotificationBadge: View {
    @ObservedObject var notifications: BioNotificationsStore

    public init(notifications: BioNotificationsStore) {
        self.notifications = notifications
    }

    public var body: some View {
        if notifications.unreadCount > 0 {
            Text("\(notifications.unreadCount)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }
}

// MARK: - BioNotificationRow

/// Individual notification row with expand/collapse functionality.
/// Shows priority icon, title, preview, type badge, and action buttons.
public struct BioNotificationRow: View {
    let notification: BioNotification
    let onAcknowledge: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    public init(
        notification: BioNotification,
        onAcknowledge: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.notification = notification
        self.onAcknowledge = onAcknowledge
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                priorityIcon
                Text(notification.title)
                    .font(.headline)
                Spacer()
                Text(timeAgo(notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Preview or full body
            if isExpanded {
                Text(notification.body)
                    .font(.body)
                    .foregroundColor(.primary)
            } else if let preview = notification.bodyPreview {
                Text(preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Type badge and actions
            HStack {
                Text(formatNotificationType(notification.notificationType))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.2))
                    .foregroundColor(typeColor)
                    .cornerRadius(4)

                Spacer()

                // Action buttons (only when expanded)
                if isExpanded {
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onAcknowledge) {
                        Text("Acknowledge")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Action URL if present
            if isExpanded, let actionUrl = notification.actionUrl, let url = URL(string: actionUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open Details")
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var priorityIcon: some View {
        Group {
            switch notification.priority {
            case "urgent":
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            case "high":
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
            case "medium":
                Image(systemName: "bell.fill")
                    .foregroundColor(.blue)
            default:
                Image(systemName: "bell")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var typeColor: Color {
        switch notification.notificationType {
        case "episode_started", "episode_ended":
            return .purple
        case "vital_alert":
            return .red
        case "medication_reminder":
            return .green
        case "appointment_reminder":
            return .blue
        case "care_plan_update":
            return .orange
        default:
            return .gray
        }
    }

    private func formatNotificationType(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("Notifications View - Empty") {
    BioNotificationsView(notifications: BioNotificationsStore())
}

#Preview("Connection Banner") {
    VStack {
        BioNotificationConnectionBanner(notifications: BioNotificationsStore())
    }
}
