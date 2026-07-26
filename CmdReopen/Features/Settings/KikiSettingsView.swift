import KikiSettings
import SwiftUI
#if APPSTORE
import KikiCommerceCore
#endif

enum SettingsTab: Int, CaseIterable, Hashable {
    case general
    case statistics
    case about

    static func visibleTabs(showProTab: Bool) -> [SettingsTab] {
        allCases
    }

    func title(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: String(localized: "General")
        case .statistics: String(localized: "Stats", comment: "Settings tab title; short form of Statistics.")
        case .about: String(localized: "About")
        }
    }

    func icon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: "gearshape"
        case .statistics: "chart.bar.xaxis"
        case .about: "info.circle"
        }
    }

    static var kikiTabs: [KikiSettingsTabSpec<SettingsTab>] {
        allCases.map { tab in
            KikiSettingsTabSpec(
                tab,
                title: tab.title(for: .current),
                systemImage: tab.icon(for: .current)
            )
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var accessController: AppAccessController
    @ObservedObject private var route = SettingsNavigationModel.shared
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
#if APPSTORE
        .sheet(isPresented: $route.isPaywallSheetPresented) {
            PaywallSheetView(
                accessModel: accessModel,
                context: .settings,
                source: route.paywallSource,
                onPurchaseCompleted: {
                    _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .purchaseCompleted)
                }
            )
        }
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
                    title: "Status",
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

            Section {
                ForEach(aboutLinks.orderedLinks) { link in
                    aboutLinkRow(link)
                }
                if let copyright = aboutMetadata.copyright, !copyright.isEmpty {
                    Text(copyright)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    }
                )
            } header: {
                Text("Developer Testing")
            } footer: {
                KikiSettingsHelperText("Debug only. Live clears the Pro access override.")
            }
#endif
        }
    }

    private var aboutMetadata: KikiAppMetadata { .bundle() }

    private var aboutLinks: KikiStandardAboutLinks {
        KikiStandardAboutLinks(
            website: URL(string: ExternalLinks.officialURL),
            feedback: URL(string: ExternalLinks.contactEmail),
            github: URL(string: ExternalLinks.githubURL)
        )
    }

    @ViewBuilder
    private func aboutLinkRow(_ link: KikiStandardAboutLink) -> some View {
        switch link.kind {
        case .link:
            KikiSettingsLinkRow(
                title: link.title,
                value: link.value,
                urlString: link.url.absoluteString,
                systemImage: link.systemImage ?? "link"
            )
        case .copy:
            KikiSettingsCopyRow(
                title: link.title,
                value: link.value,
                systemImage: link.systemImage ?? "envelope"
            )
        }
    }

    private var accessAction: (@MainActor () -> Void)? {
        guard accessController.distributionChannel == .appStore else { return nil }
        return { route.presentPaywall() }
    }

    private var accessPresentation: KikiAccessStatusPresentation {
#if APPSTORE
        switch accessModel.readiness {
        case .idle, .loading:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: String(localized: "Checking purchases…"),
                subtitle: String(localized: "Verifying your Command Reopen Pro access."),
                actionTitle: nil
            )
        case .degraded:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: String(localized: "Purchases unavailable"),
                subtitle: String(localized: "We couldn't verify your purchase status. Try again when you're online."),
                actionTitle: String(localized: "View options")
            )
        case .ready:
            break
        }

        switch accessModel.status {
        case .notStarted:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: String(localized: "Trial not started"),
                subtitle: String(localized: "Start the free trial when you are ready."),
                actionTitle: String(localized: "View options")
            )
        case .trial(.time(let daysRemaining, _)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: String(localized: "\(daysRemaining) days left", comment: "Trial time remaining in the About pane; plural-aware in the catalog."),
                subtitle: String(localized: "Command Reopen Pro is active during the trial."),
                actionTitle: String(localized: "View plans")
            )
        case .trial(.usage(_, let used, let limit)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: String(localized: "\(max(0, limit - used)) uses left", comment: "Trial usage remaining in the About pane; plural-aware in the catalog."),
                subtitle: String(localized: "Command Reopen Pro is active during the trial."),
                actionTitle: String(localized: "View plans")
            )
        case .expired:
            return KikiAccessStatusPresentation(
                tone: .expired,
                title: String(localized: "Trial ended"),
                subtitle: String(localized: "Upgrade to continue automatic window reopening."),
                actionTitle: String(localized: "Upgrade")
            )
        case .pro(let plan, _):
            return KikiAccessStatusPresentation(
                tone: .active,
                title: plan.title,
                subtitle: plan.billingDetail,
                actionTitle: "View plans"
            )
        }
#else
        return KikiAccessStatusPresentation(
            tone: .active,
            title: String(localized: "Direct version"),
            subtitle: String(localized: "All Command Reopen features are available."),
            actionTitle: nil
        )
#endif
    }
}
