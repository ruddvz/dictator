#!/usr/bin/env bash
# Runs the full unit-test suite locally (this is the project's real test run; GitHub's CI is
# manual-only because its runners use an older Xcode than development does).
#   ./Scripts/test.sh
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
xcodegen generate -q
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee /tmp/dictator-test.log \
  | grep -E "error: |Executed [0-9]+ tests.*seconds$|TEST (SUCCEEDED|FAILED)" | tail -4
grep -q "TEST SUCCEEDED" /tmp/dictator-test.log
