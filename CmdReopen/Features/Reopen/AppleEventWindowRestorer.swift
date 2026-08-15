import AppKit
import ApplicationServices
import Combine
import Foundation

enum AppleEventWindowRestoreCapability: Equatable {
    case restoreAllMinimizedWindows
    case focusOnly
    case unsupported
}

struct AppleEventWindowRestoreAdapter: Equatable {
    enum Strategy: Equatable {
        case setMinimizedProperty(String)
        case activateEveryWindow(command: String)
    }

    let bundleIdentifier: String
    let strategy: Strategy

    var scriptSource: String {
        switch strategy {
        case .setMinimizedProperty(let minimizedProperty):
            return """
            with timeout of 3 seconds
                tell application id "\(bundleIdentifier)"
                    set minimizedWindows to every window whose \(minimizedProperty) is true
                    set restoredCount to count of minimizedWindows
                    repeat with targetWindow in minimizedWindows
                        set \(minimizedProperty) of targetWindow to false
                    end repeat
                    return restoredCount
                end tell
            end timeout
            """
        case .activateEveryWindow(let command):
            return """
            with timeout of 3 seconds
                tell application id "\(bundleIdentifier)"
                    set targetWindows to every window
                    set restoredCount to count of targetWindows
                    repeat with targetWindow in targetWindows
                        \(command) targetWindow
                    end repeat
                    return restoredCount
                end tell
            end timeout
            """
        }
    }
}

struct AppleEventWindowRestoreApp: Identifiable, Equatable {
    let name: String
    let bundleIdentifier: String

    var id: String { bundleIdentifier }
}

enum AppleEventWindowRestoreRegistry {
    static let supportedApps: [AppleEventWindowRestoreApp] = [
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
        .init(name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        .init(name: "Preview", bundleIdentifier: "com.apple.Preview"),
        .init(name: "iTerm2", bundleIdentifier: "com.googlecode.iterm2"),
        .init(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty")
    ]

    private static let adaptersByBundleIdentifier: [String: AppleEventWindowRestoreAdapter] = [
        "com.apple.Safari": .init(bundleIdentifier: "com.apple.Safari", strategy: .setMinimizedProperty("miniaturized")),
        "com.google.Chrome": .init(bundleIdentifier: "com.google.Chrome", strategy: .setMinimizedProperty("minimized")),
        "com.apple.Terminal": .init(bundleIdentifier: "com.apple.Terminal", strategy: .setMinimizedProperty("miniaturized")),
        "com.apple.Preview": .init(bundleIdentifier: "com.apple.Preview", strategy: .setMinimizedProperty("miniaturized")),
        "com.googlecode.iterm2": .init(bundleIdentifier: "com.googlecode.iterm2", strategy: .setMinimizedProperty("miniaturized")),
        "com.mitchellh.ghostty": .init(bundleIdentifier: "com.mitchellh.ghostty", strategy: .activateEveryWindow(command: "activate window"))
    ]

    private static let focusOnlyBundleIdentifiers: Set<String> = [
        "company.thebrowser.dia",
        "company.thebrowser.Browser"
    ]

    static func adapter(for bundleIdentifier: String) -> AppleEventWindowRestoreAdapter? {
        adaptersByBundleIdentifier[bundleIdentifier]
    }

    static func capability(for bundleIdentifier: String) -> AppleEventWindowRestoreCapability {
        if adaptersByBundleIdentifier[bundleIdentifier] != nil { return .restoreAllMinimizedWindows }
        if focusOnlyBundleIdentifiers.contains(bundleIdentifier) { return .focusOnly }
        return .unsupported
    }
}

enum AppleEventAutomationAuthorizationResult: Equatable {
    case authorized
    case denied
    case targetNotRunning
    case failed(errorNumber: Int)
}

protocol AppleEventAutomationAuthorizing: AnyObject {
    func requestAuthorization(bundleIdentifier: String) async -> AppleEventAutomationAuthorizationResult
}

final class SystemAppleEventAutomationAuthorizer: AppleEventAutomationAuthorizing {
    func requestAuthorization(bundleIdentifier: String) async -> AppleEventAutomationAuthorizationResult {
        guard let processIdentifier = await Self.resolveProcessIdentifier(
            bundleIdentifier: bundleIdentifier
        ) else {
            return .targetNotRunning
        }

        let status = await Self.determinePermission(processIdentifier: processIdentifier)

        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent):
            return .denied
        case OSStatus(procNotFound):
            return .targetNotRunning
        default:
            return .failed(errorNumber: Int(status))
        }
    }

    /// Automation permission is addressed to a live process. If the app is not
    /// running yet, launch it without activation so enabling the toggle does not
    /// make the user leave Settings and open the target by hand.
    private static func resolveProcessIdentifier(bundleIdentifier: String) async -> pid_t? {
        if let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            return runningApplication.processIdentifier
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, _ in
                continuation.resume(returning: application?.processIdentifier)
            }
        }
    }

    private static func determinePermission(processIdentifier: pid_t) async -> OSStatus {
        await Task.detached(priority: .userInitiated) {
            let descriptor = NSAppleEventDescriptor(processIdentifier: processIdentifier)
            guard let address = descriptor.aeDesc else { return OSStatus(paramErr) }
            return AEDeterminePermissionToAutomateTarget(
                address,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                true
            )
        }.value
    }
}

enum AppleEventWindowRestoreSettingResult: Equatable {
    case enabled
    case disabled
    case authorizationDenied
    case targetNotRunning
    case failed(errorNumber: Int)
}

