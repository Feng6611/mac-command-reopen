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

if [ -z "${trimmed_key}" ]; then
  local_secrets_path="${SRCROOT:-$(pwd)}/Config/LocalSecrets.xcconfig"
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

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *" DEBUG "*)
    ;;
  *)
    case "${trimmed_key}" in
      test_*)
        echo "error: Release App Store builds must not use a RevenueCat test API key." >&2
        exit 1
        ;;
    esac
    ;;
esac

echo "note: RevenueCat API key is configured for App Store build"
