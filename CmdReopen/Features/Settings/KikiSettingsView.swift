import KikiSettings
import SwiftUI
#if APPSTORE
import KikiCommerceCore
#endif

@MainActor
enum SettingsTab: Int, CaseIterable, Hashable {
    case general
    case statistics
    case about

    static func visibleTabs(showProTab: Bool) -> [SettingsTab] {
        allCases
    }

    func title(for distributionChannel: DistributionChannel, language: AppLanguage) -> String {
        switch self {
        case .general: language.string("General")
        case .statistics: language.string("Stats")
        case .about: language.string("About")
        }
    }

    func icon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: "gearshape"
        case .statistics: "chart.bar.xaxis"
        case .about: "info.circle"
        }
    }

    static func kikiTabs(language: AppLanguage) -> [KikiSettingsTabSpec<SettingsTab>] {
        allCases.map { tab in
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
        KikiSettingsCoordinatorView(coordinator: SettingsWindowController.shared.coordinator) { tab in
            switch tab {
            case .general:
                SettingsTabContent()
            case .statistics:
                ReopenStatsView()
            case .about:
                aboutPane
            }
        }
        .id(appLanguage.selected)
#if APPSTORE
        .sheet(isPresented: $route.isPaywallSheetPresented) {
            PaywallSheetView(
                accessModel: accessModel,
                context: .settings,
                source: route.paywallSource,
                // Closing the paywall after the trial ended is the only moment
                // the app knows the user decided not to pay. `TrialExitOffer`
                // resolves to nil in every other case, including a close that
                // followed a purchase.
                onFinish: {
                    guard TrialExitOffer.resolve(accessModel: accessModel) != nil else { return }
                    route.presentTrialExitOffer()
                },
                onPurchaseCompleted: {
                    _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .purchaseCompleted)
                }
            )
        }
        .sheet(isPresented: $route.isTrialExitOfferPresented) {
            // Resolved again on presentation rather than carried over from the
            // paywall's close: the sheet is asked for one run loop later, and
            // anything that changed access state in between should cancel it.
            if let offer = TrialExitOffer.resolve(accessModel: accessModel) {
                TrialExitOfferSheet(accessModel: accessModel, offer: offer)
            }
        }
#if DEBUG
        .sheet(isPresented: $route.isTrialExitOfferDebugPreviewPresented) {
            TrialExitOfferSheet(
                accessModel: accessModel,
                offer: .debugPreview
            )
        }
#endif
#endif
    }

    private var aboutPane: some View {
        // KikiStandardAboutPane has no extension slot. Compose the same public
        // Kiki atoms so the DEBUG-only controls can be their own final section.
        KikiSettingsPane {
            Section {
                KikiAppIdentityView(
                    appName: aboutMetadata.appName,
                    versionText: aboutMetadata.displayVersion
                )
                .padding(.vertical, DS.Spacing.xl)
                .listRowBackground(Color(nsColor: .windowBackgroundColor))
            }

            Section {
                KikiSettingsStatusRow(
                    title: appLanguage.string("Status"),
                    value: accessPresentation.title,
                    systemImage: "info.circle",
                    valueSystemImage: accessPresentation.tone == .neutral ? nil : accessPresentation.tone.systemImage,
                    tone: accessPresentation.tone.settingsTone,
                    tint: DS.Colors.brandPrimary,
                    showsBadge: false,
                    trailingSystemImage: accessAction == nil ? nil : "chevron.right",
                    action: accessAction
                )
            }

            // Someone who opens About is checking who wrote this and whether
            // the permission claim holds. The rows are ordered as that check
            // runs: who, where they publish, how to reach them, and the source
            // that makes the claim verifiable rather than a promise.
            Section {
                KikiSettingsLinkRow(
                    title: appLanguage.string("Made by"),
                    value: ExternalLinks.developerName,
                    urlString: ExternalLinks.developerURL,
                    systemImage: "person"
                )
                KikiSettingsLinkRow(
                    title: appLanguage.string("Website"),
                    value: ExternalLinks.websiteDisplayName,
                    urlString: ExternalLinks.officialURL,
                    systemImage: "globe"
                )
                KikiSettingsCopyRow(
                    title: appLanguage.string("Email"),
                    value: ExternalLinks.contactEmailAddress,
                    systemImage: "envelope"
                )
                KikiSettingsLinkRow(
                    title: appLanguage.string("Source"),
                    value: ExternalLinks.repositoryDisplayName,
                    urlString: ExternalLinks.githubURL,
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
            } footer: {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    KikiSettingsHelperText(
                        appLanguage.string("Open source under MIT. Command Reopen needs no system permissions — and you can check that in the source rather than take our word for it.")
                    )
                    if let copyright = aboutMetadata.copyright, !copyright.isEmpty {
                        Text(copyright)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
                    }
                )
            } header: {
                Text(appLanguage.string("Developer Testing"))
            } footer: {
                KikiSettingsHelperText(appLanguage.string("Debug only. Live clears the Pro access override."))
            }
#endif
        }
    }

    private var aboutMetadata: KikiAppMetadata { .bundle() }

    private var accessAction: (@MainActor () -> Void)? {
        guard accessController.distributionChannel == .appStore else { return nil }
        return { route.presentPaywall() }
    }

    private var accessPresentation: KikiAccessStatusPresentation {
        let language = AppLanguage.shared
#if APPSTORE
        switch accessModel.readiness {
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
        return KikiAccessStatusPresentation(
            tone: .active,
            title: language.string(localized: "Community edition"),
            subtitle: language.string(localized: "Free and fully featured for the community."),
            actionTitle: nil
        )
#endif
    }

#if APPSTORE
    private func localizedPlanTitle(for plan: KikiAccessPlan) -> String {
        switch plan.commercePlan {
        case .yearly: appLanguage.string("Yearly")
        case .lifetime: appLanguage.string("Lifetime")
        default: plan.title
        }
    }

    private func localizedPlanBillingDetail(for plan: KikiAccessPlan) -> String {
        switch plan.commercePlan {
        case .yearly: appLanguage.string("per year")
        case .lifetime: appLanguage.string("once")
        default: plan.billingDetail
        }
    }
#endif
}
