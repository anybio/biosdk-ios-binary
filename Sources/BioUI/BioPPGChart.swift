//
//  BioPPGChart.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/12/25.
//


import SwiftUI
import BioSDK

public struct BioPPGChart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    public var body: some View {
        BioLineChart(
            live: live,
            series: \.ppg,          // [TimeSeries]
            title: "PPG (a.u.)",
            cap: 2_000              // ~5s @ 400 Hz
        )
    }
}
