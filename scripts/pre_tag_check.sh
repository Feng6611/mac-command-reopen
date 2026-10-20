#!/bin/sh
# Pre-tag checklist. Run before `git tag <version>`; read-only, never tags or pushes.
#   scripts/pre_tag_check.sh 1.5.2 [--skip-tests]
# Exit 0 only when every blocking check passes (warnings do not block).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

VERSION="${1:-}"
SKIP_TESTS=0
[ "${2:-}" = "--skip-tests" ] && SKIP_TESTS=1
if [ -z "$VERSION" ]; then
  echo "usage: scripts/pre_tag_check.sh <version>   e.g. 1.5.2" >&2
  exit 2
fi

PBXPROJ="CmdReopen.xcodeproj/project.pbxproj"
BUILD_XCCONFIG="Config/BuildNumber.xcconfig"
fail=0

pass() { printf '  [ ok ] %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }

echo "Pre-tag checklist for $VERSION"

echo "1. Tag"
case "$VERSION" in
  *[!0-9.]*|"" ) bad "version '$VERSION' must be digits and dots (tags have no 'v' prefix)" ;;
  *) pass "version format" ;;
esac
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  bad "tag $VERSION already exists locally"
else
  pass "tag $VERSION is free locally"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$VERSION" >/dev/null 2>&1; then
  bad "tag $VERSION already exists on origin"
else
  pass "tag $VERSION is free on origin (or origin unreachable)"
fi

echo "2. Git state"
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "HEAD" ] && bad "detached HEAD" || pass "on branch $branch"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  bad "uncommitted changes to tracked files — commit them first, the tag must point at the release"
else
  pass "tracked files are clean"
fi
upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  warn "no upstream configured; push the branch before tagging"
elif [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]; then
  bad "HEAD differs from $upstream — push (or pull) before tagging"
else
  pass "HEAD matches $upstream"
fi

echo "3. Version"
app_versions="$(grep 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//; s/;.*//' | sort -u | grep -v '^1\.0$')"
if [ "$app_versions" = "$VERSION" ]; then
  pass "MARKETING_VERSION is $VERSION in every app target"
else
  bad "MARKETING_VERSION values (excluding test targets at 1.0): $(echo $app_versions)"
fi
prev_tag="$(git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
if [ -n "$prev_tag" ]; then
  newest="$(printf '%s\n%s\n' "$prev_tag" "$VERSION" | sort -V | tail -1)"
  if [ "$prev_tag" != "$VERSION" ] && [ "$newest" = "$VERSION" ]; then
    pass "$VERSION is newer than previous tag $prev_tag"
  else
    bad "$VERSION is not newer than previous tag $prev_tag"
  fi
  prev_build="$(git show "$prev_tag:$BUILD_XCCONFIG" 2>/dev/null | sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' | tr -d ' ')"
fi
build="$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$BUILD_XCCONFIG" | tr -d ' ')"
case "$build" in
  ''|*[!0-9]*) bad "build number '$build' is not an integer" ;;
  *) pass "build number $build" ;;
esac
if [ -n "${prev_build:-}" ] && [ "$build" -le "$prev_build" ] 2>/dev/null; then
  warn "build number $build is not above $prev_tag's ($prev_build); App Store Connect rejects a repeated build for the same version"
fi
if git diff --quiet HEAD -- "$BUILD_XCCONFIG"; then
  pass "$BUILD_XCCONFIG committed"
else
  bad "$BUILD_XCCONFIG has uncommitted changes"
fi

echo "4. Changelog"
if grep -q "^## $VERSION — " CHANGELOG.md; then
  pass "CHANGELOG has a '## $VERSION — <date>' section"
  section="$(awk -v v="$VERSION" '$0 ~ "^## "v" — "{f=1;next} /^## /{f=0} f' CHANGELOG.md)"
  echo "$section" | grep -q '^### English' && echo "$section" | grep -q '^### 中文' \
    && pass "section has English and 中文" || bad "section must have both '### English' and '### 中文'"
else
  bad "CHANGELOG has no '## $VERSION — <date>' heading"
fi
if grep -q '^## Unreleased' CHANGELOG.md; then
  warn "CHANGELOG still has an 'Unreleased' section"
fi

echo "5. Secrets and config"
if [ -n "$(sed -n 's/^CMDREOPEN_REVENUECAT_API_KEY *= *//p' "$BUILD_XCCONFIG" | tr -d ' ')" ]; then
  bad "$BUILD_XCCONFIG commits a RevenueCat key; it belongs in LocalSecrets.xcconfig"
