//
//  SettingsComponents.swift
//  CmdReopen
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
