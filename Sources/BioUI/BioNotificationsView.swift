//
//  BioNotificationsView.swift
//  BioSDK
//
//  Reusable BioUI components for displaying notifications from BioNotificationsStore.
//  Includes: BioNotificationsView, BioNotificationRow, BioNotificationBadge
//

import SwiftUI
import BioSDK

// MARK: - Markdown rendering

/// Value-type `AttributedString` box so it can live in an `NSCache` (which is
/// reference-only). NSCache is thread-safe and self-evicting under memory
/// pressure.
private final class MarkdownBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

/// Memo of parsed notification bodies, keyed by the raw source string. Bodies
/// are stable, but the feed re-evaluates every `TimelineView` tick (once/minute,
/// for the relative-time labels), which would otherwise re-parse every visible
/// row's Markdown on every tick. Parse once, reuse thereafter.
private let bioMarkdownCache: NSCache<NSString, MarkdownBox> = {
    let cache = NSCache<NSString, MarkdownBox>()
    // Two entries per notification (body + bodyPreview are separate keys), so this
    // holds ~200 notifications. Bounds growth; also self-evicts under memory pressure.
    cache.countLimit = 400
    return cache
}()

private extension String {
    /// Render a server-composed notification body as Markdown, ready for display
    /// in a notification row — or `nil` when the trimmed source is empty, so the
    /// caller omits the `Text` entirely (a `Text(AttributedString())` still
    /// reserves a line of height, leaving a phantom blank gap otherwise).
    ///
    /// Coach/insight bodies use `**bold**`, `_italics_`, inline links, and
    /// paragraph breaks — but SwiftUI's `Text(String)` renders the raw source
    /// verbatim (the literal `**` shows through). Parse to an `AttributedString`
    /// first; `.inlineOnlyPreservingWhitespace` keeps inline styling AND blank-line
    /// paragraph separation instead of collapsing single newlines. Falls back to
    /// plain text on a parse failure so a malformed body still renders. The source
    /// is trimmed (leading/trailing whitespace/newlines would otherwise render as a
    /// visible gap).
    ///
    /// Link policy is context-dependent (`linksTappable`):
    /// - **Feed row** (`linksTappable: true`) has no competing row gesture, so an
    ///   `http`/`https` link stays **tappable** — its destination isn't lost. Every
    ///   other link has only its interactivity stripped (visible text kept): a
    ///   non-web scheme (`tel:`/`sms:`/custom) **and** a schemeless/relative link
    ///   (`URL(string: "/episodes/9")` has a `nil` scheme) — so nothing dead-taps or
    ///   opens an unvalidated/relative target.
    /// - **Expand/collapse row** (`linksTappable: false`) is itself one big tap
    ///   target (`.onTapGesture` toggles), which races with any tappable link region
    ///   in the `Text`; strip **all** link interactivity there so the toggle is
    ///   unambiguous. The sanctioned action is the `webActionURL` CTA button.
    ///
    /// The display-ready value (policy already applied) is memoized on the trimmed
    /// source keyed by context, so a cache hit returns with no per-render work.
    func bioNotificationMarkdown(linksTappable: Bool) -> AttributedString? {
        let source = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        // Key by context: the two policies produce different display values. A given
        // body is rendered in only one context in practice, so this adds no real dup.
        let key = ((linksTappable ? "L|" : "_|") + source) as NSString
        if let hit = bioMarkdownCache.object(forKey: key) { return hit.value }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        // On a parse failure, return the plain-text fallback WITHOUT caching it, so
        // the cache holds only successfully-parsed values (not an immortalized fallback).
        guard var parsed = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }

        if linksTappable {
            // Keep only http/https tappable; strip every other link — non-web scheme
            // AND schemeless/relative (nil scheme). Collect ranges first — mutating a
            // run's attribute would invalidate the `runs` view mid-iteration.
            let strippableRanges: [Range<AttributedString.Index>] = parsed.runs.compactMap { run in
                guard let url = run.link else { return nil }
                let scheme = url.scheme?.lowercased() ?? ""
                return (scheme == "http" || scheme == "https") ? nil : run.range
            }
            for range in strippableRanges { parsed[range].link = nil }
        } else {
            parsed.link = nil // no tappable links in a row that is itself a tap target
        }

        bioMarkdownCache.setObject(MarkdownBox(parsed), forKey: key)
        return parsed
    }
}

