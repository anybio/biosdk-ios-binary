import SwiftUI
#if canImport(Charts)
import Charts
#endif
import BioSDK

public struct BioLineChart: View {
    @ObservedObject var live: BioLiveStore
    let series: KeyPath<BioLiveStore, [TimeSeries]>
    let title: String
    let yLabel: String?
    let cap: Int

    public init(
        live: BioLiveStore,
        series: KeyPath<BioLiveStore, [TimeSeries]>,
        title: String,
        yLabel: String? = nil,
        cap: Int = 2_000
    ) {
        self.live = live
        self.series = series
        self.title = title
        self.yLabel = yLabel
        self.cap = cap
    }

    private var flattened: [Double] {
        var out: [Double] = []
        let chunks = live[keyPath: series]
        for ts in chunks {
            guard !ts.values.isEmpty else { continue }
            out.append(contentsOf: ts.values)
            if out.count > cap {
                out.removeFirst(out.count - cap)
            }
        }
        return out
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            #if canImport(Charts)
            if #available(macOS 13.0, iOS 16.0, *) {
                Chart {
                    ForEach(Array(flattened.enumerated()), id: \.offset) { i, v in
                        LineMark(
                            x: .value("Index", i),
                            y: .value(yLabel ?? title, v)
                        )
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
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

    @ViewBuilder private var fallbackSummary: some View {
        if let last = flattened.last {
            Text("Latest: \(Int(last))")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Text("No data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
