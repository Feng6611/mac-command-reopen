#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/appstore/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

: "${APP_ID:?Missing APP_ID}"
: "${APP_VERSION:?Missing APP_VERSION}"
: "${ASC_KEY_ID:?Missing ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID}"
: "${ASC_PRIVATE_KEY_PATH:?Missing ASC_PRIVATE_KEY_PATH}"

export ASC_BYPASS_KEYCHAIN=1
export ASC_KEY_ID
export ASC_ISSUER_ID
export ASC_PRIVATE_KEY_PATH

asc builds list --app "$APP_ID" --version "$APP_VERSION" --sort -uploadedDate --output table
