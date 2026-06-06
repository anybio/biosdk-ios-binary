//
//  BioTaskListView.swift
//  BioSDK
//
//  Reusable BioUI checklist widget — iOS parity with the Web SDK's
//  `bio-task-list`. Fetches a program's task set from the active episode's
//  sdk-config, groups by category, and records completions as
//  `task.completion` observations. Un-checking is a local-only affordance
//  (observations are append-only), matching the web behavior.
//

import SwiftUI
import BioSDK

// MARK: - BioTaskListView

/// A self-contained program-task checklist.
///
/// Usage (hub-and-spoke, e.g. AnyBio — episodeId comes from the enrollment):
/// ```swift
/// if let episodeId = program.episodeId {
///     BioTaskListView(sdk: sdk, episodeId: episodeId)
/// }
/// ```
public struct BioTaskListView: View {
    private let sdk: BioSDKClient
    private let episodeId: String
    /// Optional section title, shown only when there are tasks to display.
    private let title: String?
    /// Optional cohort filter. A task with no tags is always shown; a tagged
    /// task is shown only if it shares a tag with this set. Empty = show all.
    private let filterTags: Set<String>
    private let onTaskComplete: ((BioTask) -> Void)?
    private let onDayComplete: ((Int) -> Void)?

    @State private var tasks: [BioTask] = []
    @State private var day: Int = 0
    @State private var completed: Set<String> = []
    @State private var completing: Set<String> = []
    @State private var isLoading = true
    /// Load-time failure — shown (with a retry affordance) only when there's
    /// nothing else to display.
    @State private var loadError: String?
    /// Save-time failure — a transient banner above the (still-shown) list.
    @State private var actionError: String?
    /// The episode whose tasks are currently shown. Drives clear-on-switch so a
    /// previous program's checklist never lingers when the spoke changes.
    @State private var loadedEpisodeId: String?
    /// Fires `onDayComplete` at most once per transition into a fully-complete
    /// set (reset when the set becomes incomplete again or on episode switch).
    @State private var dayCompleteFired = false

    public init(
        sdk: BioSDKClient,
        episodeId: String,
        title: String? = nil,
        filterTags: [String] = [],
        onTaskComplete: ((BioTask) -> Void)? = nil,
        onDayComplete: ((Int) -> Void)? = nil
    ) {
        self.sdk = sdk
        self.episodeId = episodeId
        self.title = title
        self.filterTags = Set(filterTags)
        self.onTaskComplete = onTaskComplete
        self.onDayComplete = onDayComplete
    }

    public var body: some View {
        // Silent while loading and for programs with no tasks — this widget is
        // dropped into a shared Today feed, so it renders nothing rather than an
        // empty-state placeholder when a program defines no checklist.
        Group {
            if !visibleTasks.isEmpty {
                taskList
            } else if let loadError {
                // Keep the error row visible during a retry (with a spinner)
                // rather than collapsing to blank when `isLoading` flips true.
                errorRow(loadError, retrying: isLoading)
            } else {
                // First load / no tasks → invisible, always-present host. A fully
                // empty `Group` collapses to `EmptyView`, and `.task` attached to
                // `EmptyView` never fires — so `load()` would never run and the
                // list could never populate.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: episodeId) { await load() }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let actionError {
                actionBanner(actionError)
            }
            // A failed *reload* (we already have a usable list) surfaces a small,
            // non-destructive banner rather than replacing the checklist with the
            // full errorRow — content continuity, but the failure is still shown.
            if loadError != nil {
                refreshFailedBanner(retrying: isLoading)
            }
            ForEach(groupedCategories, id: \.self) { categoryKey in
                categorySection(categoryKey, tasks: grouped[categoryKey] ?? [])
            }
        }
    }

