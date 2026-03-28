//
//  ReopenStatsView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import SwiftUI

struct ReopenStatsView: View {
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore

    var body: some View {
        Section {
            HStack {
                Text("Total Reopens")
                Spacer()
                Text("\(reopenStatsStore.totalSuccessfulReopens)")
                    .monospacedDigit()
            }

            if reopenStatsStore.appStats.isEmpty {
                Text("No reopen activity yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(reopenStatsStore.appStats) { stat in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.displayName)
                            if stat.displayName != stat.bundleID {
                                Text(stat.bundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }

                        Spacer()

                        Text("\(stat.count)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button("Reset Statistics", role: .destructive) {
                reopenStatsStore.reset()
            }
            .disabled(reopenStatsStore.totalSuccessfulReopens == 0)
        } header: {
            Text("Statistics")
        }
    }
}
