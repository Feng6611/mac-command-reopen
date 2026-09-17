import AppKit
import KikiDesign
import KikiSettings
import SwiftUI
#if APPSTORE
import KikiCommerceCore
#endif

@MainActor
enum SettingsTab: Int, CaseIterable, Hashable {
    case general
    case advanced
    case statistics
    case about

    static func visibleTabs(showProTab: Bool, distributionChannel: DistributionChannel = .current) -> [SettingsTab] {
        allCases.filter { tab in
            tab != .advanced || distributionChannel == .direct
        }
    }

    func title(for distributionChannel: DistributionChannel, language: AppLanguage) -> String {
        switch self {
        case .general: language.string("General")
        case .advanced: language.string("Advanced")
        case .statistics: language.string("Stats")
        case .about: language.string("About")
        }
    }

    func icon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: "gearshape"
        case .advanced: "slider.horizontal.3"
        case .statistics: "chart.bar.xaxis"
        case .about: "info.circle"
        }
    }

    static func kikiTabs(language: AppLanguage) -> [KikiSettingsTabSpec<SettingsTab>] {
        visibleTabs(showProTab: true).map { tab in
            KikiSettingsTabSpec(
                tab,
                title: tab.title(for: .current, language: language),
                systemImage: tab.icon(for: .current)
            )
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var accessController: AppAccessController
    @ObservedObject private var route = SettingsNavigationModel.shared
    @EnvironmentObject private var appLanguage: AppLanguage
#if APPSTORE
    @StateObject private var accessModel = CommandAccessModel.shared
#endif

    var body: some View {
        // The registered controller supplies the shared AppKit/SwiftUI layout.
        KikiSettingsCoordinatorView(
            coordinator: SettingsWindowController.shared.coordinator
        ) { tab in
            switch tab {
            case .general:
                SettingsTabContent()
            case .advanced:
                AdvancedSettingsView()
            case .statistics:
                ReopenStatsView()
            case .about:
                aboutPane
            }
        }
        .id(appLanguage.selected)
        .sheet(item: $route.presentedSheet, onDismiss: {
            route.sheetDidDismiss(canPresent: canPresentSheet)
        }) { sheet in
            sheetContent(sheet)
                .environment(\.locale, appLanguage.locale)
        }
    }

    private func canPresentSheet(_ sheet: SettingsSheet) -> Bool {
#if APPSTORE
        if sheet == .trialExit {
            return TrialExitOffer.resolve(accessModel: accessModel) != nil
        }
#else
        if sheet != .shortcuts { return false }
#endif
        return true
    }

    @ViewBuilder
    private func sheetContent(_ sheet: SettingsSheet) -> some View {
        switch sheet {
        case .shortcuts:
            MacShortcutsSheet()
        case .paywall:
#if APPSTORE
            PaywallSheetView(
                accessModel: accessModel,
                context: .settings,
                // Closing the paywall after the trial ended is the only moment
                // the app knows the user decided not to pay — and the moment
                // the win-back clock starts. `TrialExitOffer` resolves to nil
                // in every other case, including a close that followed a
                // purchase, so this never pitches a discount at a buyer.
                onFinish: {
                    guard TrialExitOffer.resolve(accessModel: accessModel) != nil else { return }
                    route.presentTrialExitOffer()
                },
                onPurchaseCompleted: {
                    route.performAfterDismiss {
                        _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .purchaseCompleted)
                    }
                }
            )
#else
            EmptyView()
#endif
        case .trialExit:
#if APPSTORE
            if let offer = TrialExitOffer.resolve(accessModel: accessModel) {
                TrialExitOfferView(accessModel: accessModel, offer: offer)
            }
#else
            EmptyView()
#endif
#if DEBUG
        case .trialExitDebug:
#if APPSTORE
            TrialExitOfferView(
                accessModel: accessModel,
                offer: .debugPreview,
                marksOfferShown: false,
                rendersAvailableProductForPreview: true
            )
#else
            EmptyView()
#endif
#endif
        }
    }

    private var aboutPane: some View {
        KikiStandardAboutPane(metadata: aboutMetadata)
            .statusContent {
                standardAboutStatusRow
                KikiSettingsLinkRow(
                    title: appLanguage.string("Mac window shortcuts"),
                    value: "",
                    urlString: "",
                    systemImage: "keyboard",
                    trailingSystemImage: "chevron.right",
                    action: { route.presentMacShortcuts() }
                )
#if APPSTORE
                // The same banner General shows, rather than a second design
                // for the same state: one offer, one way it looks, wherever
                // the user meets it.
                WinbackOfferRow(accessModel: accessModel) {
                    route.presentTrialExitOffer()
                }
#endif
            }
            .additionalLinks {
                SettingsTrailingLinkRow(
                    title: appLanguage.string("Made by"),
                    value: ExternalLinks.developerName,
                    urlString: ExternalLinks.developerURL,
                    systemImage: "person"
                )
                SettingsTrailingLinkRow(
                    title: appLanguage.string("Website"),
                    value: ExternalLinks.websiteDisplayName,
                    urlString: ExternalLinks.officialURL,
                    systemImage: "globe"
                )
                SettingsTrailingCopyRow(
                    title: appLanguage.string("Email"),
                    value: ExternalLinks.contactEmailAddress,
                    systemImage: "envelope"
                )
                SettingsTrailingLinkRow(
                    title: appLanguage.string("Source"),
                    value: ExternalLinks.repositoryDisplayName,
                    urlString: ExternalLinks.githubURL,
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
                KikiSettingsHelperText(
                    appLanguage.string("Open source under MIT. Command Reopen needs no system permissions — and you can check that in the source rather than take our word for it.")
                )
            }
            .additionalSections {
#if !APPSTORE
                Section { DirectSupportCardRow() }
#endif
#if DEBUG && APPSTORE
            Section {
                ProAccessDebugRows(
                    onPresentOnboarding: {
                        OnboardingWindowController.shared.replayFromDebugSettings()
                    },
                    onPresentPaywall: {
                        route.presentPaywall()
                    },
                    onPresentTrialExitOffer: {
                        route.presentTrialExitOfferDebugPreview()
                    },
                    onPresentReviewPrompt: {
                        ReopenStatsStore.shared.presentCustomReviewPromptPreview()
                    }
                )
            } header: {
                Text(appLanguage.string("Developer Testing"))
            } footer: {
                KikiSettingsHelperText(appLanguage.string("Debug only. Live clears the Pro access override. The win-back window needs Pro access set to Expired, the same gate the app applies."))
            }
#endif
        }
    }

    private var aboutMetadata: KikiAppMetadata { .bundle() }

    private var standardAboutStatusRow: some View {
        KikiSettingsValueRow(appLanguage.string("Status"), systemImage: "info.circle") {
            if let accessAction {
                Button(action: accessAction) {
                    statusValueContent
                }
                .buttonStyle(.plain)
            } else {
                statusValueContent
            }
        }
    }

    @ViewBuilder
    private var statusValueContent: some View {
        HStack(spacing: DS.Spacing.xs) {
            if accessPresentation.title == appLanguage.string("Free") || accessPresentation.title == appLanguage.string("Lifetime") {
                Text("👑")
            } else if accessPresentation.tone != .neutral {
                Image(systemName: accessPresentation.tone.systemImage)
            }
            Text(accessPresentation.title)
                .lineLimit(1)
                .foregroundStyle(accessPresentation.tone == .neutral ? .secondary : DS.Colors.brandPrimary)
            if accessAction != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessAction: (@MainActor () -> Void)? {
        guard accessController.distributionChannel == .appStore else { return nil }
        return { route.presentPaywall() }
    }

    private var accessPresentation: KikiAccessStatusPresentation {
        let language = AppLanguage.shared
#if APPSTORE
        switch accessModel.presentationReadiness {
        case .idle, .loading:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: language.string(localized: "Checking purchases…"),
                subtitle: language.string(localized: "Verifying your Command Reopen Pro access."),
                actionTitle: nil
            )
        case .degraded:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: language.string(localized: "Purchases unavailable"),
                subtitle: language.string(localized: "We couldn't verify your purchase status. Try again when you're online."),
                actionTitle: language.string(localized: "View options")
            )
        case .ready:
            break
        }

        switch accessModel.status {
        case .notStarted:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: language.string(localized: "Trial not started"),
                subtitle: language.string(localized: "Start the free trial when you are ready."),
                actionTitle: language.string(localized: "View options")
            )
        case .trial(.time(let daysRemaining, _)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: language.string(localized: "\(daysRemaining) days left", comment: "Trial time remaining in the About pane; plural-aware in the catalog."),
                subtitle: language.string(localized: "Command Reopen Pro is active during the trial."),
                actionTitle: language.string(localized: "View plans")
            )
        case .trial(.usage(_, let used, let limit)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: language.string(localized: "\(max(0, limit - used)) uses left", comment: "Trial usage remaining in the About pane; plural-aware in the catalog."),
                subtitle: language.string(localized: "Command Reopen Pro is active during the trial."),
                actionTitle: language.string(localized: "View plans")
            )
        case .expired:
            return KikiAccessStatusPresentation(
                tone: .expired,
                title: language.string(localized: "Trial ended"),
                subtitle: language.string(localized: "Upgrade to continue automatic window reopening."),
                actionTitle: language.string(localized: "Upgrade")
            )
        case .pro(let plan, _):
            return KikiAccessStatusPresentation(
                tone: .active,
                title: localizedPlanTitle(for: plan),
                subtitle: localizedPlanBillingDetail(for: plan),
                actionTitle: language.string(localized: "View plans")
            )
        }
#else
        // The status row answers the money question, not the channel question:
        // this build costs nothing and withholds nothing. Channel names
        // (Direct, Community edition) kept getting rewritten because they
        // named the distribution in a row that should state the deal; where
        // provenance is the question — README, Releases — it is "the GitHub
        // build".
        return KikiAccessStatusPresentation(
            tone: .active,
            title: language.string(localized: "Free", comment: "About status value for the free GitHub build."),
            subtitle: language.string(localized: "Full-featured, nothing locked. Same app as the App Store version.", comment: "About status subtitle for the free GitHub build."),
            actionTitle: nil
        )
#endif
    }

#if APPSTORE
    private func localizedPlanTitle(for plan: KikiAccessPlan) -> String {
        switch plan.commercePlan {
        case .yearly: appLanguage.string("Yearly")
        case .lifetime, .winbackLifetime: appLanguage.string("Lifetime")
        default: plan.title
        }
    }

    private func localizedPlanBillingDetail(for plan: KikiAccessPlan) -> String {
        switch plan.commercePlan {
        case .yearly: appLanguage.string("per year")
        case .lifetime, .winbackLifetime: appLanguage.string("once")
        default: plan.billingDetail
        }
    }
#endif
}

private struct SettingsTrailingLinkRow: View {
    let title: String
    let value: String
    let urlString: String
    let systemImage: String

    var body: some View {
        KikiSettingsValueRow(title, systemImage: systemImage) {
            Button {
                KikiSettingsActions.openURL(urlString)
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingsTrailingCopyRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        KikiSettingsValueRow(title, systemImage: systemImage) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
