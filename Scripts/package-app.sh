#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
app_path="$project_root/build/Build/Products/Release/HushKey.app"
mkdir -p "$project_root/dist"
ditto "$app_path" "$project_root/dist/HushKey.app"
codesign --force --deep --sign - --timestamp=none "$project_root/dist/HushKey.app"
echo "Built $project_root/dist/HushKey.app"
