#!/bin/bash
# Scores HushKey's saved silent takes under several decoding variants and writes docs/eval/silent-report.md.
# Reads the dataset in place (default: HushKey's own Application Support copy); nothing is uploaded or changed.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

dataset="${1:-$HOME/Library/Application Support/com.ruddvz.hushkey/dataset.json}"
[[ -f "$dataset" ]] || { echo "No dataset at $dataset" >&2; exit 1; }

xcodegen generate --quiet
TEST_RUNNER_HUSHKEY_SILENT_DATASET="$dataset" \
  TEST_RUNNER_HUSHKEY_SILENT_PERMUTATIONS="${HUSHKEY_SILENT_PERMUTATIONS:-500}" \
  xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO \
  -only-testing:HushKeyTests/SilentEvalTests test -quiet

echo "Wrote $project_root/docs/eval/silent-report.md"
