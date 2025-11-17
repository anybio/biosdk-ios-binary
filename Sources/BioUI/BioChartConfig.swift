//
//  BioChartConfig 2.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/12/25.
//


import SwiftUI

public struct BioChartConfig {
    public var title: String?
    public var yUnit: String?
    public var maxPoints: Int
    public var yRange: ClosedRange<Double>?    // nil = auto
    public var showGrid: Bool
    public var paused: Binding<Bool>?          // optional external pause binding

    public init(title: String? = nil,
                yUnit: String? = nil,
                maxPoints: Int = 900,
                yRange: ClosedRange<Double>? = nil,
                showGrid: Bool = true,
                paused: Binding<Bool>? = nil) {
        self.title = title
        self.yUnit = yUnit
        self.maxPoints = maxPoints
        self.yRange = yRange
        self.showGrid = showGrid
        self.paused = paused
    }
}

// Convenient presets you can reuse from host apps
public extension BioChartConfig {
    static func ecg(title: String = "ECG",
                    yUnit: String = "mV",
                    maxPoints: Int = 1200,
                    range: ClosedRange<Double> = -5...5,
                    paused: Binding<Bool>? = nil) -> BioChartConfig {
        .init(title: title, yUnit: yUnit, maxPoints: maxPoints, yRange: range, paused: paused)
    }
    static func ppg(title: String = "PPG",
                    maxPoints: Int = 1200,
                    paused: Binding<Bool>? = nil) -> BioChartConfig {
        .init(title: title, yUnit: nil, maxPoints: maxPoints, yRange: nil, paused: paused)
    }
    static func eda(title: String = "EDA",
                    yUnit: String = "µS",
                    range: ClosedRange<Double> = 0...20,
                    paused: Binding<Bool>? = nil) -> BioChartConfig {
        .init(title: title, yUnit: yUnit, maxPoints: 600, yRange: range, paused: paused)
    }
    static func temp(title: String = "Temperature",
                     yUnit: String = "°C",
                     range: ClosedRange<Double> = 20...45,
                     paused: Binding<Bool>? = nil) -> BioChartConfig {
        .init(title: title, yUnit: yUnit, maxPoints: 600, yRange: range, paused: paused)
    }
}
