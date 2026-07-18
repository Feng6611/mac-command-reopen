#!/bin/sh
set -eu

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *" APPSTORE "*)
    ;;
  *)
    echo "note: Skipping RevenueCat API key check for non-App Store build"
    exit 0
    ;;
esac

trimmed_key="$(printf '%s' "${CMDREOPEN_REVENUECAT_API_KEY:-}" | /usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
local_secrets_path="${SRCROOT:-$(pwd)}/Config/LocalSecrets.xcconfig"

if [ -z "${trimmed_key}" ] && [ -f "${local_secrets_path}" ]; then
  trimmed_key="$(/usr/bin/sed -nE 's/^[[:space:]]*CMDREOPEN_REVENUECAT_API_KEY[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "${local_secrets_path}" | /usr/bin/tail -n 1)"
fi

if [ -z "${trimmed_key}" ]; then
  if [ ! -f "${local_secrets_path}" ]; then
    echo "error: CMDREOPEN_REVENUECAT_API_KEY is empty and ${local_secrets_path} does not exist." >&2
    echo "error: Create that ignored local file with: CMDREOPEN_REVENUECAT_API_KEY = appl_your_public_revenuecat_sdk_key" >&2
  else
    echo "error: CMDREOPEN_REVENUECAT_API_KEY is empty even though ${local_secrets_path} exists." >&2
    echo "error: Check that the file contains exactly: CMDREOPEN_REVENUECAT_API_KEY = appl_your_public_revenuecat_sdk_key" >&2
  fi
  exit 1
fi

case "${trimmed_key}" in
  appl_your_public_revenuecat_sdk_key)
    echo "error: CMDREOPEN_REVENUECAT_API_KEY is still set to the example placeholder." >&2
    exit 1
    ;;
esac

case "${trimmed_key}" in
  appl_*)
    ;;
  test_*)
    echo "error: Command Reopen does not use RevenueCat Test Store keys." >&2
    echo "error: Debug uses Apple Sandbox with the production Apple public SDK key (appl_)." >&2
    exit 1
    ;;
  *)
    echo "error: App Store builds require an Apple public RevenueCat SDK key beginning with appl_." >&2
    exit 1
    ;;
esac

verify_built_product() {
  if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ]; then
    return 0
  fi

  built_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
  if [ ! -f "${built_plist}" ]; then
    echo "error: Built product Info.plist is missing at ${built_plist}." >&2
    exit 1
  fi

  embedded_key="$(/usr/libexec/PlistBuddy -c 'Print :CmdReopenRevenueCatAPIKey' "${built_plist}" 2>/dev/null || true)"
  if [ "${embedded_key}" != "${trimmed_key}" ]; then
    echo "error: Built Command Reopen.app does not contain the configured RevenueCat API key." >&2
    exit 1
  fi

  embedded_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${built_plist}" 2>/dev/null || true)"
  if [ "${embedded_bundle_id}" != "com.dev.kkuk.CommandReopen" ]; then
    echo "error: Built App Store product has unexpected bundle identifier: ${embedded_bundle_id:-<missing>}." >&2
    exit 1
  fi

  echo "note: Verified RevenueCat configuration in the built Command Reopen.app"
}

verify_built_product
echo "note: RevenueCat API key is configured for App Store build"
