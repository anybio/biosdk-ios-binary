//
//  BioChartTheme.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/12/25.
//


import SwiftUI

public struct BioChartTheme {
    public var lineWidth: CGFloat
    public var cornerRadius: CGFloat
    public var gridOpacity: CGFloat
    public var backgroundMaterial: Material
    public var height: CGFloat = 180
    /// If nil, Charts will auto-range.
    public var hrAxis: ClosedRange<Double>? = 40...200

    public init(lineWidth: CGFloat = 1.5,
                cornerRadius: CGFloat = 12,
                gridOpacity: CGFloat = 0.25,
                backgroundMaterial: Material = .ultraThinMaterial) {
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        self.gridOpacity = gridOpacity
        self.backgroundMaterial = backgroundMaterial
    }

    public static let `default` = BioChartTheme()
}

private struct BioChartThemeKey: EnvironmentKey {
    static let defaultValue: BioChartTheme = .default
}

public extension EnvironmentValues {
    var bioChartTheme: BioChartTheme {
        get { self[BioChartThemeKey.self] }
        set { self[BioChartThemeKey.self] = newValue }
    }
}

public extension View {
    func bioChartTheme(_ theme: BioChartTheme) -> some View {
        environment(\.bioChartTheme, theme)
    }
}
