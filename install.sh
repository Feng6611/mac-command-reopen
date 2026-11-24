#!/usr/bin/env bash
# Command Reopen installer (free Direct build).
#
#   curl -fsSL https://raw.githubusercontent.com/Feng6611/mac-command-reopen/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --version 1.5.5
#   curl -fsSL .../install.sh | bash -s -- --uninstall
#
# Options:
#   --version X.Y.Z   install that release instead of the latest
#   --dmg PATH        install from a local DMG (testing); also CMDREOPEN_DMG=PATH
#   --app-dir DIR     install into DIR instead of /Applications; also CMDREOPEN_APP_DIR
#   --no-launch       do not open the app afterwards
#   --force           replace an App Store copy at the same path
#   --uninstall       quit and remove the app
#   --purge           with --uninstall, also remove its preferences and caches
#   -h, --help        show this help
set -euo pipefail

REPO="Feng6611/mac-command-reopen"
APP_NAME="Command Reopen.app"
# Older GitHub builds may sit under this name; an upgrade replaces it.
LEGACY_APP_NAME="Command Reopen Direct.app"
BUNDLE_ID="com.dev.kkuk.CommandReopen.direct"
ASSET="CommandReopen.dmg"

VERSION=""
LOCAL_DMG="${CMDREOPEN_DMG:-}"
APP_DIR="${CMDREOPEN_APP_DIR:-/Applications}"
LAUNCH=1
FORCE=0
MODE="install"
PURGE=0

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() { sed -n '2,17p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   [ $# -ge 2 ] || die "--version needs a value"; VERSION="${2#v}"; shift 2 ;;
    --dmg)       [ $# -ge 2 ] || die "--dmg needs a path"; LOCAL_DMG="$2"; shift 2 ;;
    --app-dir)   [ $# -ge 2 ] || die "--app-dir needs a path"; APP_DIR="$2"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --force)     FORCE=1; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    --purge)     PURGE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "Command Reopen runs on macOS only."
if [ -n "$VERSION" ]; then
  case "$VERSION" in
    *[!0-9.]*|.*|*.) die "invalid version '$VERSION' (expected e.g. 1.5.5)" ;;
  esac
fi

TARGET="$APP_DIR/$APP_NAME"
LEGACY="$APP_DIR/$LEGACY_APP_NAME"
SUDO=""
if [ ! -w "$APP_DIR" ]; then
  if [ ! -d "$APP_DIR" ]; then
    die "$APP_DIR does not exist."
  fi
  warn "$APP_DIR is not writable; sudo will ask for your password."
  SUDO="sudo"
fi

WORK=""
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true; fi
  if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT

