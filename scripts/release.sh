#!/usr/bin/env bash
# release.sh — Bump version, archive, and upload dSYMs to Datadog
#
# Usage:  ./scripts/release.sh <version>   e.g.  ./scripts/release.sh 1.1
#
# Prerequisites:
#   1. datadog-ci installed:
#        npm install -g @datadog/datadog-ci
#      or:
#        brew install datadog/tap/datadog-ci
#
#   2. DD_API_KEY stored in Keychain (run once):
#        security add-generic-password \
#          -s "datadog-chess-recall" -a "$USER" -w "<your-dd-api-key>"

set -euo pipefail

# ── Datadog config (must stay in sync with ChessRecallApp.swift) ──────────────
readonly DD_SERVICE="chess-recall-ios"
readonly DATADOG_SITE="datadoghq.eu"
readonly DD_KEYCHAIN_SERVICE="datadog-chess-recall"

# ── Xcode config ──────────────────────────────────────────────────────────────
readonly PROJECT="ChessRecall.xcodeproj"
readonly SCHEME="ChessRecall"
readonly INFOPLIST="ChessRecall/Info.plist"
readonly ARCHIVE_PATH="/tmp/ChessRecall-release.xcarchive"

# ── Validate args ─────────────────────────────────────────────────────────────
VERSION="${1:?Usage: $(basename "$0") <version>  e.g.  1.1}"

# ── Read DD_API_KEY from macOS Keychain ───────────────────────────────────────
echo "→ Reading DD_API_KEY from Keychain..."
DATADOG_API_KEY=$(security find-generic-password \
  -s "$DD_KEYCHAIN_SERVICE" -a "$USER" -w 2>/dev/null) || {
  echo ""
  echo "Error: DD_API_KEY not found in Keychain."
  echo "Store it once with:"
  echo "  security add-generic-password -s \"$DD_KEYCHAIN_SERVICE\" -a \"\$USER\" -w \"<your-key>\""
  exit 1
}
export DATADOG_API_KEY
export DATADOG_SITE

# ── Bump CFBundleShortVersionString ───────────────────────────────────────────
echo "→ Bumping version to $VERSION..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFOPLIST"

# ── Commit & tag ──────────────────────────────────────────────────────────────
git add "$INFOPLIST"
git commit -m "chore: release $VERSION"
git tag -a "v$VERSION" -m "Release $VERSION"
echo "→ Tagged v$VERSION"

# ── Archive ───────────────────────────────────────────────────────────────────
echo "→ Archiving for release (this takes a moment)..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic

# ── Upload dSYMs to Datadog ───────────────────────────────────────────────────
# BUILD_NUMBER mirrors the "Set Build Number from Git" Xcode build phase
BUILD_NUMBER=$(git rev-list --count HEAD)
echo "→ Uploading dSYMs (version=$VERSION build=$BUILD_NUMBER)..."
datadog-ci dsyms upload "$ARCHIVE_PATH/dSYMs"

echo ""
echo "✓ Release $VERSION (build $BUILD_NUMBER) complete."
echo "  Archive: $ARCHIVE_PATH"
