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
        // Sized here as well as on the window controller: the SwiftUI ideal is
        // what the Settings window settles at, so the AppKit side alone leaves
        // the pane at Kiki's generic default height.
        KikiSettingsCoordinatorView(
            coordinator: SettingsWindowController.shared.coordinator,
            width: DS.Window.settingsWidth,
            height: DS.Window.settingsHeight,
            minimumWidth: DS.Window.settingsWidth,
            minimumHeight: DS.Window.settingsMinimumHeight
        ) { tab in
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
        .sheet(isPresented: $route.isMacShortcutsPresented) {
            MacShortcutsSheet()
        }
#if APPSTORE
        .sheet(isPresented: $route.isPaywallSheetPresented) {
            PaywallSheetView(
                accessModel: accessModel,
                context: .settings,
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
                TrialExitOfferView(accessModel: accessModel, offer: offer)
            }
        }
#if DEBUG
        .sheet(isPresented: $route.isTrialExitOfferDebugPreviewPresented) {
            TrialExitOfferView(
                accessModel: accessModel,
                offer: .debugPreview,
                marksOfferShown: false
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
                standardAboutStatusRow
#if APPSTORE
                // The same banner General shows, rather than a second design
                // for the same state: one offer, one way it looks, wherever
                // the user meets it.
                WinbackOfferRow(accessModel: accessModel) {
                    route.presentTrialExitOffer()
                }
#endif
            }
#if !APPSTORE
            Section {
                DirectSupportCardRow()
            }
#else
            // Each edition puts its one ask in the same slot, directly under
            // the status it follows from: the free build asks for a purchase,
            // the paid build asks for feedback. Below the contact section it
            // would sit after that section's footer, and a footer reads as the
            // end of the pane rather than a divider before more content.
            Section {
                FeedbackOfferCardRow()
            }
#endif

            // The left side identifies the destination; only the right-side
            // value and action icon are interactive.
            Section {
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
