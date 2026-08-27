import Combine
import Defaults
import Foundation

/// App-owned policy for the Direct build's opt-in Accessibility behavior.
/// Kiki supplies the permission mechanism, but not these product choices.
final class AdvancedWindowRestoreSettings: ObservableObject {
    static let shared = AdvancedWindowRestoreSettings()

    @Published var isAdvancedModeEnabled: Bool {
        didSet {
            guard isAdvancedModeEnabled != oldValue else { return }
            defaults[AppDefaults.advancedWindowRestoreEnabled] = isAdvancedModeEnabled
        }
    }

    @Published var restoresAllWindows: Bool {
        didSet {
            guard restoresAllWindows != oldValue else { return }
            defaults[AppDefaults.advancedWindowRestoreAllWindows] = restoresAllWindows
        }
    }

    @Published var cyclesWindowsFromDockClick: Bool {
        didSet {
            guard cyclesWindowsFromDockClick != oldValue else { return }
            defaults[AppDefaults.advancedWindowRestoreDockClickCycle] = cyclesWindowsFromDockClick
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _isAdvancedModeEnabled = Published(initialValue: defaults[AppDefaults.advancedWindowRestoreEnabled])
        _restoresAllWindows = Published(initialValue: defaults[AppDefaults.advancedWindowRestoreAllWindows])
        _cyclesWindowsFromDockClick = Published(initialValue: defaults[AppDefaults.advancedWindowRestoreDockClickCycle])
    }
}
