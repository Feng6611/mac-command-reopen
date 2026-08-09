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
