//
//  BioSleepSessionView.swift
//  BioSDK
//
//  Bedtime mode view for overnight continuous monitoring
//  - Keeps screen on (dimmed) with red-light theme
//  - Requires device to be plugged in
//  - Displays real-time ECG, PPG, EDA waveforms
//  - Shows clock for bedside display
//

import SwiftUI
import BioSDK
#if canImport(UIKit)
import UIKit
#endif

public struct BioSleepSessionView: View {
    @ObservedObject var live: BioLiveStore
    @Environment(\.dismiss) private var dismiss

    @State private var sessionStartTime = Date()
    @State private var batteryLevel: Float = 1.0
    @State private var isPluggedIn: Bool = false
    @State private var showExitButton: Bool = false
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let batteryTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    public init(live: BioLiveStore) {
        self.live = live
    }

    private var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStartTime)
    }

    private var durationFormatted: String {
        let hours = Int(sessionDuration) / 3600
        let minutes = (Int(sessionDuration) % 3600) / 60
        let seconds = Int(sessionDuration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func updateBatteryStatus() {
        #if canImport(UIKit) && !os(macOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        isPluggedIn = (state == .charging || state == .full)
        #endif
    }

    private func enableAlwaysOn() {
        #if canImport(UIKit) && !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private func disableAlwaysOn() {
        #if canImport(UIKit) && !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    public var body: some View {
        ZStack {
            // Dark red background
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Clock display
                Text(currentTime, style: .time)
                    .font(.system(size: 60, weight: .thin, design: .rounded))
                    .foregroundColor(.red.opacity(0.8))

                // Session duration
                Text("Sleep Session")
                    .font(.headline)
                    .foregroundColor(.red.opacity(0.6))
                Text(durationFormatted)
                    .font(.system(size: 24, weight: .light, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))

                // Battery warning
                if !isPluggedIn {
                    HStack(spacing: 8) {
                        Image(systemName: "battery.25")
                        Text("Not Plugged In - Battery: \(Int(batteryLevel * 100))%")
                            .font(.caption)
                    }
                    .foregroundColor(.red.opacity(0.9))
                    .padding(8)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                }

                Spacer()

                // Dim red-light waveforms
                BioSleepWaveformsView(live: live)

                Spacer()

                // Vitals
                HStack(spacing: 40) {
                    VitalDisplay(label: "HR", value: latestBPM, unit: "bpm")
                    VitalDisplay(label: "SpO₂", value: latestSpO2, unit: "%")
                }
                .padding(.bottom, 20)
            }
            .padding()

            // Tap overlay to show exit button
            if !showExitButton {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            showExitButton = true
                        }
                        // Auto-hide after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                showExitButton = false
                            }
                        }
                    }
            }

            // Exit button (appears on tap)
            if showExitButton {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            disableAlwaysOn()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Exit Sleep Session")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onAppear {
            sessionStartTime = Date()
            updateBatteryStatus()
            enableAlwaysOn()
        }
        .onDisappear {
            disableAlwaysOn()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onReceive(batteryTimer) { _ in
            updateBatteryStatus()
        }
    }

    // Extract latest heart rate
    private var latestBPM: Double {
        let hrSamples = live.samples(for: "heart_rate")
        guard let latestSample = hrSamples.last,
              let bpm = latestSample.scalarValue else {
            return 0
        }
        return bpm
    }

    // Extract latest SpO2
    private var latestSpO2: Double {
        let spo2Samples = live.samples(for: "spo2")
        guard let latestSample = spo2Samples.last,
              let value = latestSample.scalarValue else {
            return 0
        }
        return value
    }
}

// MARK: - Vital Display Component
private struct VitalDisplay: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.red.opacity(0.6))
            Text(value > 0 ? "\(Int(value))" : "--")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundColor(.red.opacity(0.8))
            Text(unit)
                .font(.caption2)
                .foregroundColor(.red.opacity(0.5))
        }
    }
}

// MARK: - Sleep Waveforms View
private struct BioSleepWaveformsView: View {
    @ObservedObject var live: BioLiveStore

    var body: some View {
        VStack(spacing: 16) {
            // ECG
            SleepWaveform(label: "ECG", samples: live.samples(for: "ecg"), maxPoints: 200)

            // PPG
            SleepWaveform(label: "PPG", samples: live.samples(for: "ppg"), maxPoints: 200)

            // EDA
            SleepWaveform(label: "EDA", samples: live.samples(for: "eda"), maxPoints: 100)
        }
    }
}

// MARK: - Sleep Waveform Component (Red-tinted, dim)
private struct SleepWaveform: View {
    let label: String
    let samples: [BioSample]
    let maxPoints: Int

    private var waveformPoints: [CGPoint] {
        let recentSamples = Array(samples.suffix(maxPoints))
        guard !recentSamples.isEmpty else { return [] }

        // Extract values
        let values: [Double] = recentSamples.compactMap { sample in
            if let scalar = sample.scalarValue {
                return scalar
            } else if let waveform = sample.waveform, !waveform.isEmpty {
                return waveform[0]
            }
            return nil
        }

        guard values.count > 1 else { return [] }

        // Normalize to 0...1
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range = maxVal - minVal

        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1)
            let normalized = range > 0 ? (value - minVal) / range : 0.5
            let y = 1.0 - normalized  // Invert Y axis
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.red.opacity(0.5))

            GeometryReader { geometry in
                Path { path in
                    guard !waveformPoints.isEmpty else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height

                    let firstPoint = CGPoint(
                        x: waveformPoints[0].x * width,
                        y: waveformPoints[0].y * height
                    )
                    path.move(to: firstPoint)

                    for point in waveformPoints.dropFirst() {
                        let scaledPoint = CGPoint(
                            x: point.x * width,
                            y: point.y * height
                        )
                        path.addLine(to: scaledPoint)
                    }
                }
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
            .frame(height: 60)
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)
        }
    }
}
