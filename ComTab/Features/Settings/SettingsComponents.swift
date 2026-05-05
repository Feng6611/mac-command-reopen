//
//  SettingsComponents.swift
//  ComTab
//
//  Shared settings UI building blocks.
//

import AppKit
import SwiftUI

enum SettingsUI {
    struct FormPane<Content: View>: View {
        private let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            Form {
                content
            }
            .formStyle(.grouped)
        }
    }

    struct LinkButton: View {
        let title: String
        let urlString: String
        var systemImage: String?

        var body: some View {
            Button {
                openURL(urlString)
            } label: {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.link)
        }
    }

    struct ApplicationRow: View {
        let bundleID: String
        let removeAction: (String) -> Void

        private var applicationURL: URL? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }

        private var displayName: String {
            guard let applicationURL else {
                return bundleID
            }

            return FileManager.default.displayName(atPath: applicationURL.path)
        }

        var body: some View {
            HStack(spacing: DS.Spacing.sm) {
                icon

                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .help(bundleID)

                Spacer(minLength: 0)

                Button {
                    removeAction(bundleID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove \(displayName)")
                .accessibilityLabel("Remove \(displayName)")
            }
        }

        @ViewBuilder
        private var icon: some View {
            if let applicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
        }
    }

    struct ApplicationPicker<Applications: RandomAccessCollection>: View where Applications.Element == NSRunningApplication {
        let applications: Applications
        @Binding var selection: String?
        let isDisabled: Bool
        let addAction: (String) -> Void

        var body: some View {
            HStack {
                Picker(selection: $selection) {
                    Text("Select an app...").tag(String?.none)
                    ForEach(Array(applications), id: \.bundleIdentifier) { application in
                        if let bundleID = application.bundleIdentifier {
                            Text(application.localizedName ?? bundleID)
                                .tag(Optional(bundleID))
                        }
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(isDisabled)

                Button("Add") {
                    guard let selection else {
                        return
                    }

                    addAction(selection)
                    self.selection = nil
                }
                .disabled(selection == nil || isDisabled)
            }
        }
    }

    static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

extension View {
    func settingDescription() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
    }
}
