//
//  ProAccessDebugSection.swift
//  CmdReopen
//

#if DEBUG && APPSTORE
import Foundation
import KikiCommerceCore
import KikiSettings
import SwiftUI

struct ProAccessDebugRows: View {
    @ObservedObject private var accessModel = CommandAccessModel.shared
    let onPresentOnboarding: () -> Void
    let onPresentPaywall: () -> Void
    let onPresentTrialExitOffer: () -> Void

    var body: some View {
        KikiSettingsDebugPreviewRow(
            "Pro access",
            selection: debugMode,
            options: KikiAccessDebugMode.allCases,
            isOverrideActive: accessModel.debugProAccessOverride != nil,
            optionTitle: \.displayName
        )

        KikiSettingsValueRow("Test flows", systemImage: "play.rectangle") {
            Button("Onboarding", action: onPresentOnboarding)
            Button("Paywall", action: onPresentPaywall)
            Button("Retention offer", action: onPresentTrialExitOffer)
        }

        // Presenting the retention card from "Test flows" deliberately does
        // not start the real clock, so the banners it leaves behind had no
        // way to be seen. This row is that missing state: it opens the
        // window directly, at a chosen point inside it, and the banners in
        // General and About follow.
        KikiSettingsValueRow("Win-back window", systemImage: "tag") {
            Picker("", selection: winbackWindow) {
                Text("Closed").tag(nil as Int?)
                Text("2 days left").tag(2 as Int?)
                Text("Ends today").tag(1 as Int?)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var winbackWindow: Binding<Int?> {
        let accessModel = accessModel

        return Binding(
            get: {
                guard accessModel.isWinbackDebugForced,
                      let offer = TrialExitOffer.resolve(accessModel: accessModel) else {
                    return nil
                }
                return offer.daysRemaining()
            },
            set: { days in
                // Same reconciliation hazard as the access picker above:
                // publish the change after this render pass.
                DispatchQueue.main.async {
                    accessModel.setWinbackDebugWindow(daysRemaining: days)
                }
            }
        )
    }

    private var debugMode: Binding<KikiAccessDebugMode> {
        let accessModel = accessModel

        return Binding(
            get: { accessModel.debugProAccessOverride ?? .live },
            set: { mode in
                // A segmented Picker can reconcile selection while SwiftUI is
                // rendering. Publish the access-state change in the next turn.
                DispatchQueue.main.async {
                    if mode == .live {
                        accessModel.clearDebugProAccessOverride()
                    } else {
                        accessModel.setDebugProAccessOverride(mode)
                    }
                }
            }
        )
    }
}
#endif
