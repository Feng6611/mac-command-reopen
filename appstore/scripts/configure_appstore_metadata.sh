#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APPSTORE_DIR="$ROOT_DIR/appstore"
ENV_FILE="${ENV_FILE:-$APPSTORE_DIR/.env}"
METADATA_FILE="$APPSTORE_DIR/metadata/en-US.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  echo "Copy appstore/.env.example to appstore/.env and fill the credentials."
  exit 1
fi

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Missing $METADATA_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${APP_ID:?Missing APP_ID}"
: "${APP_VERSION:?Missing APP_VERSION}"
: "${ASC_KEY_ID:?Missing ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID}"
: "${ASC_PRIVATE_KEY_PATH:?Missing ASC_PRIVATE_KEY_PATH}"
: "${SUPPORT_URL:?Missing SUPPORT_URL}"
: "${PRIVACY_URL:?Missing PRIVACY_URL}"
: "${APP_NAME:?Missing APP_NAME}"
: "${APP_SUBTITLE:?Missing APP_SUBTITLE}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script."
  exit 1
fi

DESCRIPTION="$(jq -r '.description' "$METADATA_FILE")"
KEYWORDS="$(jq -r '.keywords' "$METADATA_FILE")"
SUPPORT_FROM_FILE="$(jq -r '.support_url' "$METADATA_FILE")"
MARKETING_URL="$(jq -r '.marketing_url' "$METADATA_FILE")"
PROMOTIONAL_TEXT="$(jq -r '.promotional_text' "$METADATA_FILE")"
WHATS_NEW="$(jq -r '.whats_new' "$METADATA_FILE")"

export ASC_BYPASS_KEYCHAIN=1
export ASC_KEY_ID
export ASC_ISSUER_ID
export ASC_PRIVATE_KEY_PATH

asc versions create --app "$APP_ID" --version "$APP_VERSION" --platform MAC_OS || true

asc localizations update \
  --app "$APP_ID" \
  --type app-info \
  --locale "en-US" \
  --name "$APP_NAME" \
  --subtitle "$APP_SUBTITLE" \
  --privacy-policy-url "$PRIVACY_URL"

asc app-info set \
  --app "$APP_ID" \
  --version "$APP_VERSION" \
  --platform MAC_OS \
  --locale "en-US" \
  --description "$DESCRIPTION" \
  --keywords "$KEYWORDS" \
  --support-url "$SUPPORT_FROM_FILE" \
  --marketing-url "$MARKETING_URL" \
  --promotional-text "$PROMOTIONAL_TEXT"

if [[ -n "$WHATS_NEW" ]]; then
  asc app-info set \
    --app "$APP_ID" \
    --version "$APP_VERSION" \
    --platform MAC_OS \
    --locale "en-US" \
    --whats-new "$WHATS_NEW"
fi

echo "Metadata configured for app $APP_ID version $APP_VERSION."
