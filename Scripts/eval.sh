#!/bin/bash
# Runs HushKey's local dictation eval and writes docs/eval/report.md and report.json.
# Audio stays on this Mac: clips are recognized with on-device Apple Speech and any WhisperKit
# or Parakeet model already downloaded in HushKey. Nothing is downloaded and no remote service is used.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

voice="${HUSHKEY_EVAL_VOICE:-Samantha}"
locale="${HUSHKEY_EVAL_LOCALE:-en-US}"

# Synthesize a bootstrap clip with macOS text-to-speech for each clip that has no consented recording.
for split in dev holdout; do
  manifest="Fixtures/eval/$split/audio.json"
  out_dir=".build/eval-audio/$split"
  mkdir -p "$out_dir"
  index=0
  while id="$(plutil -extract "clips.$index.id" raw -o - "$manifest" 2>/dev/null)"; do
    reference="$(plutil -extract "clips.$index.reference" raw -o - "$manifest")"
    index=$((index + 1))
    if compgen -G "Fixtures/eval/$split/audio/$id.*" >/dev/null; then continue; fi
    stamp="$voice|$reference"
    if [[ -f "$out_dir/$id.wav" && "$(cat "$out_dir/$id.txt" 2>/dev/null)" == "$stamp" ]]; then continue; fi
    say -v "$voice" --file-format=WAVE --data-format=LEI16@16000 -o "$out_dir/$id.wav" "$reference"
    printf '%s' "$stamp" > "$out_dir/$id.txt"
  done
done

xcodegen generate --quiet
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO \
  build-for-testing -quiet
# Sign the test host like dist/HushKey.app, so macOS treats it as the same app: Speech stays
# allowed without a prompt, and dist's permissions aren't moved to an ad-hoc copy.
identity="$(security find-identity -p codesigning 2>/dev/null | awk '/"HushKey Local Signing"/ { print $2; exit }')"
if [[ -n "$identity" ]]; then
  codesign --force --deep --sign "$identity" --timestamp=none .build/Build/Products/Debug/HushKey.app
fi
TEST_RUNNER_HUSHKEY_EVAL=1 TEST_RUNNER_HUSHKEY_EVAL_LOCALE="$locale" \
  xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO \
  -only-testing:HushKeyTests/DictationEvalTests -only-testing:HushKeyTests/PauseRecognitionTests test-without-building -quiet

echo "Wrote $project_root/docs/eval/report.md"
