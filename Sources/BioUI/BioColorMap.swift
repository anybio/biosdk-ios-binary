//
//  BioColorMap.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/14/25.
//


import SwiftUI

public enum BioColorMap {
    // Color-blind friendly(ish) palette
    private static let palette: [Color] = [
        Color(red:0.00, green:0.45, blue:0.70), // blue
        Color(red:0.87, green:0.80, blue:0.02), // yellow
        Color(red:0.94, green:0.01, blue:0.50), // magenta
        Color(red:0.34, green:0.71, blue:0.91), // sky
        Color(red:0.00, green:0.62, blue:0.45), // teal
        Color(red:0.90, green:0.62, blue:0.00), // orange
        Color(red:0.35, green:0.35, blue:0.35), // gray
        Color(red:0.80, green:0.47, blue:0.65), // purple
        Color(red:0.00, green:0.68, blue:0.26), // green
        Color(red:0.94, green:0.43, blue:0.00)  // vermilion
    ]

    // Stable djb2 hash (don’t use Swift Hasher – not stable across runs)
    private static func djb2(_ s: String) -> UInt32 {
        var hash: UInt32 = 5381
        for b in s.utf8 { hash = ((hash << 5) &+ hash) &+ UInt32(b) }
        return hash
    }

    public static func color(for deviceId: String) -> Color {
        let idx = Int(djb2(deviceId) % UInt32(palette.count))
        return palette[idx]
    }

    // Nice short label: …ABCD
    public static func shortLabel(for deviceId: String) -> String {
        "…\(deviceId.suffix(4))"
    }
}
