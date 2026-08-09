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
