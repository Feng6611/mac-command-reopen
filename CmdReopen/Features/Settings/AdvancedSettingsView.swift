#if DIRECT
import AppKit
import KikiAuthorization
#endif
import KikiSettings
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var appLanguage: AppLanguage
#if DIRECT
    @EnvironmentObject private var settings: AdvancedWindowRestoreSettings
    @State private var isAccessibilityAuthorized = false
#endif

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
    }

    var body: some View {
#if DIRECT
        KikiSettingsPane {
            Section {
                KikiAuthorizationStatusRow(
                    title: appLanguage.string("Accessibility"),
                    isAuthorized: isAccessibilityAuthorized,
                    authorizedValue: appLanguage.string("Allowed"),
                    unauthorizedValue: appLanguage.string("Needed"),
                    action: openAccessibilitySetup
                )
            } header: {
                Text(appLanguage.string("Accessibility"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("Advanced window restoration can control other apps’ windows only after you grant Accessibility access. Core Command Reopen needs no permission.")
                )
            }

            Section {
                KikiSettingsToggleRow(
                    appLanguage.string("Use Advanced Window Restore"),
                    isOn: $settings.isAdvancedModeEnabled,
                    systemImage: "accessibility"
                )
                .disabled(isFeatureLocked || !isAccessibilityAuthorized)

                KikiSettingsToggleRow(
                    appLanguage.string("Restore All Minimized Windows"),
                    isOn: $settings.restoresAllWindows,
                    systemImage: "macwindow.on.rectangle"
                )
                .disabled(isFeatureLocked || !settings.isAdvancedModeEnabled || !isAccessibilityAuthorized)

                KikiSettingsToggleRow(
                    appLanguage.string("Cycle Windows from Dock Click"),
                    isOn: $settings.cyclesWindowsFromDockClick,
                    systemImage: "dock.rectangle"
                )
                .disabled(isFeatureLocked || !settings.isAdvancedModeEnabled || !isAccessibilityAuthorized)
            } header: {
                Text(appLanguage.string("Advanced Mode"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("When enabled, Command Reopen uses Accessibility to raise a window. Restore All brings back every minimized window. Dock Click Cycling minimizes a frontmost app, restores all minimized windows, and leaves background app activation native.")
                )
            }
        }
        .onAppear(perform: refreshAccessibilityAuthorization)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            refreshAccessibilityAuthorization()
        }

#else
        EmptyView()
#endif
    }

#if DIRECT
    private func openAccessibilitySetup() {
        _ = KikiAuthorizationPanel.accessibility.requestSystemPrompt()
        refreshAccessibilityAuthorization()
        guard !isAccessibilityAuthorized else { return }
        KikiAuthorizationAssistant.shared.present(
            panel: .accessibility,
            instruction: "Turn on Command Reopen in Accessibility to use its optional advanced window restore mode."
        )
    }

    private func refreshAccessibilityAuthorization() {
        isAccessibilityAuthorized = KikiAuthorizationPanel.accessibility.isAuthorized
    }
#endif

}
