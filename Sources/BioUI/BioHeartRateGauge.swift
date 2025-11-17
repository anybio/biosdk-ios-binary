//
//  BioHeartRateGauge.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/12/25.
//


import SwiftUI
import BioSDK

public struct BioHeartRateGauge: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    // Extract latest heart rate from dynamic storage
    private var latestBPM: Double {
        // Get all heart_rate samples and find the most recent
        let hrSamples = live.samples(for: "heart_rate")
        guard let latestSample = hrSamples.last,
              let bpm = latestSample.scalarValue else {
            return 0
        }
        return bpm
    }

    public var body: some View {
        let bpm = latestBPM
        // Clamp to valid range to avoid Gauge warnings
        let clampedBPM = max(30, min(200, bpm))

        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").font(.headline)
            if #available(macOS 13.0, iOS 16.0, *) {
                Gauge(value: clampedBPM, in: 30...200) {
                    Text("\(Int(bpm)) bpm")
                } currentValueLabel: {
                    Text("\(Int(bpm))")
                } minimumValueLabel: {
                    Text("30")
                } maximumValueLabel: {
                    Text("200")
                }
                .gaugeStyle(.accessoryLinearCapacity)
            } else {
                HStack(spacing: 12) {
                    Text("\(Int(bpm)) bpm")
                    ProgressView(value: Double(clampedBPM), total: 200)
                        .frame(maxWidth: 120)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: bpm) { newBPM in
            print("BioHeartRateGauge: current BPM = \(newBPM)")
        }
    }
}
