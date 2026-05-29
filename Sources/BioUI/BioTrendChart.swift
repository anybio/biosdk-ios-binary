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
    ///
    /// `source` is an optional slug (e.g. `"apple_health"`, `"fitbit"`)
    /// identifying which device/integration produced this point. When
    /// the input contains more than one distinct `source` value, the
    /// chart renders one line (or grouped bar set) per source —
    /// mirroring the live-streaming `BioHRChart` per-device pattern.
    /// `nil` source values collapse into a single anonymous series, so
    /// single-source callers don't have to set it.
    public struct DataPoint: Identifiable, Hashable {
        public let id: String
        public let date: Date
        public let value: Double
        public let source: String?

        public init(id: String, date: Date, value: Double, source: String? = nil) {
            self.id = id
            self.date = date
            self.value = value
            self.source = source
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
    /// Optional slug → Color mapping for multi-source rendering. Only
    /// consulted when `points` contains more than one distinct
    /// `source` slug; if a slug is missing from the map it falls back
    /// to `tintColor`. AnyBio owns the slug palette (so the chart's
    /// per-source colors match the section-level legend).
    let sourcePalette: [String: Color]?
    let height: CGFloat

    public init(
        points: [DataPoint],
        title: String,
        unit: String? = nil,
        summary: Summary? = nil,
        style: Style = .lineFill,
        tintColor: Color = .accentColor,
        sourcePalette: [String: Color]? = nil,
        height: CGFloat = 140
    ) {
        self.points = points
        self.title = title
        self.unit = unit
        self.summary = summary
        self.style = style
        self.tintColor = tintColor
        self.sourcePalette = sourcePalette
        self.height = height
    }

    /// Distinct source slugs present in `points`, sorted for stable
    /// rendering order across reloads (so colors don't shuffle when a
    /// later sync brings in points in a different order). Empty / single
    /// slug means single-source path.
    private var distinctSources: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for p in points {
            if let s = p.source, seen.insert(s).inserted {
                ordered.append(s)
            }
        }
        return ordered.sorted()
    }

    private var isMultiSource: Bool { distinctSources.count > 1 }

    /// Color for the single-source rendering path. Uses `sourcePalette`
    /// when the caller supplied one for this chart's lone source, so a
    /// single-source chart embedded in a multi-source *section* matches
    /// that section's legend; otherwise falls back to `tintColor` (the
    /// per-metric brand color) for single-source sections and palette-less
    /// callers. `nil`-source points (single anonymous series) also fall
    /// back to `tintColor`.
    private var soloSourceColor: Color {
        guard let slug = distinctSources.first,
              let mapped = sourcePalette?[slug] else {
            return tintColor
        }
        return mapped
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
            if isMultiSource {
                // Per-source line. The area-fill is dropped in
                // multi-source mode: stacking translucent fills from
                // different sources creates a confusing color mix
                // (and obscures the line-by-line comparison the
                // caller asked for by sending separate sources).
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Source", point.source ?? "unknown"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
            } else {
                // Single-source path: area + line over the day points,
                // matching the look the other Bio charts use.
                // `catmullRom` softens the daily edges without smoothing
                // through real outliers (compare to `cardinal` which
                // over-rounds).
                //
                // `soloColor` honors `sourcePalette` when the caller
                // provided one for this chart's single source — so a
                // single-source chart that sits in a multi-source
                // *section* (e.g. Steps from only Fitbit alongside RHR
                // from only WHOOP) draws in the same color the section
                // legend assigns that source, instead of `tintColor`.
                // Falls back to `tintColor` when no palette is given
                // (single-source section / KitchenSink), preserving the
                // per-metric brand color in that case.
                let soloColor = soloSourceColor
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [soloColor.opacity(0.32), soloColor.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(soloColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                }
            }

        case .bars:
            // Bars for accumulating / discrete daily values. A dashed
            // rule across the chart at the mean gives a quick "above/
            // below typical" read without needing to label every bar.
            // Bars sit on a 0 baseline so absolute counts are
            // visually accurate (no truncation tricks).
            if isMultiSource {
                // Grouped (side-by-side) bars per source within each
                // day's x-slot. The avg rule is suppressed in
                // multi-source mode: one mean across heterogeneous
                // sources isn't a meaningful number (HK steps and
                // Fitbit steps from the same user double-count); a
                // per-source mean rule was rejected as visual clutter.
                ForEach(points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Value", point.value)
                    )
                    .position(by: .value("Source", point.source ?? "unknown"))
                    .foregroundStyle(by: .value("Source", point.source ?? "unknown"))
                    .cornerRadius(2)
                }
            } else {
                let mean: Double = points.isEmpty
                    ? 0
                    : points.map(\.value).reduce(0, +) / Double(points.count)
                // See `soloSourceColor` rationale in the lineFill branch:
                // palette color when this chart's single source has one
                // (keeps it consistent with the section legend), else
                // the per-metric tintColor.
                let soloColor = soloSourceColor

                ForEach(points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(soloColor.gradient)
                    .cornerRadius(3)
                }
                if !points.isEmpty {
                    RuleMark(y: .value("Average", mean))
                        .foregroundStyle(soloColor.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                }
            }
        }
    }

    private var chart: some View {
        let domain = distinctSources
        let range = domain.map { sourcePalette?[$0] ?? tintColor }

        return Chart {
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
        // Pin the per-source color domain explicitly so AnyBio's
        // section-level legend (rendered separately) and the chart use
        // the same source→color assignments. Without this, SwiftUI
        // Charts auto-derives colors from its default palette and
        // they'd disagree with the legend.
        .chartForegroundStyleScale(domain: domain, range: range)
        // The chart's auto-generated per-series legend duplicates the
        // section-level legend AnyBio renders for the whole Trends
        // group. Hide it here so we don't show the same chips twice.
        .chartLegend(.hidden)
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
