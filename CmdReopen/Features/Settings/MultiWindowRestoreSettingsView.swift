import AppKit
import KikiDesign
import KikiSettings
import SwiftUI

struct MultiWindowRestoreSettingsView: View {
    @EnvironmentObject private var settings: AppleEventWindowRestoreSettings
    @EnvironmentObject private var appLanguage: AppLanguage
    @State private var pendingBundleIdentifiers: Set<String> = []

    var body: some View {
        KikiSettingsPane {
            Section {
                ForEach(AppleEventWindowRestoreRegistry.supportedApps) { app in
                    appRow(app)
                }
            } header: {
                Text(appLanguage.string("Restore every minimized window"))
            } footer: {
                KikiSettingsHelperText(
                    appLanguage.string("Standard Reopen stays on by default. Enable this optional enhancement for each app that should restore all of its minimized windows.")
                )
            }

            if hasAuthorizationDenial {
                Section {
                    Button(appLanguage.string("Open Automation Settings")) {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
                        NSWorkspace.shared.open(url)
                    }
                } footer: {
                    KikiSettingsHelperText(
                        appLanguage.string("Command Reopen needs Automation access only for apps you enable here.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func appRow(_ app: AppleEventWindowRestoreApp) -> some View {
        let isInstalled = applicationURL(for: app) != nil
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.md) {
                appIcon(for: app)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                    if !isInstalled {
                        Text(appLanguage.string("Not installed"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if pendingBundleIdentifiers.contains(app.bundleIdentifier) {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("", isOn: toggleBinding(for: app))
                    .labelsHidden()
                    .disabled(!isInstalled || pendingBundleIdentifiers.contains(app.bundleIdentifier))
            }

            if let status = statusText(for: app) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleBinding(for app: AppleEventWindowRestoreApp) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(bundleIdentifier: app.bundleIdentifier) },
            set: { newValue in
                pendingBundleIdentifiers.insert(app.bundleIdentifier)
                Task { @MainActor in
                    _ = await settings.setEnabled(newValue, bundleIdentifier: app.bundleIdentifier)
                    pendingBundleIdentifiers.remove(app.bundleIdentifier)
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

    private func statusText(for app: AppleEventWindowRestoreApp) -> String? {
        switch settings.lastResultByBundleIdentifier[app.bundleIdentifier] {
        case .authorizationDenied:
            return appLanguage.string("Access was denied. Allow Command Reopen in Automation settings, then try again.")
        case .targetNotRunning:
            return appLanguage.string("Open this app first, then enable it again.")
        case .failed(let errorNumber):
            return appLanguage.string("Authorization failed (error \(errorNumber)).")
        case .enabled:
            return appLanguage.string("Automation access granted.")
        case .disabled, .none:
            return nil
        }
    }

    private var hasAuthorizationDenial: Bool {
        settings.lastResultByBundleIdentifier.values.contains(.authorizationDenied)
    }
}
