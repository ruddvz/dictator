#!/usr/bin/env bash
# Builds dist/Dictator-<version>.dmg: an ad-hoc signed app (not tied to this Mac's local
# certificate) plus an Applications shortcut and short install notes.
#
# This is NOT notarized. macOS Gatekeeper blocks it on first open until the user allows it in
# System Settings → Privacy & Security → "Open Anyway" (see the notes inside the DMG).
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

DICTATOR_AD_HOC=1 ./Scripts/package-app.sh
app="dist/Dictator.app"
[[ -d "$app" ]] || { echo "Build failed: $app is missing." >&2; exit 1; }
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="dist/Dictator-$version.dmg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/Dictator.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/READ ME FIRST.txt" <<'NOTES'
Install Dictator
1. Drag Dictator onto Applications.
2. Open Dictator from Applications. macOS will say it can't verify the app (it isn't notarized).
   Click Done, then open System Settings → Privacy & Security, scroll down, click "Open Anyway"
   next to Dictator, and confirm. You only do this once per downloaded version.
   (Terminal alternative: xattr -dr com.apple.quarantine /Applications/Dictator.app)
3. Allow Microphone and Speech Recognition when asked.
4. System Settings → Privacy & Security → Accessibility → switch Dictator on.
5. Hold fn, speak, release. For the best accuracy choose Parakeet in Settings → Dictation.

After an update you may need to switch Dictator off and on again under Accessibility.
Nothing leaves your Mac. Source and notices: https://github.com/ruddvz/dictator
NOTES

rm -f "$dmg"
hdiutil create -quiet -volname "Dictator $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
echo "Built $dmg ($(du -h "$dmg" | cut -f1))"
shasum -a 256 "$dmg"
