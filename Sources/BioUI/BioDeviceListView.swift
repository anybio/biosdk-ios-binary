import SwiftUI
import Combine
import BioSDK

#if canImport(UIKit)
import UIKit
#endif

// Internal model for each device row.
struct DeviceRow: Identifiable, Equatable { // was fileprivate
    let id: UUID
    var name: String
    var connection: BioConnectionState
    var stream: BioStreamState
    var autoStream: Bool
    var battery: Int? // Battery percentage (0-100)
    // Include flag (pre-session). During active session it is frozen.
    var includeInSession: Bool = false
}

@MainActor
final class BioDeviceListViewModel: ObservableObject {
    @Published var devices: [DeviceRow] = []
    @Published var scanning = false
    @Published var summaryConnections: Int = 0
    // Session tracking
    @Published var sessionActive: Bool = false
    @Published var sessionId: String? = nil
    @Published var sessionStartedAt: Date? = nil
    @Published var sessionModeEnabled: Bool = true
    @Published var sessionDevices: [SessionDevice] = []
    // Snapshot of device ids that belong to the active session (frozen while active)
    private var activeSessionDeviceIds: Set<UUID> = []
    // Buffer monitoring
    @Published var bufferStats: BufferStats? = nil
    @Published var uploadStats: [String: DeviceUploadStats]? = nil
    @Published var allLogFiles: [(url: URL, size: Int, created: Date?)] = []
    // BLE Packet logging tracking
    @Published var blePacketLoggingEnabled: Bool = false
    @Published var blePacketLogURL: URL? = nil

    // NEW: session start orchestration UI state
    @Published var isStartingSession: Bool = false
    @Published var startStatusMessage: String? = nil
    @Published var conflictActiveId: String? = nil
    @Published var conflictStartedAt: Date? = nil
    @Published var showConflictAlert: Bool = false
    @Published var showNonStreamingWarning: Bool = false
    @Published var startError: String? = nil
    private var pendingXUser: String? = nil

    // Provide injected xUser (optional). If nil, start UI will be hidden.
    private let xUserId: String?

    private let sdk: BioSDKClient
    private var cancellables: Set<AnyCancellable> = []
    private var scanStopWorkItem: DispatchWorkItem?

    // Expose live store for UI components
    var liveStore: BioLiveStore { sdk.live }

    init(sdk: BioSDKClient, xUserId: String? = nil) {
        self.sdk = sdk
        self.xUserId = xUserId
        wire()
    }

    // Expose if we can initiate a session (needs user + at least one included device connected/eligible)
    var canStartSession: Bool {
        guard !sessionActive, !isStartingSession, conflictActiveId == nil, let _ = xUserId else { return false }
        return sessionEligibleDevices.contains { $0.includeInSession }
    }

    // Check if any included devices are not streaming
    var hasNonStreamingIncludedDevices: Bool {
        sessionEligibleDevices.contains { $0.includeInSession && $0.stream != .streaming }
    }

    // List of included devices that are not streaming
    var nonStreamingDeviceNames: [String] {
        sessionEligibleDevices
            .filter { $0.includeInSession && $0.stream != .streaming }
            .map { $0.name }
    }

    func requestStartSession() {
        // Check if any included devices are not streaming
        if hasNonStreamingIncludedDevices {
            showNonStreamingWarning = true
        } else {
            startSession()
        }
    }

