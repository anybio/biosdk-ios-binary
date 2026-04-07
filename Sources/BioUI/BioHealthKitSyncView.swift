//
//  BioHealthKitSyncView.swift
//  BioSDK
//
//  Reusable BioUI view for Apple Health integration.
//  Provides authorization, manual sync, and background delivery controls.
//  Observes sdk.healthKitSyncStatus for live sync/upload state.
//

import SwiftUI
import BioSDK
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - BioHealthKitSyncView

/// A self-contained view for managing Apple Health integration.
/// Handles authorization, manual sync, and optional background delivery.
///
/// Usage:
/// ```swift
/// BioHealthKitSyncView(sdk: bioSDKClient)
/// ```
public struct BioHealthKitSyncView: View {
    private let sdk: BioSDKClient

    #if canImport(HealthKit)
    @ObservedObject private var status: HealthKitSyncStatus
    #endif

    @State private var isAuthorizing = false

    public init(sdk: BioSDKClient) {
        self.sdk = sdk
        #if canImport(HealthKit)
        self._status = ObservedObject(wrappedValue: sdk.healthKitSyncStatus)
        #endif
    }

    public var body: some View {
        #if canImport(HealthKit)
        VStack(spacing: 0) {
            authorizationRow

            if status.isAuthorized {
                Divider().padding(.leading, 52)
                syncRow
                Divider().padding(.leading, 52)
                backgroundSyncRow

                if status.pendingCount > 0 || status.uploadedCount > 0 {
                    Divider().padding(.leading, 52)
                    bufferStatusRow
                }
            }

            if let lastSync = status.lastSyncDate {
                Divider().padding(.leading, 52)
                lastSyncRow(date: lastSync, queried: status.lastSyncQueried, buffered: status.lastSyncBuffered)
            }

            if let error = status.lastError {
                Divider().padding(.leading, 52)
                errorRow(error)
            }
        }
        #else
        Text("HealthKit is not available on this platform")
            .font(.caption)
            .foregroundColor(.secondary)
        #endif
    }

    // MARK: - Rows

    #if canImport(HealthKit)
    private var authorizationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundColor(.red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health")
                    .font(.headline)
                if status.isAuthorized {
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Sync health data to your care team")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isAuthorizing {
                ProgressView()
            } else if !status.isAuthorized {
                Button("Enable") { authorize() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var syncRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Now")
                    .font(.subheadline)
                Text("Upload recent health data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if status.isSyncing {
                ProgressView()
            } else {
                Button("Sync") { syncNow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var backgroundSyncRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                    .font(.subheadline)
                Text("Automatically sync when new data arrives")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $status.backgroundSyncEnabled)
                .labelsHidden()
                .onChange(of: status.backgroundSyncEnabled) { enabled in
                    if enabled {
                        sdk.enableHealthKitBackgroundSync()
                    } else {
                        sdk.disableHealthKitBackgroundSync()
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bufferStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isUploading ? "arrow.up.circle" : "tray.full")
                .font(.title3)
                .foregroundColor(status.isUploading ? .blue : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                if status.pendingCount > 0 {
                    Text("\(status.pendingCount) pending upload")
                        .font(.caption)
                }
                if status.uploadedCount > 0 {
                    Text("\(status.uploadedCount) uploaded")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                if status.failedCount > 0 {
                    Text("\(status.failedCount) failed (will retry)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            if status.isUploading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func lastSyncRow(date: Date, queried: Int, buffered: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(queried) sample\(queried == 1 ? "" : "s") queried, \(buffered) buffered")
                    .font(.caption)
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.title3)
                .foregroundColor(.red)
                .frame(width: 32)

            Text(message)
                .font(.caption)
                .foregroundColor(.red)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func authorize() {
        isAuthorizing = true
        Task { @MainActor in
            do {
                try await sdk.enableHealthKit()
            } catch {
                // Status object handles error display
            }
            isAuthorizing = false
        }
    }

    private func syncNow() {
        Task { @MainActor in
            _ = try? await sdk.syncHealthKit()
        }
    }
    #endif
}
