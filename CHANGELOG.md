# Changelog

## [1.0.0] - 2025-xx-xx

### Added
- Smart activation tracking: skip reopen when rapidly switching back to an app
- User-configurable exclude list for specific apps
- Expanded system app filter (Spotlight, Control Center, Notification Center, etc.)
- Localization: English, Simplified Chinese, Japanese
- App Sandbox support for App Store distribution
- Privacy manifest (PrivacyInfo.xcprivacy)
- Privacy policy (PRIVACY.md)

### Changed
- Increased activation evaluation delay for better Cmd+Tab sweep handling
- Refactored system app blacklist into a clean Set-based lookup

## [0.7.0] - 2025-xx-xx
- Removed window detection, simplified logic

## [0.2.0] - 2025-xx-xx
- Initial public release
