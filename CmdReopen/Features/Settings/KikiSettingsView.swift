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
        case .general: "General"
        case .statistics: "Stats"
        case .about: "About"
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
            PaywallSheetView(accessModel: accessModel, context: .settings)
        }
#endif
    }

    private var aboutPane: some View {
        KikiStandardAboutPane(
            metadata: .bundle(),
            accessStatus: accessPresentation,
            onAccessAction: accessAction,
            links: KikiStandardAboutLinks(
                website: URL(string: ExternalLinks.officialURL),
                feedback: URL(string: ExternalLinks.contactEmail),
                github: URL(string: ExternalLinks.githubURL)
            ),
            tint: DS.Colors.brandPrimary
        )
    }

    private var accessAction: (@MainActor () -> Void)? {
        guard accessController.distributionChannel == .appStore else { return nil }
        return { route.isPaywallSheetPresented = true }
    }

    private var accessPresentation: KikiAccessStatusPresentation {
#if APPSTORE
        switch accessModel.status {
        case .notStarted:
            return KikiAccessStatusPresentation(
                tone: .neutral,
                title: "Trial not started",
                subtitle: "Start the free trial when you are ready.",
                actionTitle: "View options"
            )
        case .trial(.time(let daysRemaining, _)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left",
                subtitle: "Command Reopen Pro is active during the trial.",
                actionTitle: "View plans"
            )
        case .trial(.usage(_, let used, let limit)):
            return KikiAccessStatusPresentation(
                tone: .trial,
                title: "\(max(0, limit - used)) uses left",
                subtitle: "Command Reopen Pro is active during the trial.",
                actionTitle: "View plans"
            )
        case .expired:
            return KikiAccessStatusPresentation(
                tone: .expired,
                title: "Trial ended",
                subtitle: "Upgrade to continue automatic window reopening.",
                actionTitle: "Upgrade"
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
            title: "Direct version",
            subtitle: "All Command Reopen features are available.",
            actionTitle: nil
        )
#endif
    }
}
