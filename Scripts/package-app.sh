#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift Scripts/generate-app-icon.swift
xcodegen generate
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/HushKey-build.XXXXXX")"
stage_dir=""
backup_dir=""
backup_path=""
cleanup() {
  rm -rf "$derived_data"
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then rm -rf "$stage_dir"; fi
  if [[ -n "$backup_path" && -d "$backup_path" && ! -d "$project_root/dist/HushKey.app" ]]; then
    mv "$backup_path" "$project_root/dist/HushKey.app"
  fi
  if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then rm -rf "$backup_dir"; fi
}
trap cleanup EXIT
xcodebuild -project HushKey.xcodeproj -scheme HushKey -configuration Release -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO build
app_path="$derived_data/Build/Products/Release/HushKey.app"
mkdir -p "$project_root/dist"
stage_dir="$(mktemp -d "$project_root/dist/.HushKey-stage.XXXXXX")"
staged_app="$stage_dir/HushKey.app"
ditto "$app_path" "$staged_app"
resources="$staged_app/Contents/Resources"
mkdir -p "$resources"
cp "$project_root/docs/research/Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf" "$resources/"
cp "$project_root/docs/COMPETITOR_RESEARCH.md" "$resources/"
cp "$project_root/docs/COMPETITOR_RESEARCH_ADDENDUM_2026-11-01.md" "$resources/"
cp "$project_root/docs/LOCAL_MODEL_EVALUATION.md" "$resources/"
cp "$project_root/NOTICE.md" "$resources/"
cp "$project_root/LICENSE" "$resources/"
cp "$project_root/docs/licenses/ARGMAX-MIT-LICENSE.txt" "$resources/"
cp "$project_root/docs/licenses/ARGMAX-NOTICES.txt" "$resources/"
# Ad-hoc signatures default to a cdhash requirement, so macOS treats every build as a new app
# and asks for microphone, Speech and Accessibility again. Naming the bundle identifier keeps
# those grants across local builds. Distribution builds should use a real signing identity.
codesign --force --deep --sign - --timestamp=none \
  -r='designated => identifier "com.ruddvz.hushkey"' "$staged_app"
destination="$project_root/dist/HushKey.app"
if [[ -e "$destination" ]]; then
  backup_dir="$(mktemp -d "$project_root/dist/.HushKey-backup.XXXXXX")"
  backup_path="$backup_dir/HushKey.app"
  mv "$destination" "$backup_path"
fi
mv "$staged_app" "$destination"
if [[ -n "$backup_path" ]]; then
  rm -rf "$backup_dir"
  backup_dir=""
  backup_path=""
fi
rmdir "$stage_dir"
stage_dir=""
echo "Built $project_root/dist/HushKey.app"
