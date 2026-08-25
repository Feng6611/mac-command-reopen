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
    @ObservedObject private var appLanguage = AppLanguage.shared
    let onPresentOnboarding: () -> Void
    let onPresentPaywall: () -> Void
    let onPresentTrialExitOffer: () -> Void
    let onPresentReviewPrompt: () -> Void

    var body: some View {
        KikiSettingsDebugPreviewRow(
            appLanguage.string(localized: "Pro access"),
            selection: debugMode,
            options: KikiAccessDebugMode.allCases,
            isOverrideActive: accessModel.debugProAccessOverride != nil,
            optionTitle: localizedDebugModeTitle(for:)
        )

        KikiSettingsValueRow(appLanguage.string(localized: "Test flows"), systemImage: "play.rectangle") {
            Button(appLanguage.string(localized: "Onboarding"), action: onPresentOnboarding)
            Button(appLanguage.string(localized: "Paywall"), action: onPresentPaywall)
            Button(appLanguage.string(localized: "Retention offer"), action: onPresentTrialExitOffer)
            Button(appLanguage.string(localized: "Review prompt"), action: onPresentReviewPrompt)
        }

        // Presenting the retention card from "Test flows" deliberately does
        // not start the real clock, so the banner it leaves behind had no way
        // to be seen. This row is that missing state: it opens the window
        // directly, at a chosen point inside it. Pro access must be Expired
        // for anything to show — that is the production gate, and the row
        // does not pretend otherwise.
        KikiSettingsValueRow(appLanguage.string(localized: "Win-back window"), systemImage: "tag") {
            Picker("", selection: winbackWindow) {
                Text(appLanguage.string(localized: "Closed")).tag(nil as Int?)
                Text(appLanguage.string(localized: "2 days left")).tag(2 as Int?)
                Text(appLanguage.string(localized: "Ends today")).tag(1 as Int?)
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
                      let offer = accessModel.activeWinbackOffer else {
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

    private func localizedDebugModeTitle(for mode: KikiAccessDebugMode) -> String {
        switch mode {
        case .live: appLanguage.string(localized: "Live")
        case .notPro: appLanguage.string(localized: "Not Pro")
        case .trial: appLanguage.string(localized: "Trial")
        case .expired: appLanguage.string(localized: "Expired")
        case .pro: appLanguage.string(localized: "Pro")
        }
    }
}
#endif
