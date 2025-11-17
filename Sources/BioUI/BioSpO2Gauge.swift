//
//  BioSpO2Gauge.swift
//  BioSDK
//
//  Numeric display for SpO2 (blood oxygen saturation)
//

import SwiftUI
import BioSDK

public struct BioSpO2Gauge: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    // Extract latest SpO2 from dynamic storage
    private var latestSpO2: Double {
        // Get all spo2 samples and find the most recent
        let spo2Samples = live.samples(for: "spo2")
        guard let latestSample = spo2Samples.last,
              let value = latestSample.scalarValue else {
            return 0
        }
        return value
    }

    // Color coding based on clinical thresholds
    private func colorForSpO2(_ value: Double) -> Color {
        if value < 90 {
            return .red  // Critical: severe hypoxemia
        } else if value < 95 {
            return .orange  // Warning: mild hypoxemia
        } else {
            return .green  // Normal
        }
    }

    public var body: some View {
        let spo2 = latestSpO2
        // Clamp to valid range to avoid Gauge warnings
        let clampedSpO2 = max(70, min(100, spo2))

        VStack(alignment: .leading, spacing: 8) {
            Text("SpO₂").font(.headline)
            if #available(macOS 13.0, iOS 16.0, *) {
                Gauge(value: clampedSpO2, in: 70...100) {
                    Text("\(Int(spo2))%")
                } currentValueLabel: {
                    Text("\(Int(spo2))")
                        .foregroundColor(colorForSpO2(spo2))
                } minimumValueLabel: {
                    Text("70")
                } maximumValueLabel: {
                    Text("100")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(colorForSpO2(spo2))
            } else {
                HStack(spacing: 12) {
                    Text("\(Int(spo2))%")
                        .foregroundColor(colorForSpO2(spo2))
                    ProgressView(value: Double(clampedSpO2), total: 100)
                        .frame(maxWidth: 120)
                        .tint(colorForSpO2(spo2))
                }
            }

            // Clinical status indicator
            if spo2 > 0 {
                Text(statusText(for: spo2))
                    .font(.caption)
                    .foregroundColor(colorForSpO2(spo2))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: spo2) { newValue in
            print("BioSpO2Gauge: current SpO₂ = \(newValue)%")
        }
    }

    private func statusText(for value: Double) -> String {
        if value < 90 {
            return "Critical"
        } else if value < 95 {
            return "Low"
        } else {
            return "Normal"
        }
    }
}
