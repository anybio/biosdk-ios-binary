//
//  BioSpO2Chart.swift
//  BioSDK
//
//  SpO2 (Blood Oxygen Saturation) waveform chart over time
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif
import BioSDK

public struct BioSpO2Chart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    // MARK: - Internal point model
    private struct SpO2LinePoint: Identifiable {
        let deviceId: String
        let label: String
        let timestamp: Date
        let spo2: Double
        let index: Int
        var id: String { deviceId + "#" + String(index) + "#" + String(Int(timestamp.timeIntervalSince1970 * 1000)) }
    }

    // MARK: - Dynamic Data Extraction

    /// Extract SpO2 data by device from dynamic storage
    private func extractSpO2ByDevice() -> [String: [(timestamp: TimeInterval, spo2: Double)]] {
        var result: [String: [(TimeInterval, Double)]] = [:]

        for deviceId in live.availableDevices {
            let spo2Samples = live.samples(for: "spo2", deviceId: deviceId)
            let points = spo2Samples.compactMap { sample -> (TimeInterval, Double)? in
                guard let value = sample.scalarValue else { return nil }
                return (sample.timestamp, value)
            }
            if !points.isEmpty {
                result[deviceId] = points
            }
        }

        return result
    }

    /// Get legend labels (device IDs mapped to friendly names)
    private func getLegendLabels() -> (keys: [String], labelMap: [String: String]) {
        let spo2ByDevice = extractSpO2ByDevice()
        var labelMap: [String: String] = [:]

        for deviceId in spo2ByDevice.keys {
            labelMap[deviceId] = live.deviceNames[deviceId] ?? deviceId
        }

        return (keys: Array(spo2ByDevice.keys).sorted(), labelMap: labelMap)
    }

    /// Get the active device (most recent SpO2 data)
    private func getActiveDeviceId() -> String? {
        var latestDeviceId: String?
        var latestTimestamp: TimeInterval = 0

        for deviceId in live.availableDevices {
            let spo2Samples = live.samples(for: "spo2", deviceId: deviceId)
            if let lastSample = spo2Samples.last, lastSample.timestamp > latestTimestamp {
                latestTimestamp = lastSample.timestamp
                latestDeviceId = deviceId
            }
        }

        return latestDeviceId
    }

    // MARK: - Helpers
    private func flattenPoints(keys: [String], labelMap: [String:String]) -> [SpO2LinePoint] {
        let spo2ByDevice = extractSpO2ByDevice()
        var total = 0
        for k in keys { total += spo2ByDevice[k]?.count ?? 0 }
        var out: [SpO2LinePoint] = []
        if total > 0 { out.reserveCapacity(total) }

        for deviceId in keys {
            guard let series = spo2ByDevice[deviceId], let label = labelMap[deviceId] else { continue }
            var i = 0
            for pt in series {
                let tsDate = Date(timeIntervalSince1970: pt.timestamp)
                out.append(SpO2LinePoint(deviceId: deviceId,
                                        label: label,
                                        timestamp: tsDate,
                                        spo2: pt.spo2,
                                        index: i))
                i += 1
            }
        }
        return out
    }

    private func computeTimeDomain(keys: [String]) -> ClosedRange<Date>? {
        let spo2ByDevice = extractSpO2ByDevice()
        var minTs: TimeInterval = .greatestFiniteMagnitude
        var maxTs: TimeInterval = 0

        for id in keys {
            guard let arr = spo2ByDevice[id], let first = arr.first, let last = arr.last else { continue }
            if first.timestamp < minTs { minTs = first.timestamp }
            if last.timestamp > maxTs { maxTs = last.timestamp }
        }

        if maxTs <= 0 || minTs == .greatestFiniteMagnitude { return nil }
        let span = max(1.0, maxTs - minTs)
        let pad = span * 0.05
        return Date(timeIntervalSince1970: minTs - pad)...Date(timeIntervalSince1970: maxTs + pad)
    }

    // Color for SpO2 value based on clinical thresholds
    private func colorForSpO2(_ value: Double) -> Color {
        if value < 90 {
            return .red  // Critical
        } else if value < 95 {
            return .orange  // Warning
        } else {
            return .green  // Normal
        }
    }

    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SpO₂").font(.headline)
            let legend = getLegendLabels()
            let keys: [String] = legend.keys
            let labelMap: [String:String] = legend.labelMap
            let active: String? = getActiveDeviceId()
            let points: [SpO2LinePoint] = flattenPoints(keys: keys, labelMap: labelMap)
            let domainLabels: [String] = keys.compactMap { labelMap[$0] }
            let colorRange: [Color] = keys.map { BioColorMap.color(for: $0) }
            let timeDomain = computeTimeDomain(keys: keys)

            #if canImport(Charts)
            if #available(macOS 13.0, iOS 16.0, *) {
                Group {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Time", p.timestamp),
                            y: .value("SpO₂ (%)", p.spo2)
                        )
                        .foregroundStyle(by: .value("Device", p.label))
                        .lineStyle(StrokeStyle(lineWidth: (p.deviceId == active) ? 3 : 1.5, lineCap: .round, lineJoin: .round))
                        .opacity(p.deviceId == active ? 1.0 : 0.55)

                        // Add threshold rule marks
                        RuleMark(y: .value("Critical", 90))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.red.opacity(0.3))

                        RuleMark(y: .value("Warning", 95))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.orange.opacity(0.3))
                    }
                    .chartForegroundStyleScale(domain: domainLabels, range: colorRange)
                    .chartLegend(.visible)
                    .chartYScale(domain: 70...100)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 220)
                    .applyTimeDomain(timeDomain)
                }
            } else {
                fallbackList(keys: keys, labelMap: labelMap)
            }
            #else
            fallbackList(keys: keys, labelMap: labelMap)
            #endif
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func fallbackList(keys: [String], labelMap: [String:String]) -> some View {
        if keys.isEmpty {
            Text("No data").font(.caption).foregroundColor(.secondary)
        } else {
            let spo2ByDevice = extractSpO2ByDevice()
            ForEach(keys, id: \.self) { id in
                let label = labelMap[id] ?? id
                let last = spo2ByDevice[id]?.last?.spo2
                HStack {
                    Text(label)
                    Spacer()
                    if let value = last {
                        Text("\(Int(value))%")
                            .foregroundColor(colorForSpO2(value))
                    } else {
                        Text("--")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - View extension
private extension View {
    @ViewBuilder
    func applyTimeDomain(_ domain: ClosedRange<Date>?) -> some View {
        #if canImport(Charts)
        if #available(macOS 13.0, iOS 16.0, *), let d = domain {
            self.chartXScale(domain: d)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
