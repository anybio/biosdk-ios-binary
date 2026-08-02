//
//  BioCheckInView.swift
//  BioSDK
//
//  Reusable BioUI check-in (PROM) widget — renders a program's daily check-in
//  scales (from `spec.sdk.checkins`, a `CheckInConfig`) as numeric selectors and
//  submits the answers via `sdk.submitCheckIn(...)`, where they land as
//  LOINC-coded Observations. Parity with the task-list widget; the config is
//  passed in (not fetched), so there's no load step.
//

import SwiftUI
import BioSDK

// MARK: - BioCheckInView

/// A self-contained daily check-in card.
///
/// Usage (hub-and-spoke, e.g. AnyBio — one per `CheckInConfig`):
/// ```swift
/// if let episodeId = program.episodeId, let checkins = program.sdk?.checkins {
///     ForEach(Array(checkins.enumerated()), id: \.offset) { _, config in
///         BioCheckInView(sdk: sdk, episodeId: episodeId, config: config)
///     }
/// }
/// ```
public struct BioCheckInView: View {
    private let sdk: BioSDKClient
    private let episodeId: String
    private let config: CheckInConfig
    private let title: String?
    private let onSubmit: ((BioCheckInResult) -> Void)?

    /// Selected scale point per question (nil = unanswered).
    @State private var values: [CheckInQuestionType: Double] = [:]
    @State private var phase: Phase = .editing

    private enum Phase: Equatable {
        case editing
        case submitting
        case done
        case failed(String)
    }

    public init(
        sdk: BioSDKClient,
        episodeId: String,
        config: CheckInConfig,
        title: String? = nil,
        onSubmit: ((BioCheckInResult) -> Void)? = nil
    ) {
        self.sdk = sdk
        self.episodeId = episodeId
        self.config = config
        self.title = title
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if phase == .done {
                submittedView
            } else {
                ForEach(config.questionTypes, id: \.self) { scale in
                    scaleRow(scale)
                }
                if case .failed(let message) = phase {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                submitButton
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        // Reset on episode switch (a different program / a new day) so a prior
        // check-in's answers or "submitted" state never linger.
        .task(id: episodeId) {
            values = [:]
            phase = .editing
        }
    }

    // MARK: - Rows

    private func scaleRow(_ scale: CheckInQuestionType) -> some View {
        let p = Self.presentation(for: scale)
        return VStack(alignment: .leading, spacing: 8) {
            Text(p.prompt)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(p.range), id: \.self) { n in
                    let selected = values[scale] == Double(n)
                    Button {
                        values[scale] = Double(n)
                    } label: {
                        Text("\(n)")
                            .font(.callout.weight(selected ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(selected ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundColor(selected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.prompt) \(n)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

            HStack {
                Text(p.lowLabel)
                Spacer(minLength: 8)
                Text(p.highLabel)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var submitButton: some View {
        let ready = allAnswered
        let busy = phase == .submitting
        return Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "Submitting…" : "Submit check-in")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ready ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!ready || busy)
    }

    private var submittedView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
            Text("Check-in submitted. Thank you!")
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private var allAnswered: Bool {
        !config.questionTypes.isEmpty && config.questionTypes.allSatisfy { values[$0] != nil }
    }

    private func submit() {
        let answers: [BioCheckInAnswer] = config.questionTypes.compactMap { scale in
            guard let value = values[scale] else { return nil }
            return BioCheckInAnswer(linkId: scale.rawValue, value: value)
        }
        guard !answers.isEmpty else { return }
        phase = .submitting
        let targetEpisode = episodeId
        Task {
            do {
                let result = try await sdk.submitCheckIn(
                    episodeId: targetEpisode,
                    questionnaireId: config.questionnaireID,
                    context: config.context,
                    answers: answers
                )
                // Drop the result if the spoke switched mid-submit.
                guard episodeId == targetEpisode else { return }
                phase = .done
                onSubmit?(result)
            } catch {
                guard episodeId == targetEpisode else { return }
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                phase = .failed("Couldn't submit: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Per-scale presentation

    /// Prompt, integer range, and pole labels per PROM scale. Ranges mirror the
    /// backend's `biosignals.csv` validation bounds (readiness/confidence/worry/
    /// physical_function 1–10, energy/mood 1–5, pain 0–10). `helpfulness` isn't
    /// seeded server-side yet (the backend skips it), but is rendered so a
    /// program declaring it doesn't show a gap.
    private static func presentation(
        for scale: CheckInQuestionType
    ) -> (prompt: String, range: ClosedRange<Int>, lowLabel: String, highLabel: String) {
        switch scale {
        case .readiness:
            return ("How ready do you feel today?", 1...10, "Not at all", "Completely")
        case .confidence:
            return ("How confident do you feel?", 1...10, "Not at all", "Very")
        case .worry:
            return ("How worried do you feel?", 1...10, "Not at all", "Extremely")
        case .physicalFunction:
            return ("How is your physical function today?", 1...10, "Very limited", "Full")
        case .energy:
            return ("How is your energy today?", 1...5, "Drained", "Energized")
        case .mood:
            return ("How is your mood today?", 1...5, "Very low", "Great")
        case .pain:
            return ("What is your pain level today?", 0...10, "None", "Worst")
        case .helpfulness:
            return ("How helpful was this?", 1...5, "Not helpful", "Very helpful")
        }
    }
}
