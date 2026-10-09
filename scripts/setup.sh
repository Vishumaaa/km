#!/bin/sh
# One-time (and re-runnable) project setup: asks for a bundle ID prefix and finds your Apple
# Team ID, writes project.yml, and generates Glide.xcodeproj.
#
# Non-interactive:  GLIDE_BUNDLE_PREFIX=com.yourname GLIDE_TEAM_ID=ABCDE12345 ./scripts/setup.sh
set -e
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with:  brew install xcodegen"
  exit 1
fi

# --- Bundle ID prefix (must be unique to you; Apple rejects ones already taken) ---
PREFIX="${GLIDE_BUNDLE_PREFIX:-}"
if [ -z "$PREFIX" ]; then
  DEFAULT="com.$(whoami)"
  printf "Bundle ID prefix, e.g. com.yourname [%s]: " "$DEFAULT"
  read -r PREFIX
  PREFIX="${PREFIX:-$DEFAULT}"
fi
PREFIX=$(printf '%s' "$PREFIX" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9.-')

# --- Apple Team ID (from the signing certificate Xcode created for your Apple ID) ---
TEAM="${GLIDE_TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p' | head -1)
fi
if [ -z "$TEAM" ]; then
  echo
  echo "Couldn't find an Apple signing certificate on this Mac."
  echo "Open Xcode > Settings > Accounts, add your Apple ID, then build any app once so Xcode"
  echo "creates a certificate. Or paste your 10-character Team ID now (Enter to skip):"
  read -r TEAM
fi

sed -e "s/com\.example/$PREFIX/g" \
    -e "s/DEVELOPMENT_TEAM: \"\"/DEVELOPMENT_TEAM: \"$TEAM\"/" \
    project.template.yml > project.yml

xcodegen

echo
echo "Bundle ID prefix: $PREFIX"
echo "Team ID:          ${TEAM:-<none: choose a Team in Xcode, then re-run this script>}"
echo "Done. Open Glide.xcodeproj"
