#!/usr/bin/env bash
# build-dev.sh — Archive a development build and export an IPA
#
# Usage:  ./scripts/build-dev.sh
#
# Output: /tmp/ChessRecall-dev.ipa

set -euo pipefail

# ── Xcode config ──────────────────────────────────────────────────────────────
readonly PROJECT="ChessRecall.xcodeproj"
readonly SCHEME="ChessRecall"
readonly ARCHIVE_PATH="/tmp/ChessRecall-dev.xcarchive"
readonly EXPORT_PATH="/tmp/ChessRecall-dev-export"
readonly IPA_PATH="/tmp/ChessRecall-dev.ipa"

# ── Ensure Xcode is running (required for automatic provisioning) ─────────────
echo "→ Ensuring Xcode is running..."
open -a Xcode
sleep 5

# ── Archive (Debug config, development signing) ───────────────────────────────
echo "→ Archiving development build..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic

# ── Write ExportOptions.plist inline ──────────────────────────────────────────
EXPORT_PLIST=$(mktemp /tmp/ExportOptions.XXXXXX.plist)
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>3KJ42RM854</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

# ── Export IPA ────────────────────────────────────────────────────────────────
echo "→ Exporting IPA..."
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates
rm -f "$EXPORT_PLIST"

cp "$EXPORT_PATH/ChessRecall.ipa" "$IPA_PATH"

echo ""
echo "✓ Development IPA ready: $IPA_PATH"
