#!/bin/sh

set -eu

if [ "${SKIP_AUTO_INCREMENT_BUILD_NUMBER:-0}" = "1" ]; then
  echo "note: Skipping build number bump because SKIP_AUTO_INCREMENT_BUILD_NUMBER=1"
  exit 0
fi

if [ "${CI:-}" = "1" ] || [ "${CI:-}" = "true" ]; then
  echo "note: Skipping build number bump on CI"
  exit 0
fi

VERSION_FILE="${SRCROOT}/Config/BuildNumber.xcconfig"

if [ ! -f "${VERSION_FILE}" ]; then
  echo "error: Missing build number file at ${VERSION_FILE}" >&2
  exit 1
fi

current_version="$(
  /usr/bin/awk -F '=' '
    /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2)
      print $2
      exit
    }
  ' "${VERSION_FILE}"
)"

if [ -z "${current_version}" ]; then
  echo "error: CURRENT_PROJECT_VERSION is missing from ${VERSION_FILE}" >&2
  exit 1
fi

case "${current_version}" in
  ''|*[!0-9]*)
    echo "error: CURRENT_PROJECT_VERSION must be an integer, got '${current_version}'" >&2
    exit 1
    ;;
esac

next_version=$((current_version + 1))

/usr/bin/sed -E -i '' \
  "s/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*$/CURRENT_PROJECT_VERSION = ${next_version}/" \
  "${VERSION_FILE}"

echo "note: Bumped build number from ${current_version} to ${next_version} for the next build"
