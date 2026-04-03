//
//  OnboardingView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import SwiftUI

struct OnboardingView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

            Spacer().frame(height: 20)

            Text("Welcome to Command Reopen")
                .font(.system(size: 22, weight: .bold))

            Spacer().frame(height: 8)

            Text("Never lose your windows again.\nSwitch apps with Cmd+Tab, windows reopen automatically.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Feature list
            VStack(alignment: .leading, spacing: 16) {
                onboardingFeature(
                    icon: "command",
                    color: .accentColor,
                    title: "Smart Window Reopen",
                    description: "Detects when you Cmd+Tab to an app with no visible window and reopens it."
                )
                onboardingFeature(
                    icon: "hand.raised",
                    color: .orange,
                    title: "Per-App Control",
                    description: "Exclude specific apps that you don't want to auto-reopen."
                )
                onboardingFeature(
                    icon: "chart.bar",
                    color: .purple,
                    title: "Usage Insights",
                    description: "Track how often Command Reopen helps you across different apps."
                )
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 36)

            // Trial callout
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                Text("7-day free trial, no commitment")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
            )

            Spacer().frame(height: 24)

            // CTA
            Button {
                onGetStarted()
            } label: {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 28)
        }
        .frame(width: 440, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func onboardingFeature(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(1)
            }
        }
    }
}

// MARK: - Window Controller

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func showIfNeeded(proStatusManager: ProStatusManager) {
        guard proStatusManager.isFirstLaunch else { return }
        show(proStatusManager: proStatusManager)
    }

    func show(proStatusManager: ProStatusManager) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = OnboardingView {
            proStatusManager.startTrial()
            self.close()
        }

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome"
        window.delegate = self
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 440, height: 560))
        window.center()

        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
