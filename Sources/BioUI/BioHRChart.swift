//
//  BioHRChart.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/13/25.
//


import SwiftUI
#if canImport(Charts)
import Charts
#endif
import BioSDK

public struct BioHRChart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }
    
    // MARK: - Internal point model
    private struct HRLinePoint: Identifiable {
        let deviceId: String
        let label: String
        let timestamp: Date
        let bpm: Double
        let index: Int
        var id: String { deviceId + "#" + String(index) + "#" + String(Int(timestamp.timeIntervalSince1970 * 1000)) }
    }

    // MARK: - Dynamic Data Extraction (from new BioLiveStore architecture)

    /// Extract HR data by device from dynamic storage
    private func extractHRByDevice() -> [String: [(timestamp: TimeInterval, bpm: Double)]] {
        var result: [String: [(TimeInterval, Double)]] = [:]

        for deviceId in live.availableDevices {
            let hrSamples = live.samples(for: "heart_rate", deviceId: deviceId)
            let points = hrSamples.compactMap { sample -> (TimeInterval, Double)? in
                guard let bpm = sample.scalarValue else { return nil }
                return (sample.timestamp, bpm)
            }
            if !points.isEmpty {
                result[deviceId] = points
            }
        }

        return result
    }

    /// Get legend labels (device IDs mapped to friendly names)
    private func getLegendLabels() -> (keys: [String], labelMap: [String: String]) {
        let hrByDevice = extractHRByDevice()
        var labelMap: [String: String] = [:]

        for deviceId in hrByDevice.keys {
            labelMap[deviceId] = live.deviceNames[deviceId] ?? deviceId
        }

        return (keys: Array(hrByDevice.keys).sorted(), labelMap: labelMap)
    }

    /// Get the active device (most recent HR data)
    private func getActiveDeviceId() -> String? {
        var latestDeviceId: String?
        var latestTimestamp: TimeInterval = 0

        for deviceId in live.availableDevices {
            let hrSamples = live.samples(for: "heart_rate", deviceId: deviceId)
            if let lastSample = hrSamples.last, lastSample.timestamp > latestTimestamp {
                latestTimestamp = lastSample.timestamp
                latestDeviceId = deviceId
            }
        }

        return latestDeviceId
    }

    // MARK: - Helpers
    private func flattenPoints(keys: [String], labelMap: [String:String]) -> [HRLinePoint] {
        let hrByDevice = extractHRByDevice()
        var total = 0
        for k in keys { total += hrByDevice[k]?.count ?? 0 }
        var out: [HRLinePoint] = []
        if total > 0 { out.reserveCapacity(total) }

        for deviceId in keys {
            guard let series = hrByDevice[deviceId], let label = labelMap[deviceId] else { continue }
            var i = 0
            for pt in series {
                let tsDate = Date(timeIntervalSince1970: pt.timestamp)
                out.append(HRLinePoint(deviceId: deviceId,
                                       label: label,
                                       timestamp: tsDate,
                                       bpm: pt.bpm,
                                       index: i))
                i += 1
            }
        }
        return out
    }

    private func computeTimeDomain(keys: [String]) -> ClosedRange<Date>? {
        let hrByDevice = extractHRByDevice()
        var minTs: TimeInterval = .greatestFiniteMagnitude
        var maxTs: TimeInterval = 0

        for id in keys {
            guard let arr = hrByDevice[id], let first = arr.first, let last = arr.last else { continue }
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
            Text("Heart Rate").font(.headline)
            let legend = getLegendLabels()
            let keys: [String] = legend.keys
            let labelMap: [String:String] = legend.labelMap
            let active: String? = getActiveDeviceId()
            let points: [HRLinePoint] = flattenPoints(keys: keys, labelMap: labelMap)
            let domainLabels: [String] = keys.compactMap { labelMap[$0] }
            let colorRange: [Color] = keys.map { BioColorMap.color(for: $0) }
            let timeDomain = computeTimeDomain(keys: keys)

            #if canImport(Charts)
            if #available(macOS 13.0, iOS 16.0, *) {
                Group {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Time", p.timestamp),
                            y: .value("BPM", p.bpm)
                        )
                        .foregroundStyle(by: .value("Device", p.label))
                        .lineStyle(StrokeStyle(lineWidth: (p.deviceId == active) ? 3 : 1.5, lineCap: .round, lineJoin: .round))
                        .opacity(p.deviceId == active ? 1.0 : 0.55)
                    }
                    .chartForegroundStyleScale(domain: domainLabels, range: colorRange)
                    .chartLegend(.visible)
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
            let hrByDevice = extractHRByDevice()
            ForEach(keys, id: \.self) { id in
                let label = labelMap[id] ?? id
                let last = hrByDevice[id]?.last?.bpm
                HStack { Text(label); Spacer(); Text(last != nil ? "\(Int(last!)) bpm" : "--").foregroundColor(.secondary) }
                    .font(.caption)
            }
        }
    }
}

// MARK: - View extension (kept minimal to avoid generic blow-up)
private extension View {
    @ViewBuilder
    func applyTimeDomain(_ domain: ClosedRange<Date>?) -> some View {
        #if canImport(Charts)
        if #available(macOS 13.0, iOS 16.0, *), let d = domain { self.chartXScale(domain: d) } else { self }
        #else
        self
        #endif
    }
}
