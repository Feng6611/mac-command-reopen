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
                    appLanguage.string("Return Focus to Previous App"),
                    isOn: activationMonitor.automaticSwitcherReorderingBinding,
                    systemImage: "arrow.uturn.backward"
                )
                .disabled(isFeatureLocked || !activationMonitor.isFeatureEnabled)
            } header: {
                Text(appLanguage.string("When No Windows Remain"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("When you close or minimize an app’s last window, automatically hand focus back to the previous app so Cmd+Tab can bring it right back.")
                )
            }

            Section {
                ForEach(AppleEventWindowRestoreRegistry.supportedApps) { app in
                    appRow(app)
                }
            } header: {
                Text(appLanguage.string("Restore All Windows at Once"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("Standard reopen brings back the main window. Enable an app below to restore every minimized window in your Dock at once using macOS Automation.")
                )
            }

            Section {
                Button(appLanguage.string("Open Automation Settings…")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
                    NSWorkspace.shared.open(url)
                }
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("If an app stops restoring, check macOS System Settings > Privacy & Security > Automation.")
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
