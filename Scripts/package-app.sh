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
echo "Built $project_root/dist/HushKey.app"