    func startSession() {
        guard let x = xUserId, !isStartingSession, !sessionActive else { return }
        isStartingSession = true
        startStatusMessage = "Starting session..."
        startError = nil
        pendingXUser = x
        sdk.startBackendSession(for: x) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                print("BioDeviceListViewModel: startStreaming completion callback called with result: \(result)")
                switch result {
                case .success:
                    self.startStatusMessage = nil
                    self.isStartingSession = false // will also get started/resumed event
                case .failure(let disp):
                    print("BioDeviceListViewModel: startStreaming failed with disposition: \(disp)")
                    switch disp {
                    case .conflict(let activeId, let startedAt):
                        print("BioDeviceListViewModel: Conflict in callback - activeId=\(activeId) startedAt=\(String(describing: startedAt))")
                        self.conflictActiveId = activeId
                        self.conflictStartedAt = startedAt
                        self.showConflictAlert = true
                        self.startStatusMessage = nil
                        self.isStartingSession = false
                        print("BioDeviceListViewModel: Callback set showConflictAlert=\(self.showConflictAlert), conflictActiveId=\(String(describing: self.conflictActiveId))")
                    default:
                        break
                    }
                }
            }
        }
    }

    func resumeConflict() {
        sdk.resumeConflictingSession()
        // UI will update on .resumed event
    }

    func endConflictAndStartNew() {
        // Show interim status
        startStatusMessage = "Ending existing & starting new..."
        sdk.endConflictingAndStartNew()
    }

    func cancelConflict() {
        sdk.cancelPendingConflict()
        conflictActiveId = nil
        conflictStartedAt = nil
        showConflictAlert = false
    }

    func clearError() {
        startError = nil
    }

    func checkForActiveSession() {
        startStatusMessage = "Checking for active session..."
        sdk.checkForActiveSession()
    }

    func abortStartAttempts() {
        // User cancels manual starting (will end backoff attempts if any by stopping streaming configuration)
        if isStartingSession && !sessionActive {
            sdk.stopStreaming() // tears down attempt
            isStartingSession = false
            startStatusMessage = nil
            startError = "Cancelled"
        }
    }

    private func wire() {
        // CRITICAL: Cannot access @Published projections ($property) across XCFramework boundaries
        // because Published<T>.Publisher type metadata cannot be resolved across module boundaries.
        // Instead, we poll BioLiveStore values on a timer and copy to local state.

        // Poll every 100ms for responsive UI updates
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncAllDevicesFromLiveStore()
                self.syncSessionStateFromLiveStore()
                self.recalcConnections()
                self.refreshSessionSnapshotIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func upsertDeviceFromLiveStore(deviceId: UUID, name: String) {
        let idStr = deviceId.uuidString

        // Get state from BioLiveStore
        let connection = sdk.live.deviceConnectionStates[idStr] ?? .discovered
        let stream = sdk.live.deviceStreamStates[idStr] ?? .idle
        let battery = sdk.live.deviceBattery[idStr]
        let autoStream = sdk.live.deviceAutoStream[idStr] ?? true

        if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
            var row = devices[idx]
            row.name = name
            row.connection = connection
            row.stream = stream
            row.battery = battery
            row.autoStream = autoStream
            // Preserve includeInSession flag
            row.includeInSession = devices[idx].includeInSession
            devices[idx] = row
        } else {
            let row = DeviceRow(
                id: deviceId,
                name: name,
                connection: connection,
                stream: stream,
                autoStream: autoStream,
                battery: battery,
                includeInSession: true
            )
            devices.append(row)
            devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func syncAllDevicesFromLiveStore() {
        // Sync all devices from BioLiveStore
        for (idStr, name) in sdk.live.deviceNames {
            guard let deviceId = UUID(uuidString: idStr) else { continue }
            upsertDeviceFromLiveStore(deviceId: deviceId, name: name)
        }
    }

    private func syncSessionStateFromLiveStore() {
        // Poll session state from BioLiveStore (cannot use @Published projections across XCFramework)
        let sessionId = sdk.live.currentSessionId
        let sessionDevices = sdk.live.sessionDevices
        let conflictId = sdk.live.conflictingSessionId
        let conflictStartedAt = sdk.live.conflictingSessionStartedAt
        let error = sdk.live.sessionError

        handleSessionStateChange(
            sessionId: sessionId,
            sessionDevices: sessionDevices,
            conflictId: conflictId,
            conflictStartedAt: conflictStartedAt,
            error: error
        )
    }

    private func recalcConnections() { summaryConnections = devices.reduce(0) { $0 + (($1.connection == .ready || $1.connection == .connecting || $1.connection == .discoveringServices) ? 1 : 0) } }

    private func handleSessionStateChange(
        sessionId: String?,
        sessionDevices: [SessionDevice],
        conflictId: String?,
        conflictStartedAt: Date?,
        error: String?
    ) {
        // Handle session started/resumed (sessionId is set)
        if let id = sessionId, self.sessionId != id {
            sessionActive = true
            self.sessionId = id
            sessionStartedAt = Date()
            self.sessionDevices = sessionDevices
            activeSessionDeviceIds = Set(sessionEligibleDevices.map { $0.id })
            conflictActiveId = nil
            showConflictAlert = false
            startError = nil
            startStatusMessage = nil
            isStartingSession = false
        }
        // Handle session ended (sessionId is nil)
        else if sessionId == nil && self.sessionId != nil {
            sessionActive = false
            self.sessionId = nil
            activeSessionDeviceIds = []
            self.sessionDevices = []
        }

        // Handle conflict
        if let activeId = conflictId, !sessionActive {
            print("BioDeviceListViewModel: Conflict detected - activeId=\(activeId) startedAt=\(String(describing: conflictStartedAt))")
            conflictActiveId = activeId
            self.conflictStartedAt = conflictStartedAt
            showConflictAlert = true
            isStartingSession = false
            print("BioDeviceListViewModel: showConflictAlert set to \(showConflictAlert), conflictActiveId=\(String(describing: conflictActiveId))")
        } else if conflictId == nil && conflictActiveId != nil {
            // Conflict cleared
            conflictActiveId = nil
            self.conflictStartedAt = nil
            showConflictAlert = false
        }

        // Handle error
        if let err = error, startError != err {
            startStatusMessage = nil
            startError = err
            isStartingSession = false
        }
    }

    // MARK: - Derived lists
    var discoveredOnly: [DeviceRow] { devices.filter { $0.connection == .discovered } }
    // Devices that are connected/connecting/ready for session (snapshot frozen when active)
    private var sessionEligibleDevices: [DeviceRow] {
        devices.filter { d in
            switch d.connection { case .ready, .connecting, .discoveringServices: return true; default: return false }
        }
    }
    var sessionDevicesDisplay: [DeviceRow] {
        if sessionActive { return devices.filter { activeSessionDeviceIds.contains($0.id) } }
        return sessionEligibleDevices
    }

    private func refreshSessionSnapshotIfNeeded() {
        if !sessionActive { activeSessionDeviceIds = Set(sessionEligibleDevices.map { $0.id }) }
    }

    // MARK: - Intents
    func toggleScan() {
        scanning = !scanning
        if scanning {
            sdk.startScan()
            scheduleAutoStopScan()
        } else {
            sdk.stopScan()
            cancelAutoStop()
        }
    }
    private func scheduleAutoStopScan() {
        cancelAutoStop()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.scanning { self.scanning = false; self.sdk.stopScan() }
        }
        scanStopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }
    private func cancelAutoStop() { scanStopWorkItem?.cancel(); scanStopWorkItem = nil }

    func connect(_ row: DeviceRow) { sdk.connect(BioDevice(id: row.id, name: row.name)) }
    func disconnect(_ row: DeviceRow) { sdk.disconnect(BioDevice(id: row.id, name: row.name)) }
    func disconnectAll() { sdk.disconnectAll(); summaryConnections = 0 }
    func toggleAutoStream(_ row: DeviceRow) {
        sdk.setAutoStream(deviceId: row.id, enabled: !row.autoStream)
        if let idx = devices.firstIndex(where: { $0.id == row.id }) { devices[idx].autoStream.toggle() }
    }
    func toggleStreaming(_ row: DeviceRow) {
        switch row.stream {
        case .streaming, .starting: sdk.stopStreaming(deviceId: row.id)
        case .idle, .stalled, .stopping, .unsupported: sdk.startStreaming(deviceId: row.id)
        }
    }
    func toggleIncludeInSession(_ row: DeviceRow) {
        guard !sessionActive, let idx = devices.firstIndex(where: { $0.id == row.id }) else { return }
        devices[idx].includeInSession.toggle()
    }
    func endSession() { sdk.endActiveSession() }
    func toggleSessionMode() {
        sessionModeEnabled.toggle()
        sdk.setSessionMode(enabled: sessionModeEnabled)
    }

    func getDeviceOperations(for deviceId: UUID) -> [DeviceOperationUI] {
        return sdk.getDeviceOperations(deviceId: deviceId)
    }

    func executeOperation(deviceId: UUID, operationName: String) {
        Task {
            do {
                try await sdk.executeOperation(deviceId: deviceId, operationName: operationName)
                print("Operation '\(operationName)' executed successfully")
            } catch {
                print("Failed to execute operation '\(operationName)': \(error)")
            }
        }
    }

    func resetDevices() {
        // Stop all streaming and disconnect all devices for fresh reconnection
        sdk.stopStreaming()
        sdk.disconnectAll()
        // Clear UI state
        devices.removeAll()
        sessionActive = false
        sessionId = nil
        sessionStartedAt = nil
        sessionDevices = []
        activeSessionDeviceIds = []
        conflictActiveId = nil
        conflictStartedAt = nil
        showConflictAlert = false
        showNonStreamingWarning = false
        startError = nil
        startStatusMessage = nil
        isStartingSession = false
        pendingXUser = nil
        summaryConnections = 0
        // Optionally restart scan for fresh discovery
        if !scanning {
            toggleScan()
        }
    }

    func refreshBufferStats() {
        Task {
            do {
                self.bufferStats = try await sdk.getBufferStats()
                self.uploadStats = await sdk.getUploadStats()
                print("📦 Refreshed buffer stats: pending=\(self.bufferStats?.totalPending ?? 0), uploaded=\(self.bufferStats?.totalPackets ?? 0)")
            } catch {
                print("❌ Failed to refresh buffer stats: \(error)")
            }
        }
    }

    func resetFailedPackets() {
        Task {
            do {
                let count = try await sdk.resetFailedPackets(for: nil)
                print("📦 Reset \(count) failed packets to pending - batch upload triggered")
                // Refresh stats to show updated counts
                try await Task.sleep(nanoseconds: 1_000_000_000)  // Wait 1 second for upload to start
                refreshBufferStats()
            } catch {
                print("❌ Failed to reset failed packets: \(error)")
            }
        }
    }

    func clearBuffer() {
        Task {
            do {
                try await sdk.clearBuffer()
                print("📦 Cleared SQLite buffer database")
                // Buffer will be recreated on next session start
                // Reset stats to zero
                bufferStats = nil
            } catch {
                print("❌ Failed to clear buffer: \(error)")
            }
        }
    }

    func syncBLEPacketLoggingState() {
        // Sync BLE packet logging state
        blePacketLoggingEnabled = sdk.isBLEPacketLoggingEnabled
        if blePacketLoggingEnabled {
            blePacketLogURL = sdk.getBLEPacketLogURL()
            print("📡 Synced BLE packet logging state: enabled=true, url=\(blePacketLogURL?.lastPathComponent ?? "nil")")
        } else {
            print("📡 Synced BLE packet logging state: enabled=false")
        }
    }

    func toggleBLEPacketLogging() {
        if blePacketLoggingEnabled {
            // Stop BLE packet logging
            if let url = sdk.stopBLEPacketLogging() {
                blePacketLogURL = url
                print("📡 BLE packet logging stopped. Log saved to: \(url.path)")
            }
            blePacketLoggingEnabled = false
        } else {
            // Start BLE packet logging
            if let url = sdk.startBLEPacketLogging() {
                blePacketLogURL = url
                blePacketLoggingEnabled = true
                print("📡 BLE packet logging started. Logging to: \(url.path)")
            } else {
                print("📡 Failed to start BLE packet logging")
            }
        }
    }

    func listAllLogFiles() {
        // Debug: list all log files to see if any were created
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [])
            // Include both ingest frames and BLE packet logs
            let logFiles = files.filter {
                $0.lastPathComponent.hasPrefix("ingest_frames_") ||
                $0.lastPathComponent.hasPrefix("ble_packets_")
            }

            // Update UI state
            allLogFiles = logFiles.compactMap { file in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let size = attrs[.size] as? Int else {
                    return nil
                }
                let created = attrs[.creationDate] as? Date
                return (url: file, size: size, created: created)
            }.sorted { ($0.created ?? Date.distantPast) > ($1.created ?? Date.distantPast) }

            print("📁 Found \(allLogFiles.count) log files in Documents:")
            for file in allLogFiles {
                print("  - \(file.url.lastPathComponent): \(file.size) bytes, created: \(file.created?.formatted() ?? "unknown")")
            }
        } catch {
            print("📁 Error listing log files: \(error)")
            allLogFiles = []
        }
    }

}

