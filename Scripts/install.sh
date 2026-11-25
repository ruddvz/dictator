#!/usr/bin/env bash
# One-command install for Dictator: checks prerequisites, builds the app from source with a stable
# local signature, installs it to /Applications and opens it.
#
#   ./Scripts/install.sh            # build, install, launch
#   ./Scripts/install.sh --check    # only check prerequisites
#
# Why build locally: Dictator has no notarized release yet, and macOS ties Accessibility trust to
# the app's code signature. A build signed with your own stable local identity keeps that trust
# across updates.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

say() { printf '\n==> %s\n' "$1"; }
fail() { printf '\nError: %s\n' "$1" >&2; exit 1; }

check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

say "Checking this Mac"
[[ "$(uname -s)" == "Darwin" ]] || fail "Dictator only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "Dictator needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

if ! xcodebuild -version >/dev/null 2>&1; then
  fail "Full Xcode is required (Command Line Tools alone are not enough). Install Xcode from the App Store, open it once to accept the license, then run: sudo xcode-select -s /Applications/Xcode.app"
fi
xcodebuild -version | head -1
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  fail "Xcode hasn't finished first-launch setup. Run: sudo xcodebuild -runFirstLaunch"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || fail "XcodeGen is missing and Homebrew isn't installed. Install Homebrew from https://brew.sh, then run this script again."
  say "Installing XcodeGen"
  brew install xcodegen
fi
echo "XcodeGen $(xcodegen --version 2>/dev/null | head -1)"

if [[ "$check_only" -eq 1 ]]; then
  say "All prerequisites are in place."
  exit 0
fi

say "Creating a local signing identity (first run only)"
./Scripts/make-signing-identity.sh

say "Building Dictator (this takes a few minutes the first time)"
./Scripts/package-app.sh

say "Installing to /Applications"
if pgrep -x Dictator >/dev/null 2>&1; then
  killall Dictator 2>/dev/null || true
  sleep 1
fi
rm -rf /Applications/Dictator.app
cp -R dist/Dictator.app /Applications/Dictator.app
codesign --verify --deep --strict /Applications/Dictator.app || fail "The installed app failed signature verification."

say "Opening Dictator"
open /Applications/Dictator.app

cat <<'MSG'

Dictator is installed. First launch:
  1. Allow Microphone and Speech Recognition when macOS asks.
  2. Open System Settings → Privacy & Security → Accessibility and switch Dictator on.
     (This is what lets the fn key start dictation and lets Dictator type into other apps.)
  3. Hold fn, speak, release. For the best accuracy, choose Parakeet in Settings → Dictation.

If macOS shows a keychain prompt about "Dictator Local Signing" while building, choose Always Allow.
To update later: git pull && ./Scripts/install.sh
MSG
