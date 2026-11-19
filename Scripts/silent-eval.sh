#!/bin/bash
# Scores Dictator's saved silent takes under several decoding variants and writes docs/eval/silent-report.md.
# Reads the dataset in place (default: Dictator's own Application Support copy); nothing is uploaded or changed.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

dataset="${1:-$HOME/Library/Application Support/com.ruddvz.dictator/dataset.json}"
[[ -f "$dataset" ]] || { echo "No dataset at $dataset" >&2; exit 1; }

xcodegen generate --quiet
TEST_RUNNER_DICTATOR_SILENT_DATASET="$dataset" \
  TEST_RUNNER_DICTATOR_SILENT_PERMUTATIONS="${DICTATOR_SILENT_PERMUTATIONS:-500}" \
  xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO \
  -only-testing:DictatorTests/SilentEvalTests test -quiet

echo "Wrote $project_root/docs/eval/silent-report.md"
