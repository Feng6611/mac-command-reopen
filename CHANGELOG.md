# Changelog

## [1.0.0] - 2025-xx-xx

### Added
- Smart window detection: skip reopen when app already has visible windows
- Expanded system app filter (Spotlight, Control Center, Notification Center, etc.)
- Localization: English, Simplified Chinese, Japanese
- App Sandbox support for App Store distribution
- Privacy manifest (PrivacyInfo.xcprivacy)

### Changed
- Increased activation evaluation delay for better Cmd+Tab sweep handling
- Refactored system app blacklist into a clean Set-based lookup

### Fixed
- Reduced unnecessary reopen calls for apps with existing windows

## [0.7.0] - 2025-xx-xx
- Removed window detection, simplified logic

## [0.2.0] - 2025-xx-xx  
- Initial public release