else
  pass "no RevenueCat key committed"
fi
if git ls-files --error-unmatch Config/LocalSecrets.xcconfig >/dev/null 2>&1; then
  bad "Config/LocalSecrets.xcconfig is tracked"
else
  pass "LocalSecrets.xcconfig is untracked"
fi
if grep -q 'trialDuration: TimeInterval' CmdReopen/Features/Pro/RevenueCatConfiguration.swift; then
  echo "     info: $(grep 'trialDuration: TimeInterval' CmdReopen/Features/Pro/RevenueCatConfiguration.swift | sed 's/^ *//')"
  echo "     info: paywall plans: $(grep -A1 'visiblePaywallPlanIDs: \[String\]' CmdReopen/Features/Pro/RevenueCatConfiguration.swift | tail -1 | sed 's/^ *//')"
fi

echo "6. Kiki dependencies"
floating="$(awk '
  /XCRemoteSwiftPackageReference "Kiki/ {kiki=1}
  kiki && /kind = / {if ($0 !~ /exactVersion/) print $0; kiki=0}
  kiki && /^\t\t};/ {kiki=0}
' "$PBXPROJ")"
if [ -n "$floating" ]; then
  bad "a Kiki package in $PBXPROJ is not pinned to an exact version (registry policy: exact)"
else
  pass "Kiki packages pinned exactly"
fi

echo "   Kiki versions vs. latest tag in the workspace"
for pair in "Kiki_mackit:Kiki_mackit" "KikiCommerceKit:KikiCommerceKit"; do
  pkg="${pair%%:*}"
  pinned="$(awk -v n="XCRemoteSwiftPackageReference \"$pkg\"" '$0 ~ n && /= \{/ {f=1} f && /version = / {gsub(/[^0-9.]/, "", $0); sub(/^\.+/, "", $0); print; exit}' "$PBXPROJ")"
  repo="$ROOT/../$pkg"
  if [ -d "$repo/.git" ]; then
    latest="$(git -C "$repo" tag --sort=-v:refname | head -1)"
    ahead="$(git -C "$repo" rev-list --count "$latest"..HEAD 2>/dev/null || echo 0)"
    if [ "$pinned" = "$latest" ]; then
      pass "$pkg pinned $pinned = latest tag"
    else
      bad "$pkg pinned $pinned but latest tag is $latest"
    fi
    [ "$ahead" -gt 0 ] && warn "$pkg main is $ahead commit(s) past $latest (unreleased; not in this build)"
  else
    warn "$pkg checkout not found at $repo; cannot compare versions"
  fi
done

echo "7. Trial and paywall"
# Behavior contract, enforced by tests: new installs get a 2-day trial, installs
# that already had a trial keep 14 days; finishing onboarding always shows the
# paywall (App Store build, non-owners); a trial older than 3 days shows it once
# a day at 10 reopens; it opens once when the trial ends; never for owners.
if [ "$SKIP_TESTS" -eq 1 ]; then
  warn "tests skipped (--skip-tests)"
else
  if xcodebuild test -project CmdReopen.xcodeproj -scheme CmdReopen \
      -only-testing:CmdReopenTests/CommandAccessModelTests \
      -only-testing:CmdReopenTests/TrialExitOfferTests \
      -only-testing:CmdReopenTests/ReopenPolicyTests \
      -only-testing:CmdReopenTests/OnboardingPaywallPolicyTests >/tmp/pre_tag_check_tests.log 2>&1; then
    pass "trial length, onboarding paywall, usage paywall, expiry paywall, win-back and Cmd+Tab nudge tests"
  else
    bad "trial/paywall tests failed; see /tmp/pre_tag_check_tests.log"
  fi
fi

echo "8. Manual (not checked here)"
echo "     - Full suite: xcodebuild test -scheme CmdReopen"
echo "     - Archive both variants and run check-mac-app-artifact-config on the .app/.pkg"
echo "     - App Store Connect/RevenueCat catalog matches the in-app plans and trial"
echo "     - Direct (GitHub) build notarized if this tag ships one"

echo
if [ "$fail" -gt 0 ]; then
  echo "NOT READY: $fail blocking issue(s)."
  exit 1
fi
echo "READY: git tag $VERSION && git push origin $VERSION"
