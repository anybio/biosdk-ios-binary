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
    /// Load-time failure — replaces content (we have nothing to show).
    @State private var loadError: String?
    /// Save-time failure — a transient banner above the (still-shown) list.
    @State private var actionError: String?

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
        // dropped into a shared Today feed, so it must render nothing rather
        // than an empty-state placeholder when a program defines no checklist.
        Group {
            if let loadError, !isLoading {
                errorRow(loadError)
            } else if !visibleTasks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let actionError {
                        actionBanner(actionError)
                    }
                    ForEach(groupedCategories, id: \.self) { category in
                        categorySection(category, tasks: grouped[category] ?? [])
                    }
                }
            } else {
                // Zero-size, always-present host. A fully-empty `Group` collapses
                // to `EmptyView`, and `.task` attached to `EmptyView` never fires —
                // so `load()` would never run and the list could never populate.
                // This invisible placeholder keeps a stable view for `.task` to
                // attach to while loading / when there are no tasks.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: episodeId) { await load() }
    }

    // MARK: - Sections

    private func categorySection(_ category: String, tasks: [BioTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(categoryIcon(category)) \(category.capitalized)")
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
        .accessibilityValue(isDone ? "completed" : "not completed")
    }

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load tasks").font(.subheadline.weight(.semibold))
            Text(message).font(.caption).foregroundColor(.secondary)
            Button("Retry") { Task { await load() } }
                .font(.caption.weight(.semibold))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func actionBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        actionError = nil
        do {
            let config = try await sdk.fetchTaskList(episodeId: episodeId)
            let items = config?.items ?? []
            tasks = items
            day = config?.day ?? 0
            completed = Set(items.filter(\.completed).map(\.id))
        } catch is CancellationError {
            // View went away or episode changed — let the replacing load own state.
            return
        } catch {
            loadError = (error as NSError).localizedDescription
        }
        isLoading = false
    }

    private func toggle(_ task: BioTask) {
        if completed.contains(task.id) {
            // Un-complete is local-only (observations are append-only).
            completed.remove(task.id)
            return
        }
        // Optimistic complete; revert on failure.
        actionError = nil
        completed.insert(task.id)
        completing.insert(task.id)
        Task {
            do {
                try await sdk.completeTask(task, episodeId: episodeId, day: day)
                completing.remove(task.id)
                onTaskComplete?(task)
                if visibleTasks.allSatisfy({ completed.contains($0.id) }) {
                    onDayComplete?(day)
                }
            } catch {
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

    private var grouped: [String: [BioTask]] {
        Dictionary(grouping: visibleTasks, by: \.category)
    }

    /// Category order: first appearance in the task list (stable, server-driven).
    private var groupedCategories: [String] {
        var seen = Set<String>()
        return visibleTasks.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
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
