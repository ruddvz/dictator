@AGENTS.md

## CI: test locally, not on GitHub

GitHub Actions doesn't run for this private repo: jobs are refused for billing ("recent account payments have failed") or never get a macOS runner. That is deliberate; don't try to fix billing, and ignore the red `build-test` check on the PR.

Verify every change on this Mac instead, and say so in `PROGRESS.md`:

```bash
osascript -e 'quit app "HushKey"'   # a running copy can abort the test run
xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
Scripts/package-app.sh && open dist/HushKey.app
```

Then check the change in the packaged app, since unit tests don't cover the mic, insertion or permissions.
