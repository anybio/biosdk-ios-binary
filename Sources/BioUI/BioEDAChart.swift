//
//  BioEDAChart.swift
//  BioSDK
//
//  Created by Stephen Saine on 8/12/25.
//


import SwiftUI
import BioSDK


public struct BioEDAChart: View {
    @ObservedObject var live: BioLiveStore
    public init(live: BioLiveStore) { self.live = live }

    public var body: some View {
        BioLineChart(
            live: live,
            series: \.eda,          // [TimeSeries]
            title: "EDA (µS)",
            cap: 200                // ~5s @ 20 Hz
        )
    }
}
