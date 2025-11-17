//
//  BioHRVChart.swift
//  BioSDK
//
//  Heart Rate Variability (HRV) waveform chart - RMSSD over time
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif
import BioSDK

public struct BioHRVChart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    // MARK: - Internal point model
    private struct HRVLinePoint: Identifiable {
        let deviceId: String
        let label: String
        let timestamp: Date
        let rmssd: Double
        let index: Int
        var id: String { deviceId + "#" + String(index) + "#" + String(Int(timestamp.timeIntervalSince1970 * 1000)) }
    }

    // MARK: - Dynamic Data Extraction

    /// Extract HRV data by device from dynamic storage
    private func extractHRVByDevice() -> [String: [(timestamp: TimeInterval, rmssd: Double)]] {
        var result: [String: [(TimeInterval, Double)]] = [:]

        for deviceId in live.availableDevices {
            let hrvSamples = live.samples(for: "hrv", deviceId: deviceId)
            let points = hrvSamples.compactMap { sample -> (TimeInterval, Double)? in
                guard let rmssd = sample.scalarValue else { return nil }
                return (sample.timestamp, rmssd)
            }
            if !points.isEmpty {
                result[deviceId] = points
            }
        }

        return result
    }

    /// Get legend labels (device IDs mapped to friendly names)
    private func getLegendLabels() -> (keys: [String], labelMap: [String: String]) {
        let hrvByDevice = extractHRVByDevice()
        var labelMap: [String: String] = [:]

        for deviceId in hrvByDevice.keys {
            labelMap[deviceId] = live.deviceNames[deviceId] ?? deviceId
        }

        return (keys: Array(hrvByDevice.keys).sorted(), labelMap: labelMap)
    }

    /// Get the active device (most recent HRV data)
    private func getActiveDeviceId() -> String? {
        var latestDeviceId: String?
        var latestTimestamp: TimeInterval = 0

        for deviceId in live.availableDevices {
            let hrvSamples = live.samples(for: "hrv", deviceId: deviceId)
            if let lastSample = hrvSamples.last, lastSample.timestamp > latestTimestamp {
                latestTimestamp = lastSample.timestamp
                latestDeviceId = deviceId
            }
        }

        return latestDeviceId
    }

    // MARK: - Helpers
    private func flattenPoints(keys: [String], labelMap: [String:String]) -> [HRVLinePoint] {
        let hrvByDevice = extractHRVByDevice()
        var total = 0
        for k in keys { total += hrvByDevice[k]?.count ?? 0 }
        var out: [HRVLinePoint] = []
        if total > 0 { out.reserveCapacity(total) }

        for deviceId in keys {
            guard let series = hrvByDevice[deviceId], let label = labelMap[deviceId] else { continue }
            var i = 0
            for pt in series {
                let tsDate = Date(timeIntervalSince1970: pt.timestamp)
                out.append(HRVLinePoint(deviceId: deviceId,
                                       label: label,
                                       timestamp: tsDate,
                                       rmssd: pt.rmssd,
                                       index: i))
                i += 1
            }
        }
        return out
    }

    private func computeTimeDomain(keys: [String]) -> ClosedRange<Date>? {
        let hrvByDevice = extractHRVByDevice()
        var minTs: TimeInterval = .greatestFiniteMagnitude
        var maxTs: TimeInterval = 0

        for id in keys {
            guard let arr = hrvByDevice[id], let first = arr.first, let last = arr.last else { continue }
            if first.timestamp < minTs { minTs = first.timestamp }
            if last.timestamp > maxTs { maxTs = last.timestamp }
        }

        if maxTs <= 0 || minTs == .greatestFiniteMagnitude { return nil }
        let span = max(1.0, maxTs - minTs)
        let pad = span * 0.05
        return Date(timeIntervalSince1970: minTs - pad)...Date(timeIntervalSince1970: maxTs + pad)
    }

    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HRV (RMSSD)").font(.headline)
            let legend = getLegendLabels()
            let keys: [String] = legend.keys
            let labelMap: [String:String] = legend.labelMap
            let active: String? = getActiveDeviceId()
            let points: [HRVLinePoint] = flattenPoints(keys: keys, labelMap: labelMap)
            let domainLabels: [String] = keys.compactMap { labelMap[$0] }
            let colorRange: [Color] = keys.map { BioColorMap.color(for: $0) }
            let timeDomain = computeTimeDomain(keys: keys)

            #if canImport(Charts)
            if #available(macOS 13.0, iOS 16.0, *) {
                Group {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Time", p.timestamp),
                            y: .value("RMSSD (ms)", p.rmssd)
                        )
                        .foregroundStyle(by: .value("Device", p.label))
                        .lineStyle(StrokeStyle(lineWidth: (p.deviceId == active) ? 3 : 1.5, lineCap: .round, lineJoin: .round))
                        .opacity(p.deviceId == active ? 1.0 : 0.55)
                    }
                    .chartForegroundStyleScale(domain: domainLabels, range: colorRange)
                    .chartLegend(.visible)
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
            let hrvByDevice = extractHRVByDevice()
            ForEach(keys, id: \.self) { id in
                let label = labelMap[id] ?? id
                let last = hrvByDevice[id]?.last?.rmssd
                HStack {
                    Text(label)
                    Spacer()
                    Text(last != nil ? "\(Int(last!)) ms" : "--")
                        .foregroundColor(.secondary)
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