bundle_id_of() { /usr/bin/defaults read "$1/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true; }
is_github_build() { [ -d "$1" ] && [ "$(bundle_id_of "$1")" = "$BUNDLE_ID" ]; }

# A GitHub build running from either install path. Matching by path, and only
# for paths that hold the GitHub build, never touches an App Store copy.
is_running() {
  local app
  for app in "$TARGET" "$LEGACY"; do
    is_github_build "$app" && pgrep -if "$app/Contents/MacOS/" >/dev/null 2>&1 && return 0
  done
  return 1
}

quit_app() {
  local app
  is_running || return 0
  info "Quitting Command Reopen…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    is_running || return 0
    sleep 0.5
  done
  for app in "$TARGET" "$LEGACY"; do
    is_github_build "$app" && pkill -if "$app/Contents/MacOS/" >/dev/null 2>&1 || true
  done
  sleep 1
  is_running && die "could not quit Command Reopen; quit it from the menu bar and try again."
  return 0
}

# The App Store copy uses the same file name; never replace it silently. It has
# a receipt and the plain bundle ID, while the GitHub build ends in ".direct".
guard_app_store_copy() {
  [ -d "$TARGET" ] || return 0
  [ "$FORCE" -eq 1 ] && return 0
  if [ -d "$TARGET/Contents/_MASReceipt" ] || ! is_github_build "$TARGET"; then
    die "$TARGET is not the GitHub build (likely the App Store version). Remove it first, or rerun with --force to replace it."
  fi
}

if [ "$MODE" = "uninstall" ]; then
  removed=0
  for app in "$TARGET" "$LEGACY"; do
    [ -d "$app" ] || continue
    if is_github_build "$app" || { [ "$FORCE" -eq 1 ] && [ "$app" = "$TARGET" ]; }; then
      quit_app
      info "Removing $app"
      $SUDO rm -rf "$app"
      ok "Removed $(basename "$app")"
      removed=1
    else
      warn "$app is not the GitHub build (likely the App Store version); leaving it. Use --force to remove it."
    fi
  done
  [ "$removed" -eq 1 ] || warn "Command Reopen (GitHub build) is not installed in $APP_DIR."
  if [ "$PURGE" -eq 1 ]; then
    info "Removing preferences and caches for $BUNDLE_ID"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
           "$HOME/Library/Caches/$BUNDLE_ID" \
           "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
           "$HOME/Library/Application Support/$BUNDLE_ID" \
           "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    ok "Purged local data"
  fi
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cmdreopen.XXXXXX")"

if [ -n "$LOCAL_DMG" ]; then
  [ -f "$LOCAL_DMG" ] || die "DMG not found: $LOCAL_DMG"
  DMG="$LOCAL_DMG"
  info "Using local DMG $DMG"
else
  command -v curl >/dev/null 2>&1 || die "curl is required."
  if [ -n "$VERSION" ]; then
    URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
    info "Downloading Command Reopen $VERSION…"
  else
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
    info "Downloading the latest Command Reopen…"
  fi
  DMG="$WORK/$ASSET"
  curl -fL --progress-bar --retry 3 -o "$DMG" "$URL" \
    || die "download failed: $URL"
fi

info "Mounting disk image"
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -noautoopen -readonly -mountpoint "$MOUNT" -quiet \
  || { MOUNT=""; die "could not mount $DMG"; }
SOURCE="$MOUNT/$APP_NAME"
[ -d "$SOURCE" ] || die "$APP_NAME not found in the disk image."

NEW_VERSION="$(/usr/bin/defaults read "$SOURCE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
OLD_VERSION=""
guard_app_store_copy
for app in "$TARGET" "$LEGACY"; do
  if [ -z "$OLD_VERSION" ] && [ -d "$app" ] && { [ "$app" = "$TARGET" ] || is_github_build "$app"; }; then
    OLD_VERSION="$(/usr/bin/defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
  fi
done

quit_app

info "Installing to $TARGET"
STAGE="$APP_DIR/.$APP_NAME.installing"
$SUDO rm -rf "$STAGE"
$SUDO ditto "$SOURCE" "$STAGE"
$SUDO rm -rf "$TARGET"
$SUDO mv "$STAGE" "$TARGET"
# Replace an older GitHub build installed under the previous name instead of
# leaving a second copy beside the new one.
if is_github_build "$LEGACY"; then
  info "Removing the older copy at $LEGACY"
  $SUDO rm -rf "$LEGACY"
fi

hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
MOUNT=""

# curl does not quarantine downloads; clear the flag only if something set it.
if xattr -p com.apple.quarantine "$TARGET" >/dev/null 2>&1; then
  $SUDO xattr -dr com.apple.quarantine "$TARGET" || warn "could not clear quarantine flag"
fi

if [ -n "$OLD_VERSION" ]; then
  ok "Updated Command Reopen $OLD_VERSION → $NEW_VERSION"
else
  ok "Installed Command Reopen $NEW_VERSION"
fi

if [ "$LAUNCH" -eq 1 ]; then
  info "Launching Command Reopen"
  open "$TARGET" || warn "could not launch; open it from $APP_DIR."
fi
