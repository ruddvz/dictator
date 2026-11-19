#!/bin/bash
# Checks that on-device recognition keeps every phrase when the speaker pauses for seconds.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
TEST_RUNNER_DICTATOR_EVAL=1 xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO -only-testing:DictatorTests/PauseRecognitionTests test 2>&1 \
  | grep -E "Recognized across pauses|error:|TEST (SUCCEEDED|FAILED)"
