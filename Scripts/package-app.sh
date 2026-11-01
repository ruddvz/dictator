#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift Scripts/generate-app-icon.swift
xcodegen generate
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/HushKey-build.XXXXXX")"
trap 'rm -rf "$derived_data"' EXIT
xcodebuild -project HushKey.xcodeproj -scheme HushKey -configuration Release -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build
app_path="$derived_data/Build/Products/Release/HushKey.app"
mkdir -p "$project_root/dist"
staged_app="$project_root/dist/HushKey.app.staging"
rm -rf "$staged_app"
ditto "$app_path" "$staged_app"
codesign --force --deep --sign - --timestamp=none "$staged_app"
rm -rf "$project_root/dist/HushKey.app"
mv "$staged_app" "$project_root/dist/HushKey.app"
# Remove stale Xcode products that can make Finder or the Dock pick a Debug build.
rm -rf "$project_root/build" "$project_root/.build"
derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
for stale_app in "$derived_data_root"/HushKey-*/Build/Products/{Debug,Release}/HushKey.app; do
  if [[ -d "$stale_app" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$stale_app" >/dev/null 2>&1 || true
    rm -rf "$stale_app"
  fi
done
echo "Built $project_root/dist/HushKey.app"
