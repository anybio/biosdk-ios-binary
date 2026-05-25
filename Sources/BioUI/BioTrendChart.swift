//
//  BioTrendChart.swift
//  BioUI
//
//  Static-data line chart for displaying historical biosignal trends —
//  e.g. 7-day HR from `BioSDK.fetchTrend(...)`. Distinct from the live-
//  streaming charts (BioHRChart, BioLineChart, etc.) which bind to a
//  `BioLiveStore` and tick as BLE samples arrive. This one renders a
//  fixed `[DataPoint]` and never observes anything.
//
//  Public API is deliberately decoupled from BioIngest / BioSDK types:
//  the chart takes a plain `[DataPoint]` so AnyBio (or any other
//  consumer) can map whatever upstream shape they prefer
//  (TrendSeries, HealthKit aggregates, custom backfill) into the
//  chart's input. The mapping helper for the SDK's TrendSeries lives
//  in the call site, not here.
//

import SwiftUI
import Charts

/// A historical-data line chart with a gradient fill under the line and
/// a one-glance header (title + optional unit + optional trailing summary
/// like "↗ 72 avg"). Use the convenience initializer if you have an
/// `ISO8601`-ish date string per point; pass parsed `Date`s directly when
/// the producer already has them.
public struct BioTrendChart: View {

    /// Single point a `BioTrendChart` plots. `id` lets SwiftUI Charts
    /// diff efficiently on series reloads (use the raw date string from
    /// the backend if available; otherwise a stable derived key).
    public struct DataPoint: Identifiable, Hashable {
        public let id: String
        public let date: Date
        public let value: Double

        public init(id: String, date: Date, value: Double) {
            self.id = id
            self.date = date
            self.value = value
        }
    }

    /// Position of the optional trailing summary in the header row.
    public struct Summary: Equatable {
        public let label: String
        public let trendDirection: Direction?

        public enum Direction: Equatable {
            case improving, stable, declining
        }

        public init(label: String, trendDirection: Direction? = nil) {
            self.label = label
            self.trendDirection = trendDirection
        }
    }

    /// Visual style for the chart body. Pick based on what the underlying
    /// aggregation actually represents — `bars` reads as "discrete daily
    /// totals" (use for sums like steps, calories, sleep duration);
    /// `lineFill` reads as "a continuous signal sampled per day" (use for
    /// means / mins / max of vitals like resting HR, HRV, SpO2). A
    /// daily-mean drawn as a continuous line is visually misleading;
    /// daily-sum drawn as a smoothed line conflates discrete events.
    public enum Style: Equatable {
        /// Area + line over the day points with a soft gradient under.
        /// Right for continuous-signal aggregations (mean / min / max).
        case lineFill
        /// One bar per day with a dashed average rule across. Right for
        /// accumulating / discrete aggregations (sum, total_minutes_asleep).
        case bars
    }

    let points: [DataPoint]
    let title: String
    let unit: String?
    let summary: Summary?
    let style: Style
    let tintColor: Color
    let height: CGFloat

    public init(
        points: [DataPoint],
        title: String,
        unit: String? = nil,
        summary: Summary? = nil,
        style: Style = .lineFill,
        tintColor: Color = .accentColor,
        height: CGFloat = 140
    ) {
        self.points = points
        self.title = title
        self.unit = unit
        self.summary = summary
        self.style = style
        self.tintColor = tintColor
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if points.isEmpty {
                emptyState
            } else {
                chart
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let summary {
                summaryView(summary)
            }
        }
    }

    @ViewBuilder
    private func summaryView(_ summary: Summary) -> some View {
        HStack(spacing: 4) {
            if let direction = summary.trendDirection {
                Image(systemName: arrow(for: direction))
                    .font(.caption2)
                    .foregroundColor(color(for: direction))
            }
            Text(summary.label)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func arrow(for direction: Summary.Direction) -> String {
        switch direction {
        case .improving: return "arrow.up.right"
        case .stable:    return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    /// Direction color reflects movement, not value judgment — "improving"
    /// for HR could be either up or down depending on the biosignal, so the
    /// BE's `trend` label is the authority. We render the arrow only.
    private func color(for direction: Summary.Direction) -> Color {
        switch direction {
        case .improving: return tintColor
        case .stable:    return .secondary
        case .declining: return tintColor.opacity(0.6)
        }
    }

    // MARK: - Chart

    @ChartContentBuilder
    private var marks: some ChartContent {
        switch style {
        case .lineFill:
            ForEach(points) { point in
                // Line on top of the gradient area gives the "filled
                // sparkline" look the other Bio charts use. `catmullRom`
                // softens the daily edges without smoothing through real
                // outliers (compare to `cardinal` which over-rounds).
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(LinearGradient(
                    colors: [tintColor.opacity(0.32), tintColor.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(tintColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
            }

        case .bars:
            // Bars for accumulating / discrete daily values. A dashed
            // rule across the chart at the mean gives a quick "above/
            // below typical" read without needing to label every bar.
            // Bars sit on a 0 baseline so absolute counts are
            // visually accurate (no truncation tricks).
            let mean: Double = points.isEmpty
                ? 0
                : points.map(\.value).reduce(0, +) / Double(points.count)

            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(tintColor.gradient)
                .cornerRadius(3)
            }
            if !points.isEmpty {
                RuleMark(y: .value("Average", mean))
                    .foregroundStyle(tintColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
            }
        }
    }

    private var chart: some View {
        Chart {
            marks
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            // Coarse — just the endpoints. We don't want to fight the
            // axis-label engine for crowded daily ticks on a 4-inch wide
            // card; the trailing summary in the header carries the
            // numeric specifics.
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}
