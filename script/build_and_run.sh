#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Command Reopen"
BUNDLE_ID="com.dev.kkuk.CommandReopen"
PROJECT_NAME="CmdReopen.xcodeproj"
SCHEME_NAME="CmdReopen-MAS"
TEAM_ID="Q3DZRXLGA3"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/AppleSandboxDerivedData"
PRODUCTS_DIR="$DERIVED_DATA_DIR/Build/Products/Debug"
APP_BUNDLE="$PRODUCTS_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

pkill -TERM -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME$" >/dev/null 2>&1 || true

xcodebuild \
  -quiet \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG APPSTORE APPLE_SANDBOX" \
TARGET_BUILD_DIR="$PRODUCTS_DIR" \
INFOPLIST_PATH="$APP_NAME.app/Contents/Info.plist" \
  "$ROOT_DIR/scripts/verify_appstore_configuration.sh"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)"
if [[ "$SIGNING_DETAILS" != *"Identifier=$BUNDLE_ID"* ||
      "$SIGNING_DETAILS" != *"TeamIdentifier=$TEAM_ID"* ||
      "$SIGNING_DETAILS" == *"Signature=adhoc"* ]]; then
  echo "error: Debug must be Apple Development-signed with the expected bundle and team before Apple Sandbox launch." >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build|--build)
    ;;
  run)
    open_app
    ;;
  debug|--debug)
    lldb -- "$APP_BINARY"
    ;;
  logs|--logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry|--telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify|--verify)
    open_app
    sleep 1
    pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