public struct BioDeviceListView: View {
    @StateObject private var vm: BioDeviceListViewModel

    // Explicit single-parameter initializer (emits symbol: init(sdk:))
    public init(sdk: BioSDKClient) {
        _vm = StateObject(wrappedValue: BioDeviceListViewModel(sdk: sdk, xUserId: nil))
    }
    // Two-parameter initializer (no default now to avoid overload ambiguity)
    public init(sdk: BioSDKClient, xUserId: String?) {
        _vm = StateObject(wrappedValue: BioDeviceListViewModel(sdk: sdk, xUserId: xUserId))
    }

    public var body: some View {
        List {
            // Scanning control section (requirement #6)
            Section("Scan") {
                HStack {
                    Button(vm.scanning ? "Stop Scan" : "Start Scan", action: vm.toggleScan)
                    Spacer()
                    if vm.scanning { Text("Auto-stops in 60s").font(.caption).foregroundColor(.secondary) }
                }
            }
            // Discovered devices (not connected)
            Section(header: discoveredHeader) {
                if vm.discoveredOnly.isEmpty {
                    Text(vm.scanning ? "Scanning…" : "No newly discovered devices.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.discoveredOnly) { row in
                        DeviceRowView(row: row,
                                      connect: { vm.connect(row) },
                                      disconnect: { vm.disconnect(row) },
                                      toggleStream: { vm.toggleStreaming(row) },
                                      toggleAutoStream: { vm.toggleAutoStream(row) })
                    }
                }
            }
            // Session devices section
            Section("Session Devices") {
                if vm.sessionDevicesDisplay.isEmpty {
                    Text("No session-capable devices.").foregroundColor(.secondary)
                } else {
                    ForEach(vm.sessionDevicesDisplay) { row in
                        SessionRowView(row: row,
                                       sessionActive: vm.sessionActive,
                                       toggleInclude: { vm.toggleIncludeInSession(row) },
                                       connect: { vm.connect(row) },
                                       disconnect: { vm.disconnect(row) },
                                       toggleStream: { vm.toggleStreaming(row) },
                                       getOperations: { vm.getDeviceOperations(for: row.id) },
                                       executeOperation: { opName in vm.executeOperation(deviceId: row.id, operationName: opName) })
                    }
                }
            }
            // Session status section
            Section("Session Status") {
                Toggle("Session Mode", isOn: $vm.sessionModeEnabled)
                
                if vm.sessionModeEnabled {
                    if vm.sessionActive, let started = vm.sessionStartedAt {
                        HStack {
                            Text("LIVE")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            Spacer()
                            Text("Started: \(started.formatted(date: .abbreviated, time: .standard))")
                                .font(.footnote)
                        }
                        
                        if !vm.sessionDevices.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Session Devices:").font(.caption).foregroundColor(.secondary)
                                ForEach(vm.sessionDevices, id: \.device_id) { device in
                                    HStack {
                                        Text(device.device_id)
                                            .font(.caption)
                                        if let make = device.make, let model = device.model {
                                            Text("(\(make) \(model))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text(vm.startStatusMessage ?? (vm.conflictActiveId != nil ? "Session conflict" : "No active session"))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Session mode disabled")
                        .foregroundColor(.secondary)
                }
            }
            
            if vm.sessionModeEnabled {
                Section("Session Control") {
                    if vm.sessionActive {
                        Button("End Session", role: .destructive) { vm.endSession() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            // Check Session button - always visible when no active session
                            Button("Check Session") {
                                vm.checkForActiveSession()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                            if vm.canStartSession {
                                if vm.isStartingSession {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text(vm.startStatusMessage ?? "Starting session...")
                                        Spacer()
                                        Button("Cancel") { vm.abortStartAttempts() }
                                            .font(.caption)
                                    }
                                } else {
                                    Button("Start Session") { vm.requestStartSession() }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                            if let err = vm.startError {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(err).font(.caption).foregroundColor(.red)
                                    Button("Retry") {
                                        vm.clearError()
                                        vm.requestStartSession()
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            // BLE Packet Logging section (raw BLE packets)
            Section(header: Text("BLE Packet Logging (Raw)")) {
                Toggle("Log All BLE Packets", isOn: Binding(
                    get: { vm.blePacketLoggingEnabled },
                    set: { _ in vm.toggleBLEPacketLogging() }
                ))

                if vm.blePacketLoggingEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("📡 Logging every BLE packet received (independent of ingest)")
                            .font(.caption)
                            .foregroundColor(.green)

                        if let url = vm.blePacketLogURL {
                            Text("Current: \(url.lastPathComponent)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Buffer Monitoring section
            Section(header: Text("Upload Buffer (Data Integrity)")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("📦 All packets buffered locally - zero data loss guaranteed")
                        .font(.caption)
                        .foregroundColor(.green)

                    if let bufferStats = vm.bufferStats {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pending:")
                                Spacer()
                                Text("\(bufferStats.totalPending)")
                                    .foregroundColor(bufferStats.totalPending > 1000 ? .orange : .secondary)
                            }
                            .font(.caption)

                            HStack {
                                Text("Uploaded:")
                                Spacer()
                                Text("\(bufferStats.totalPackets - bufferStats.totalPending)")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)

                            if bufferStats.totalFailed > 0 {
                                HStack {
                                    Text("Failed (retrying):")
                                    Spacer()
                                    Text("\(bufferStats.totalFailed)")
                                        .foregroundColor(.orange)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let uploadStats = vm.uploadStats, !uploadStats.isEmpty {
                        Divider()

                        // Calculate aggregate success rate across all devices
                        let totalSuccess = uploadStats.values.reduce(0) { $0 + $1.successCount }
                        let totalAttempts = uploadStats.values.reduce(0) { $0 + $1.totalAttempts }
                        let successRate = totalAttempts > 0 ? Double(totalSuccess) / Double(totalAttempts) : 0.0

                        HStack {
                            Text("Upload Success Rate:")
                            Spacer()
                            Text(String(format: "%.1f%%", successRate * 100))
                                .foregroundColor(successRate > 0.9 ? .green : (successRate > 0.7 ? .orange : .red))
                        }
                        .font(.caption)

                        HStack {
                            Text("Devices:")
                            Spacer()
                            Text("\(uploadStats.count) uploading")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }

                    HStack {
                        Button {
                            vm.refreshBufferStats()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button {
                            vm.resetFailedPackets()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Retry Failed")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .font(.caption)

                        Button {
                            vm.clearBuffer()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Buffer")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .font(.caption)
                    }
                }
            }

            // Sleep Session section (overnight monitoring)
            Section(header: Text("Sleep Session (Overnight Monitoring)")) {
                NavigationLink(destination: BioSleepSessionView(live: vm.liveStore)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                                .foregroundColor(.red.opacity(0.7))
                            Text("Start Sleep Session")
                                .font(.headline)
                        }
                        Text("Keep screen on with dim red-light charts for overnight monitoring. Requires device to be plugged in.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // All log files section
            if !vm.allLogFiles.isEmpty {
                Section(header: HStack {
                    Text("Log Files (\(vm.allLogFiles.count))")
                    Spacer()
                    Text("Total: \(formatBytes(vm.allLogFiles.reduce(0) { $0 + $1.size }))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }) {
                    ForEach(vm.allLogFiles, id: \.url) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.url.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text(formatBytes(file.size))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if let created = file.created {
                                            Text(created, style: .relative)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                #if os(iOS)
                                Button {
                                    #if canImport(UIKit)
                                    let activityVC = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = scene.windows.first,
                                       let rootVC = window.rootViewController {
                                        rootVC.present(activityVC, animated: true)
                                    }
                                    #endif
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                #endif
                            }
                        }
                    }
                }
            }

            // Status summary at bottom
            Section("Status") {
                statusRow(title: "Connections", value: "\(vm.summaryConnections)")
                statusRow(title: "Scanning", value: vm.scanning ? "Yes" : "No")

                Button(role: .destructive) {
                    vm.resetDevices()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Devices")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .navigationTitle("Devices")
        .onAppear {
            if !vm.scanning { vm.toggleScan() }
            // Sync BLE packet logging state on appear (important after app resume)
            vm.syncBLEPacketLoggingState()
            // Refresh buffer stats
            vm.refreshBufferStats()
            // Debug: list all log files
            vm.listAllLogFiles()
        }
        .alert("Devices Not Streaming", isPresented: $vm.showNonStreamingWarning, actions: {
            Button("Start Anyway", role: .destructive) { vm.startSession() }
            Button("Cancel", role: .cancel) { }
        }, message: {
            let deviceList = vm.nonStreamingDeviceNames.joined(separator: ", ")
            let count = vm.nonStreamingDeviceNames.count
            if count == 1 {
                Text("The following device is included in the session but not streaming: \(deviceList)\n\nStart streaming first to capture data, or proceed without data from this device.")
            } else {
                Text("The following \(count) devices are included in the session but not streaming: \(deviceList)\n\nStart streaming first to capture data, or proceed without data from these devices.")
            }
        })
        .alert("Existing Session Active", isPresented: $vm.showConflictAlert, actions: {
            Button("Resume") { vm.resumeConflict() }
            Button("End & Start New", role: .destructive) { vm.endConflictAndStartNew() }
            Button("Cancel", role: .cancel) { vm.cancelConflict() }
        }, message: {
            if let started = vm.conflictStartedAt {
                Text("A previous session is still open (started at \(started.formatted(date: .abbreviated, time: .standard))). Resume it or end it to start fresh.")
            } else {
                Text("A previous session is still open. Resume it or end it to start fresh.")
            }
        })
    }

    @ViewBuilder private func statusRow(title: String, value: String) -> some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            LabeledContent(title, value: value)
        } else {
            HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) }
        }
    }

    private var discoveredHeader: some View {
        HStack { Text("Discovered Devices"); Spacer(); if vm.scanning { ProgressView().controlSize(.small) } }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

fileprivate struct DeviceRowView: View {
    let row: DeviceRow
    let connect: ()->Void
    let disconnect: ()->Void
    let toggleStream: ()->Void
    let toggleAutoStream: ()->Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                    Text(row.id.uuidString).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if row.connection == .disconnected || row.connection == .failed || row.connection == .discovered {
                    Button("Connect", action: connect)
                } else {
                    Button("Disconnect", action: disconnect).tint(.red)
                }
            }
            HStack(spacing: 12) {
                badge(text: connLabel(row.connection), color: connColor(row.connection))
                badge(text: streamLabel(row.stream), color: streamColor(row.stream))
                if let battery = row.battery {
                    batteryBadge(level: battery)
                }
                Toggle("Auto Stream", isOn: Binding(
                    get: { row.autoStream },
                    set: { _ in toggleAutoStream() })
                ).toggleStyle(.switch).labelsHidden()
                Button(streamActionTitle, action: toggleStream)
                    .disabled(!canManualStream)
            }
        }
    }

    private func connLabel(_ c: BioConnectionState) -> String {
        switch c {
        case .discovered: return "discovered"
        case .connecting: return "connecting"
        case .discoveringServices: return "services"
        case .ready: return "ready"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        }
    }
    private func streamLabel(_ s: BioStreamState) -> String {
        switch s {
        case .idle: return "idle"
        case .starting: return "starting"
        case .streaming: return "streaming"
        case .stopping: return "stopping"
        case .stalled: return "stalled"
        case .unsupported: return "no-stream"
        }
    }
    private func connColor(_ c: BioConnectionState) -> Color {
        switch c {
        case .ready: return .green
        case .connecting, .discoveringServices: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        case .discovered: return .blue
        }
    }
    private func streamColor(_ s: BioStreamState) -> Color {
        switch s {
        case .streaming: return .green
        case .starting: return .orange
        case .stalled: return .yellow
        case .stopping: return .orange
        case .idle: return .gray
        case .unsupported: return .gray.opacity(0.6)
        }
    }
    private func badge(text: String, color: Color) -> some View {
        Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.2)).clipShape(Capsule())
    }

    private func batteryBadge(level: Int) -> some View {
        let color: Color
        let icon: String
        if level > 50 {
            color = .green
            icon = "battery.100"
        } else if level > 20 {
            color = .orange
            icon = "battery.50"
        } else {
            color = .red
            icon = "battery.25"
        }

        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(level)%")
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color.darker())
        .clipShape(Capsule())
    }

    private var streamActionTitle: String { (row.stream == .streaming || row.stream == .starting) ? "Stop" : "Start" }
    private var canManualStream: Bool { row.connection == .ready && row.stream != .starting && row.stream != .stopping && row.stream != .unsupported }
}

// Color extension for darker shade
extension Color {
    func darker(by percentage: Double = 0.3) -> Color {
        return self.opacity(1.0)
    }
}

// Session row view (similar to device row but with include toggle). Disabled toggle when session active.
fileprivate struct SessionRowView: View {
    let row: DeviceRow
    let sessionActive: Bool
    let toggleInclude: ()->Void
    let connect: ()->Void
    let disconnect: ()->Void
    let toggleStream: ()->Void
    let getOperations: () -> [DeviceOperationUI]
    let executeOperation: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.name)
                    .font(.subheadline)
                Spacer()
                if row.connection == .disconnected || row.connection == .failed || row.connection == .discovered {
                    Button("Connect", action: connect)
                } else {
                    Button("Disconnect", action: disconnect).tint(.red)
                }
            }
            
            HStack(spacing: 8) {
                badge(text: connLabel(row.connection), color: connColor(row.connection))
                badge(text: streamLabel(row.stream), color: streamColor(row.stream))
                if let battery = row.battery {
                    batteryBadge(level: battery)
                }
                if row.includeInSession {
                    badge(text: "In Session", color: .blue)
                }
            }

            if row.connection == .ready {
                HStack {
                    if row.includeInSession {
                        Button("Remove", action: toggleInclude)
                            .tint(.orange)
                    } else {
                        Button("Add to Session", action: toggleInclude)
                    }

                    Spacer()

                    Button(streamActionTitle, action: toggleStream)
                }
                .disabled(sessionActive || !canManualStream)

                // Device Operations Section
                let operations = getOperations()
                if !operations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Operations")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ForEach(operations, id: \.name) { operation in
                            if shouldShowOperation(operation) {
                                Button {
                                    executeOperation(operation.name)
                                } label: {
                                    HStack {
                                        if let icon = operation.icon {
                                            Image(systemName: icon)
                                        }
                                        Text(operation.label ?? operation.name)
                                    }
                                }
                                .tint(buttonColor(for: operation.buttonVariant))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func shouldShowOperation(_ operation: DeviceOperationUI) -> Bool {
        // Filter operations based on showWhen conditions
        guard let showWhen = operation.showWhen else { return true }

        // Check streaming state condition
        if let streamingCondition = showWhen["streaming"] {
            switch streamingCondition {
            case .bool(let shouldBeStreaming):
                let isStreaming = row.stream == .streaming
                if shouldBeStreaming != isStreaming {
                    return false
                }
            default:
                break
            }
        }

        return true
    }

    private func buttonColor(for variant: String?) -> Color {
        guard let variant = variant else { return .blue }
        switch variant {
        case "primary": return .blue
        case "secondary": return .gray
        case "danger": return .red
        case "success": return .green
        case "warning": return .orange
        default: return .blue
        }
    }
    
    private func connLabel(_ c: BioConnectionState) -> String {
        switch c {
        case .discovered: return "discovered"
        case .connecting: return "connecting"
        case .discoveringServices: return "services"
        case .ready: return "ready"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        }
    }
    
    private func streamLabel(_ s: BioStreamState) -> String {
        switch s {
        case .idle: return "idle"
        case .starting: return "starting"
        case .streaming: return "streaming"
        case .stopping: return "stopping"
        case .stalled: return "stalled"
        case .unsupported: return "no-stream"
        }
    }

    private func connColor(_ c: BioConnectionState) -> Color {
        switch c {
        case .ready: return .green
        case .connecting, .discoveringServices: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        case .discovered: return .blue
        }
    }
    
    private func streamColor(_ s: BioStreamState) -> Color {
        switch s {
        case .streaming: return .green
        case .starting: return .orange
        case .stalled: return .yellow
        case .stopping: return .orange
        case .idle: return .gray
        case .unsupported: return .gray.opacity(0.6)
        }
    }
    
    private func badge(text: String, color: Color) -> some View { Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.2)).clipShape(Capsule()) }

    private func batteryBadge(level: Int) -> some View {
        let color: Color
        let icon: String
        if level > 50 {
            color = .green
            icon = "battery.100"
        } else if level > 20 {
            color = .orange
            icon = "battery.50"
        } else {
            color = .red
            icon = "battery.25"
        }

        return HStack(spacing: 2) {
            Image(systemName: icon).font(.caption2)
            Text("\(level)%").font(.caption2)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color.darker())
        .clipShape(Capsule())
    }

    private var streamActionTitle: String { (row.stream == .streaming || row.stream == .starting) ? "Stop Streaming" : "Start Streaming" }
    
    private var canManualStream: Bool { row.connection == .ready && row.stream != .starting && row.stream != .stopping && row.stream != .unsupported }
}
