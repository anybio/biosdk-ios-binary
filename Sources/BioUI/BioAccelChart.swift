//
//  BioAccelChart.swift
//  BioUI
//
//  3-axis accelerometer chart (X, Y, Z overlaid)
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif
import BioSDK


public struct BioAccelChart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    // MARK: - Internal point model
    private struct AccelPoint: Identifiable {
        let axis: String
        let index: Int
        let value: Double
        var id: String { axis + "#" + String(index) }
    }

    private let cap = 500 // ~5s @ 100 Hz

    // MARK: - Data Extraction

    private func extractAxis(_ signalName: String) -> [Double] {
        let samples = live.samples(for: signalName)
        var values: [Double] = []
        for sample in samples {
            if let waveform = sample.waveform {
                values.append(contentsOf: waveform)
            } else if let scalar = sample.scalarValue {
                values.append(scalar)
            }
        }
        if values.count > cap {
            return Array(values.suffix(cap))
        }
        return values
    }

    private var hasData: Bool {
        let signals = live.availableSignals
        return signals.contains("accel_x") || signals.contains("accel_y") || signals.contains("accel_z")
    }

    private func buildPoints() -> [AccelPoint] {
        let xVals = extractAxis("accel_x")
        let yVals = extractAxis("accel_y")
        let zVals = extractAxis("accel_z")

        var points: [AccelPoint] = []
        points.reserveCapacity(xVals.count + yVals.count + zVals.count)

        for (i, v) in xVals.enumerated() {
            points.append(AccelPoint(axis: "X", index: i, value: v))
        }
        for (i, v) in yVals.enumerated() {
            points.append(AccelPoint(axis: "Y", index: i, value: v))
        }
        for (i, v) in zVals.enumerated() {
            points.append(AccelPoint(axis: "Z", index: i, value: v))
        }
        return points
    }

    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accelerometer (g)").font(.headline)
            #if canImport(Charts)
            if #available(macOS 13.0, iOS 16.0, *) {
                let points = buildPoints()
                if points.isEmpty {
                    noDataView
                } else {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Index", p.index),
                            y: .value("g", p.value)
                        )
                        .foregroundStyle(by: .value("Axis", p.axis))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartForegroundStyleScale([
                        "X": Color.red,
                        "Y": Color.green,
                        "Z": Color.blue
                    ])
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartLegend(.visible)
                    .frame(height: 160)
                }
            } else {
                fallbackSummary
            }
            #else
            fallbackSummary
            #endif
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var noDataView: some View {
        Text("No data")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    @ViewBuilder private var fallbackSummary: some View {
        let x = extractAxis("accel_x").last
        let y = extractAxis("accel_y").last
        let z = extractAxis("accel_z").last
        if let x = x, let y = y, let z = z {
            Text(String(format: "X: %.2f  Y: %.2f  Z: %.2f g", x, y, z))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            noDataView
        }
    }
}