@MainActor
final class AppleEventWindowRestoreSettings: ObservableObject {
    static let shared = AppleEventWindowRestoreSettings()

    @Published private(set) var enabledBundleIdentifiers: Set<String>
    @Published private(set) var lastResultByBundleIdentifier: [String: AppleEventWindowRestoreSettingResult] = [:]

    private let defaults: UserDefaults
    private let authorizer: AppleEventAutomationAuthorizing

    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, authorizer: SystemAppleEventAutomationAuthorizer())
    }

    init(defaults: UserDefaults, authorizer: AppleEventAutomationAuthorizing) {
        self.defaults = defaults
        self.authorizer = authorizer
        enabledBundleIdentifiers = Set(
            defaults.stringArray(forKey: AppDefaults.RawKey.appleEventWindowRestoreEnabledBundleIDs) ?? []
        )
    }

    func isEnabled(bundleIdentifier: String) -> Bool {
        enabledBundleIdentifiers.contains(bundleIdentifier)
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool, bundleIdentifier: String) async -> AppleEventWindowRestoreSettingResult {
        guard isEnabled else {
            enabledBundleIdentifiers.remove(bundleIdentifier)
            persist()
            lastResultByBundleIdentifier[bundleIdentifier] = .disabled
            return .disabled
        }

        let authorization = await authorizer.requestAuthorization(bundleIdentifier: bundleIdentifier)
        let result: AppleEventWindowRestoreSettingResult
        switch authorization {
        case .authorized:
            enabledBundleIdentifiers.insert(bundleIdentifier)
            persist()
            result = .enabled
        case .denied:
            result = .authorizationDenied
        case .targetNotRunning:
            result = .targetNotRunning
        case .failed(let errorNumber):
            result = .failed(errorNumber: errorNumber)
        }
        lastResultByBundleIdentifier[bundleIdentifier] = result
        return result
    }

    private func persist() {
        defaults.set(
            Array(enabledBundleIdentifiers).sorted(),
            forKey: AppDefaults.RawKey.appleEventWindowRestoreEnabledBundleIDs
        )
    }
}

enum AppleScriptExecutionResult: Equatable {
    case success(integerResult: Int)
    case failure(errorNumber: Int, message: String)
}

protocol AppleScriptExecuting: AnyObject {
    func execute(source: String) -> AppleScriptExecutionResult
}

final class NSAppleScriptExecutor: AppleScriptExecuting {
    func execute(source: String) -> AppleScriptExecutionResult {
        guard let script = NSAppleScript(source: source) else {
            return .failure(errorNumber: -1, message: "Unable to create AppleScript.")
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let errorNumber = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? -1
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String ?? "AppleScript execution failed."
            return .failure(errorNumber: errorNumber, message: message)
        }
        return .success(integerResult: Int(descriptor.int32Value))
    }
}

enum AppleEventWindowRestoreResult: Equatable {
    case restored(windowCount: Int)
    case disabled
    case noMinimizedWindows
    case unsupported(AppleEventWindowRestoreCapability)
    case permissionDenied(errorNumber: Int)
    case failed(errorNumber: Int, message: String)
}

protocol AppleEventWindowRestoring: AnyObject {
    func restoreMinimizedWindows(bundleIdentifier: String) -> AppleEventWindowRestoreResult
}

final class AppleEventWindowRestorer: AppleEventWindowRestoring {
    private static let permissionDeniedErrorNumbers: Set<Int> = [-1743, -10004]

    private let executor: AppleScriptExecuting
    private let isEnabled: (String) -> Bool
    private var permissionDeniedBundleIdentifiers: Set<String> = []

    init(
        executor: AppleScriptExecuting = NSAppleScriptExecutor(),
        isEnabled: @escaping (String) -> Bool = { bundleIdentifier in
            UserDefaults.standard.stringArray(
                forKey: AppDefaults.RawKey.appleEventWindowRestoreEnabledBundleIDs
            )?.contains(bundleIdentifier) == true
        }
    ) {
        self.executor = executor
        self.isEnabled = isEnabled
    }

    func restoreMinimizedWindows(bundleIdentifier: String) -> AppleEventWindowRestoreResult {
        guard isEnabled(bundleIdentifier) else { return .disabled }
        let capability = AppleEventWindowRestoreRegistry.capability(for: bundleIdentifier)
        guard let adapter = AppleEventWindowRestoreRegistry.adapter(for: bundleIdentifier) else {
            return .unsupported(capability)
        }
        if permissionDeniedBundleIdentifiers.contains(bundleIdentifier) {
            return .permissionDenied(errorNumber: -1743)
        }

        switch executor.execute(source: adapter.scriptSource) {
        case .success(let integerResult):
            return integerResult > 0 ? .restored(windowCount: integerResult) : .noMinimizedWindows
        case .failure(let errorNumber, let message):
            guard Self.permissionDeniedErrorNumbers.contains(errorNumber) else {
                return .failed(errorNumber: errorNumber, message: message)
            }
            permissionDeniedBundleIdentifiers.insert(bundleIdentifier)
            return .permissionDenied(errorNumber: errorNumber)
        }
    }
}

enum WindowRestoreRouting {
    enum Action: Equatable {
        case recordAutomationSuccess(windowCount: Int)
        case useNativeReopen
    }

    static func action(for result: AppleEventWindowRestoreResult) -> Action {
        switch result {
        case .restored(let windowCount):
            return .recordAutomationSuccess(windowCount: windowCount)
        case .disabled, .noMinimizedWindows, .unsupported, .permissionDenied, .failed:
            return .useNativeReopen
        }
    }
}
