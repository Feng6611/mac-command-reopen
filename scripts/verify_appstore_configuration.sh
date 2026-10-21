#!/bin/sh
set -eu

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *" APPSTORE "*) ;;
  *)
    echo "note: Skipping App Store service configuration check for non-App Store build"
    exit 0
    ;;
esac

"${SRCROOT:-$(pwd)}/scripts/verify_revenuecat_api_key.sh"
echo "note: Verified RevenueCat configuration in the App Store build"

# Release App Store archives must carry the PostHog project token; Debug builds
# send nothing without one, so they are not gated.
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *" DEBUG "*)
    echo "note: Skipping PostHog token check for a Debug build"
    ;;
  *)
    if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${WRAPPER_NAME:-}" ]; then
      "${SRCROOT:-$(pwd)}/scripts/check_posthog_config.sh" "${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
    fi
    ;;
esac