    private func refreshFailedBanner(retrying: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
            if retrying {
                Text("Refreshing…")
                ProgressView().controlSize(.small)
            } else {
                Text("Couldn't refresh")
                Spacer(minLength: 8)
                Button("Retry") { Task { await load() } }
                    .font(.caption.weight(.semibold))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: - Sections

    private func categorySection(_ categoryKey: String, tasks: [BioTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(categoryIcon(categoryKey)) \(categoryKey.capitalized)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(tasks) { task in
                taskRow(task)
                if task.id != tasks.last?.id {
                    Divider().padding(.leading, 36)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func taskRow(_ task: BioTask) -> some View {
        let isDone = completed.contains(task.id)
        let isBusy = completing.contains(task.id)
        return Button {
            toggle(task)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isDone ? .accentColor : .secondary)
                        .opacity(isBusy ? 0 : 1)
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(task.text)
                    .font(.body)
                    .foregroundColor(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(task.text)
        .accessibilityValue(isBusy ? "saving" : (isDone ? "completed" : "not completed"))
    }

    private func errorRow(_ message: String, retrying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load tasks").font(.subheadline.weight(.semibold))
            Text(message).font(.caption).foregroundColor(.secondary)
            if retrying {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Retrying…").font(.caption)
                }
                .foregroundColor(.secondary)
            } else {
                Button("Retry") { Task { await load() } }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
    }

    private func actionBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - Data

    private func load() async {
        // On an episode switch, drop the previous program's checklist before the
        // new fetch so its tasks/checks don't flash while the new set loads.
        if loadedEpisodeId != episodeId {
            tasks = []
            completed = []
            completing = []
            day = 0
            dayCompleteFired = false
        }
        isLoading = true
        actionError = nil
        // Keep any prior `loadError` set *during* the (re)load so the error row /
        // refresh banner can show a "Retrying…" state instead of vanishing — it's
        // cleared on success below, or replaced on a fresh failure.
        do {
            let config = try await sdk.fetchTaskList(episodeId: episodeId)
            loadError = nil
            let items = config?.items ?? []
            tasks = items
            day = config?.day ?? 0
            // Preserve optimistic completions still in flight (`completing`) so a
            // concurrent reload doesn't visually un-check a task whose POST isn't
            // query-visible on the server yet.
            completed = Set(items.filter(\.completed).map(\.id)).union(completing)
            loadedEpisodeId = episodeId
            // Already-complete-on-load is not a fresh transition — don't fire.
            dayCompleteFired = !visibleTasks.isEmpty
                && visibleTasks.allSatisfy { completed.contains($0.id) }
        } catch {
            // `.task(id:)` supersession (e.g. spoke switch mid-load) surfaces as
            // URLError(.cancelled) — NOT Swift CancellationError — so match both
            // and bail silently, letting the replacing load own the state.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                return
            }
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func toggle(_ task: BioTask) {
        // Ignore taps while this task's completion POST is in flight. `.disabled`
        // can miss a tap already in the gesture pipeline, and such a tap would
        // hit the un-check branch on the optimistically-inserted id and cancel an
        // in-flight save.
        guard !completing.contains(task.id) else { return }

        if completed.contains(task.id) {
            // Un-complete is local-only (observations are append-only). Clear any
            // stale save-error banner so it doesn't linger past this interaction.
            actionError = nil
            completed.remove(task.id)
            dayCompleteFired = false
            return
        }

        // Optimistic complete; revert on failure.
        actionError = nil
        completed.insert(task.id)
        completing.insert(task.id)
        // Pin the episode this completion belongs to. The POST keeps targeting
        // it correctly, but if the spoke switches to another episode while it's
        // in flight, we must not mutate the new episode's shared @State on
        // completion — `loadedEpisodeId` advances to the new episode once its
        // load resolves, so the guard drops the stale continuation.
        let targetEpisode = episodeId
        Task {
            do {
                try await sdk.completeTask(task, episodeId: targetEpisode, day: day)
                guard loadedEpisodeId == targetEpisode else { return }
                completing.remove(task.id)
                onTaskComplete?(task)
                if !dayCompleteFired
                    && !visibleTasks.isEmpty
                    && visibleTasks.allSatisfy({ completed.contains($0.id) }) {
                    dayCompleteFired = true
                    onDayComplete?(day)
                }
            } catch {
                guard loadedEpisodeId == targetEpisode else { return }
                completed.remove(task.id)
                completing.remove(task.id)
                actionError = "Couldn't save that — tap to try again."
            }
        }
    }

    // MARK: - Grouping / filtering

    private var visibleTasks: [BioTask] {
        guard !filterTags.isEmpty else { return tasks }
        return tasks.filter { task in
            guard let tags = task.tags, !tags.isEmpty else { return true } // untagged = universal
            return !filterTags.isDisjoint(with: tags)
        }
    }

    /// Normalized category key (trimmed + lowercased) so server categories that
    /// differ only by case or surrounding whitespace ("Exercise" vs "exercise ")
    /// group into one section instead of rendering as duplicates.
    private func categoryKey(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var grouped: [String: [BioTask]] {
        Dictionary(grouping: visibleTasks, by: { categoryKey($0.category) })
    }

    /// Category order: first appearance in the task list (stable, server-driven),
    /// keyed on the normalized category.
    private var groupedCategories: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for task in visibleTasks {
            let key = categoryKey(task.category)
            if seen.insert(key).inserted { order.append(key) }
        }
        return order
    }

    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "exercise": return "💪"
        case "nutrition": return "🥗"
        case "wellness": return "🧘"
        case "recovery": return "🔋"
        case "stress": return "😌"
        case "sleep": return "😴"
        case "reflection": return "📝"
        case "mindfulness": return "🧘"
        case "hydration": return "💧"
        default: return "✓"
        }
    }
}
