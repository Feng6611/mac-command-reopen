#!/bin/sh
# Archive gate: inspect the final app's Info.plist, never print the token.
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <app>" >&2
    exit 2
fi
plist="$1/Contents/Info.plist"
if [ ! -f "$plist" ]; then
    echo "Missing app Info.plist" >&2
    exit 1
fi
token=$(/usr/libexec/PlistBuddy -c 'Print :KikiPostHogProjectToken' "$plist" 2>/dev/null || true)
token=$(printf '%s' "$token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
lower=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
case "$lower" in
    *'$('*) valid=false ;;
    *your*|*placeholder*) valid=false ;;
    *) case "$token" in phc_*) valid=true ;; *) valid=false ;; esac ;;
esac
if [ "$valid" != true ]; then
    echo "Missing, placeholder or invalid KikiPostHogProjectToken" >&2
    exit 1
fi
echo "PostHog token configuration OK"