private extension BioNotification {
    /// The action URL to surface as an external (Safari) CTA — non-nil only for an
    /// explicit `web_url` action with an `http`/`https` scheme. A `deep_link` (even
    /// one whose `actionUrl` is https — it routes through the host's in-app
    /// notification-tap handler, not Safari) or a non-web scheme (`tel:`/`sms:`/
    /// custom) returns nil, so neither row renders a raw external-link button for
    /// it. Single definition shared by both rows so the policy can't diverge.
    var webActionURL: URL? {
        guard actionType == "web_url",
              let actionUrl,
              let url = URL(string: actionUrl),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

// MARK: - BioNotificationsView

/// Full-page notifications view with connection status and list.
/// Use this as the main view for a notifications tab.
///
/// - Parameter projectKey: When provided, the view filters the store's
///   notifications to ones tagged with this project_key (typically the
///   active enrollment's project). Pass `nil` for cross-project views
///   (e.g. a hub-level notification tab) — all notifications display.
///   Notifications with `projectKey == nil` (pre-rollout BE frames that
///   didn't include the field) are shown regardless of the filter so they
///   don't silently disappear during the migration window.
public struct BioNotificationsView: View {
    @ObservedObject var notifications: BioNotificationsStore
    private let projectKey: String?

    /// Thumbs feedback held at the parent, keyed by notification id, so a rating
    /// survives a LazyVStack row scrolling offscreen and back (per-row @State
    /// would reset on recycle). Stage-1 local visual state only; a later stage
    /// wires it to the SDK's submitFeedback + a thumbs-down tags sheet.
    @State private var thumbs: [String: FeedThumb] = [:]

    public init(notifications: BioNotificationsStore, projectKey: String? = nil) {
        self.notifications = notifications
        self.projectKey = projectKey
    }

    /// Notifications scoped to `projectKey` if set. `nil`-keyed notifications
    /// pass through (back-compat with pre-rollout BE frames). When
    /// `projectKey == nil`, all notifications pass.
    private var visibleNotifications: [BioNotification] {
        guard let filterKey = projectKey else {
            return notifications.notifications
        }
        return notifications.notifications.filter { n in
            n.projectKey == nil || n.projectKey == filterKey
        }
    }

    /// The feed grouped into day sections, newest day first. `visibleNotifications`
    /// is already newest-first (the store sorts by createdAt desc), so walking it
    /// in order yields day buckets newest-first with newest-first items inside.
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [BioNotification]] = [:]
        for notification in visibleNotifications {
            let day = calendar.startOfDay(for: notification.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(notification)
        }
        return order.map { DaySection(day: $0, items: buckets[$0] ?? []) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Connection status banner (unchanged).
            BioNotificationConnectionBanner(notifications: notifications)

            if visibleNotifications.isEmpty {
                emptyStateView
            } else {
                feed
            }
        }
        // Mark everything read when the feed surface appears, so the unread badge
        // clears on view — no dismiss action needed. Anchored on this stable outer
        // VStack, NOT the conditional `feed`/`emptyStateView` below: `.onAppear`
        // on a view that's currently the empty branch wouldn't fire (and we still
        // want an empty feed to clear any stale count). The read model is
        // monotonic + per-xUser, so this is cheap and idempotent.
        .onAppear { notifications.markAllRead() }
        // Also clear while the feed is already on-screen: a WebSocket push that
        // arrives with the tab foregrounded bumps unreadCount but doesn't re-fire
        // onAppear, so the badge would otherwise stick over a message the user is
        // actively reading. The `> 0` guard prevents a feedback loop (markAllRead
        // drives the count back to 0, which re-enters this with newCount == 0).
        .onChange(of: notifications.unreadCount) { newCount in
            if newCount > 0 { notifications.markAllRead() }
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

    // MARK: - Continuous feed

    /// A continuous, open-text feed (newest first) rather than a tap-to-open
    /// inbox: each item shows its full body inline, grouped under day headers.
    /// ScrollView + LazyVStack (not List) keeps it a single readable stream and
    /// sidesteps the iOS 17.6+/18 `List` + `.sheet` double-present bug for the
    /// thumbs-down feedback sheet landing in a later stage.
    private var feed: some View {
        ScrollView {
            // TimelineView ticks every minute so the relative times ("5m ago")
            // and the Today/Yesterday headers stay live — they're wall-clock
            // relative, and a feed left open (e.g. a bedside RPM device) crossing
            // midnight would otherwise keep showing stale "Today"/"5m ago" until
            // some unrelated store change forced a re-render. Grouping by day is
            // independent of `now` (it keys off each item's createdAt), so only
            // the labels recompute.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(daySections) { section in
                        Section {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, notification in
                                BioNotificationFeedRow(
                                    notification: notification,
                                    now: context.date,
                                    thumb: Binding(
                                        get: { thumbs[notification.id] },
                                        set: { thumbs[notification.id] = $0 }
                                    )
                                )
                                // No divider after the section's last row — it
                                // would butt against the next pinned header
                                // (spacing is 0) and dangle below the final item.
                                if index < section.items.count - 1 {
                                    Divider().padding(.leading)
                                }
                            }
                        } header: {
                            DayHeader(day: section.day, now: context.date)
                        }
                    }
                }
            }
        }
        .refreshable {
            // Pull-to-refresh reconnects when disconnected or failed.
            switch notifications.connectionState {
            case .disconnected, .failed:
                notifications.retryNow()
            default:
                break
            }
        }
    }
}

// MARK: - FeedThumb

/// Local thumbs feedback state for a feed row (Stage 1: visual only).
private enum FeedThumb {
    case up, down
}

// MARK: - DaySection

