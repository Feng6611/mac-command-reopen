import AppKit
import KikiDesign
import KikiSettings
import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var settings: AppleEventWindowRestoreSettings
    @EnvironmentObject private var appLanguage: AppLanguage

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
    }

    var body: some View {
        KikiSettingsPane {
            Section {
                KikiSettingsToggleRow(
                    appLanguage.string("Return to Previous App"),
                    isOn: activationMonitor.automaticSwitcherReorderingBinding,
                    systemImage: "arrow.uturn.backward"
                )
                .disabled(isFeatureLocked || !activationMonitor.isFeatureEnabled)
            } header: {
                Text(appLanguage.string("After the Last Window Disappears"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("Closing or minimizing an app’s last window leaves it frontmost with nothing on screen. Command Reopen hands focus back — one Cmd+Tab still returns you.")
                )
            }

            Section {
                ForEach(AppleEventWindowRestoreRegistry.supportedApps) { app in
                    appRow(app)
                }
            } header: {
                Text(appLanguage.string("Restore All Minimized Windows"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("Cmd+Tab back to an app and macOS leaves your minimized windows in the Dock. Turn one on to bring all of its windows back automatically.")
                )
            }

            Section {
                Button(appLanguage.string("Open Automation Settings")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
                    NSWorkspace.shared.open(url)
                }
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("macOS has no direct way to reopen another app’s minimized windows, so Command Reopen uses Automation to control each app you enable. Access is requested only for apps you turn on.")
                )
            }
        }
    }

    @ViewBuilder
    private func appRow(_ app: AppleEventWindowRestoreApp) -> some View {
        let isInstalled = applicationURL(for: app) != nil
        HStack(spacing: DS.Spacing.md) {
            appIcon(for: app)
            Text(app.name)
                .foregroundStyle(isInstalled ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: toggleBinding(for: app))
                .labelsHidden()
                .disabled(!isInstalled || isFeatureLocked)
        }
        .padding(.vertical, 2)
    }

    private func toggleBinding(for app: AppleEventWindowRestoreApp) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(bundleIdentifier: app.bundleIdentifier) },
            set: { newValue in
                Task { @MainActor in
                    _ = await settings.setEnabled(newValue, bundleIdentifier: app.bundleIdentifier)
                }
            }
        )
    }

    @ViewBuilder
    private func appIcon(for app: AppleEventWindowRestoreApp) -> some View {
        if let url = applicationURL(for: app) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    private func applicationURL(for app: AppleEventWindowRestoreApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
    }

}