/// One day's worth of notifications in the feed. Identified by `day` (start of
/// day) so `ForEach` is stable across re-renders.
private struct DaySection: Identifiable {
    let day: Date
    let items: [BioNotification]
    var id: Date { day }
}

// MARK: - DayHeader

/// Pinned section header labelling a day ("Today" / "Yesterday" / a date).
/// `now` is supplied by the feed's TimelineView so the relative label stays
/// correct across a midnight rollover while the view is open.
private struct DayHeader: View {
    let day: Date
    let now: Date

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
    }

    private var label: String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        if calendar.isDate(day, inSameDayAs: calendar.startOfDay(for: now)) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let formatter = DateFormatter()
        // Drop the year for the current year to keep headers short.
        formatter.dateFormat = calendar.isDate(day, equalTo: now, toGranularity: .year)
            ? "EEEE, MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: day)
    }
}

// MARK: - BioNotificationFeedRow

/// One notification in the continuous feed: priority icon, title, relative time,
/// the FULL body inline (no expand/collapse, no dismiss — the feed never removes
/// items), an optional action link, and a feedback bar (👍/👎 + a "Coming soon"
/// Reply/Ask-Coach affordance).
private struct BioNotificationFeedRow: View {
    let notification: BioNotification
    /// Current time, supplied by the feed's TimelineView so the relative
    /// timestamp stays live without each row owning a timer.
    let now: Date
    /// Thumbs state lives in the parent (keyed by id) so it survives LazyVStack
    /// row recycling. Stage-1 visual only; persistence lands in a later stage.
    @Binding var thumb: FeedThumb?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                priorityIcon
                Text(notification.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(timeAgo(notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Full body inline — this is the "open text" the redesign is about.
            // The helper returns nil for an empty/whitespace body (e.g. a title-only
            // frame), so it's skipped entirely and the feedback bar doesn't dangle
            // under a blank gap.
            if let body = notification.body.bioNotificationMarkdown(linksTappable: true) {
                Text(body)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Only surface a tappable link for an actual external web URL
            // (`webActionURL`, shared with BioNotificationRow). The BE today emits
            // actionType == "deep_link" with a host-less relative path (e.g.
            // "/episodes/<uuid>") or a null actionUrl — neither of which a SwiftUI
            // Link can route, so an ungated Link renders a dead no-op. TODO: the
            // proper in-app deep link (route to the episode via episodeId/projectKey,
            // like AppShellFeature.routeToInsights) belongs in a host-injected
            // onOpen(BioNotification) callback, not a raw URL open.
            if let url = notification.webActionURL {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }

            feedbackBar
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedbackBar: some View {
        HStack(spacing: 22) {
            thumbButton(.up, filled: "hand.thumbsup.fill", outline: "hand.thumbsup", tint: .green)
            thumbButton(.down, filled: "hand.thumbsdown.fill", outline: "hand.thumbsdown", tint: .red)
            Spacer()
            // Reply / Ask Coach — conversation infra exists on the BE but the
            // surface is deferred to a later stage; show a non-interactive,
            // clearly-labelled hint of what's coming.
            HStack(spacing: 5) {
                Image(systemName: "bubble.left")
                Text("Ask Coach · soon")
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ask Coach, coming soon")
        }
        .padding(.top, 2)
    }

    private func thumbButton(_ kind: FeedThumb, filled: String, outline: String, tint: Color) -> some View {
        Button {
            // Stage 1: toggle local visual state only (no persistence yet).
            thumb = (thumb == kind) ? nil : kind
        } label: {
            Image(systemName: thumb == kind ? filled : outline)
                .foregroundColor(thumb == kind ? tint : .secondary)
                .imageScale(.large)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .up ? "Helpful" : "Not helpful")
    }

    private var priorityIcon: some View {
        Group {
            switch notification.priority {
            case "urgent":
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            case "high":
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
            case "medium":
                Image(systemName: "bell.fill").foregroundColor(.blue)
            default:
                Image(systemName: "bell").foregroundColor(.secondary)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
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

            // Preview or full body. The Markdown helper returns nil for an
            // empty/whitespace source, so a title-only notification renders no
            // phantom blank line between the header and the type badge.
            if isExpanded {
                if let body = notification.body.bioNotificationMarkdown(linksTappable: false) {
                    Text(body)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            } else if let preview = notification.bodyPreview?.bioNotificationMarkdown(linksTappable: false) {
                // Render the preview as Markdown too, so a body-preview that
                // contains `**bold**` etc. isn't shown as raw syntax when
                // collapsed and styled when expanded (visual asymmetry).
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

            // Action URL if present — gated exactly like BioNotificationFeedRow via
            // the shared `webActionURL` helper (actionType == "web_url" AND an
            // http/https scheme). A `deep_link` notification (even one whose
            // actionUrl is https) routes through the host's in-app handler, not a
            // Safari button; and a tel:/sms:/custom-scheme actionUrl must not open
            // unconditionally.
            if isExpanded, let url = notification.webActionURL {
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
