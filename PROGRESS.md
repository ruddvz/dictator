# Dictator progress

## Completed — release v1.0.0 and DMG (2026-11-25)

- Published https://github.com/ruddvz/dictator/releases/tag/v1.0.0 with `Dictator-1.0.0.dmg` (ad-hoc signed, universal, macOS 14+, NOT notarized; SHA-256 9371bf7f…d7d1 verified after download). `Scripts/make-dmg.sh` builds it; `DICTATOR_AD_HOC=1` makes `package-app.sh` skip the local identity.
- Not verified: install of the DMG on a second Mac; whether Accessibility trust survives an update of the ad-hoc build.
- Still open: live exact-once insertion into TextEdit, a browser field and an Electron app (needs the user to hold fn and speak); stray leading "That" in Parakeet file output; language auto-detect; notarization (needs Apple Developer ID).

## Completed — one-command installer (2026-11-25)

- `Scripts/install.sh` checks macOS 14+, full Xcode (and first-launch setup), installs XcodeGen via Homebrew if missing, creates the local signing identity, builds with `package-app.sh`, installs to /Applications, verifies the signature, and opens the app. `--check` tests prerequisites only. README install section rewritten around it.
- Verified on this Mac only (identity already existed, Xcode 27.2, macOS 27): full run built, signed with the Dictator Local Signing requirement, installed and launched. NOT verified on a clean Mac with no identity, no Homebrew, or an older Xcode/macOS.
- Still open: a notarized, double-click release needs an Apple Developer ID (not available here). Until then every user builds from source.

## Completed — live audit of the packaged app (2026-11-25)

- Rebuilt with `package-app.sh` (signed "Dictator Local Signing", designated requirement unchanged), deployed to /Applications, 402 tests pass. Viewed live: Home, Insights, Style, Transforms, Files, Meeting notes, Vocabulary, Shortcuts sheet, and Settings (Dictation, Shortcuts, Cleanup, System, Appearance, Typing, Data & privacy). No old-name text appears in the UI; the "HushKey" the user saw is their own test file name. Remaining source mentions are migration code and MIT attribution.
- Finding 1 (FIXED, deployed, not yet verified on a real file in the UI): Files only offered Apple Speech or WhisperKit and ignored Parakeet (the Apple result "Hush, key" for "HushKey" was the symptom). Added `ParakeetFileTranscriber` (decodes any audio/video via AVAssetReader to 16 kHz mono, runs the loaded Parakeet model with the user's vocabulary), a `.parakeet` case in `FileTranscriptionEngine`, and made it the Files default (falls back to Apple Speech when the model isn't downloaded). Parakeet gives plain text, so SRT/WebVTT stay disabled for it. 406 tests, 0 failures. Live check still to do: choose /tmp/dictator-files-test.aiff (spoken "Vadodara and Vercel…") in Files and press Transcribe; the Open panel can't be driven from the background.
- Finding 2 (unresolved, maybe intentional): Shortcuts lists "Paste last dictation" (⌃⌘V) and "Paste again" (⌥⇧I) as near-duplicates; clarify or merge.
- Finding 3: language is fixed at en-US for an Indian-English user; Parakeet is English-only. Language auto-detect (HeyClicky parity) is open.
- Not done: live exact-once insertion into TextEdit, a browser field and an Electron app (needs the user to hold fn and speak); Settings pages were captured mid-crossfade, so transition overlap is unconfirmed; scroll smoothness, Reduce Motion, VoiceOver unchecked.

## Completed — Parakeet custom-vocabulary boosting (2026-11-25)

- Parakeet now prefers the user's vocabulary (plus built-in tech names). `ParakeetRecognizer.transcribe(_:vocabulary:)` configures FluidAudio's CTC keyword spotter and rescorer on the streaming Unified manager. The CTC model (parakeet-ctc-110m, ~98 MB, Hugging Face, stored in `~/Library/Application Support/FluidAudio/Models`) downloads automatically after the main model loads (`prepareVocabularyBoosting`). Dictation never waits on it or fails because of it. FluidAudio can't remove a vocabulary from a manager, so an emptied vocabulary rebuilds the manager.
- Live-ish check (macOS "Rishi" en-IN voice, opt-in package test `testVocabularyBoostingOnSpokenAudio`, needs `PARAKEET_MODEL_ROOT` and `PARAKEET_BOOST=1`): plain "Vadodra … the curve EV" became "Vadodara … the Curvv EV". "Wispr Flow" stays "Whisperflow" from the spotter and is fixed by the snapper. Synthetic speech only, not the user's voice.
- Fixed flaky `testEvaluationBeatsChanceOnlyWhenSignalExists` (unseeded permutations; asserted p > 0.01 on noise, failing ~1% of runs).
- Open: no Settings indicator for boosting; thresholds are FluidAudio defaults (recall-favouring), not tuned on the user's real recordings; short terms (EV) are below the spotter's 3-letter minimum.

## Completed — Parakeet first live result and snapper tolerance (2026-11-25)

- Parakeet Unified downloaded (595 MB) and ran live: 0.28 s for 5 s of audio, confidence 0.74. Spoken vocabulary test came back "E V C and Godara curve and Whisperflow" for EV/CNG/Vadodara/Curvv/Wispr Flow: Parakeet takes no hints, so the snapper is the only fix.
- `DictationVocabularySnapper` now also snaps long terms (8+ letters) heard up to two edits off with the same first and last letter ("Whisperflow", "Whisper flow" → "Wispr Flow"). 402 tests, 0 failures. Not fixed by design: short or phonetically distant terms (EV, CNG, Vadodara→"Godara", Curvv→"curve") need the user's Vocabulary entries and stay unreliable; a Parakeet custom-vocabulary (CTC boosting) path is the real fix and is not built.

## Completed — auto-download Parakeet model (2026-11-25)

- `ParakeetDictationEngine.downloadIfNeeded()` runs at launch when Parakeet is the chosen engine and no model is on disk (first run, or an upgrade that deleted v2). It downloads from Hugging Face via FluidAudio; progress and failures show in Settings. A model removed by the user (`parakeetModelRemovedByUser`) is not re-downloaded until they download it again. 401 tests, 0 failures.

## Completed — transcript-quality review from live history (2026-11-25)

- Read the 50 saved dictations (Apple Speech fallback, en-US; Parakeet Unified was not downloaded). Fillers and repeats ("Uh", "I I", "as as") are cleaned correctly. Misrecognitions seen: "Vercel"→"Vercell", "Wispr Flow"→"Whisper flow" (3×), "goated"→"voted", "end-to-end"→"and to end", "EV"→"E V" (4×), "CNG"→"CN G", Indian place and product names (Vadodara, Curvv).
- Added built-in tech names (Vercel, GitHub, TypeScript, etc.) to `DictationContextHints.builtInWords`, with a snapper test. 400 tests, 0 failures.
- Not fixed: phonetic errors (goated, Wispr, end-to-end) need a better engine, not vocabulary. Next: download Parakeet Unified, set the language to en-IN for Apple Speech, add EV/CNG/Vadodara/Curvv to the user's Vocabulary, then re-compare on the same sentences. The upgrade silently deleting the v2 model without downloading Unified is still open.

## Completed — audit follow-up: test fix and paste latency (2026-11-25)

- Fixed `testLegacyCacheCleanupRemovesOnlyFormerModelFolders`: it asserted `parakeet-ultra` was deleted and also that a file inside it survived. It now keeps an unrelated folder. Suite: 399 run, 8 skipped, 0 failures.
- Stop-to-done latency: Parakeet inference takes ~0.3–0.4 s, but the pill waited ~2.6 s more because the paste paths slept 2.5 s (`unverifiedPasteRestoreDelay`) before returning. The restore now runs in the background (`scheduleClipboardRestore`); the 2.5 s delay is unchanged, and a back-to-back paste waits for a pending restore first. Status text for those paths now says the clipboard "is put back in a moment".
- Not verified live: the packaged app was not rebuilt or run, so the new timing is unmeasured. The previously installed `/Applications` build was still on Parakeet v2, not Unified.
- Open from the audit: notarized release, Dynamic Type/Reduce Motion/VoiceOver, localization, `AppModel.swift` size (3.6k lines), Swift 6 language mode, macOS 14/15 test coverage.

## Completed — public repo and positioning refresh (2026-11-21)

- Updated the public GitHub description and topics to present Dictator as an open-source Wispr Flow alternative for macOS.
- Rewrote the README around its Mac-native hold-to-talk workflow, on-device and local speech options, review-first insertion, privacy, and source setup.
- Consolidated competitor, product-audit, and speech-model research under `docs/research/`; repaired repository links and removed local machine paths from published research.
- Replaced obsolete Claude-specific setup notes with the shared `AGENTS.md` instructions and added a documentation index.
- Documentation and repository metadata only; no app build or tests run.

## Completed — English Parakeet model update (2026-11-21)

- Reviewed current FluidAudio releases, primary benchmark material, community reports, Reddit discussion, and competing open-source defaults. The dated report is [English dictation model update](docs/research/models/english-dictation-model-update-2026.md).
- Updated the live Dictator source to FluidAudio 0.18.4 and a single on-demand Parakeet Unified EN 0.6B streaming configuration (1.12-second tier). No model weights are bundled in the app; obsolete Dictator-owned Parakeet caches are cleaned while shared FluidAudio data is preserved.
- Package unit suite: 5 passed, 2 skipped, 0 failed. Xcode build-for-testing succeeded. Real-audio accuracy, model download on the user's Mac, and live insertion were not verified; Unified remains an integration candidate rather than a proven accuracy winner over v2 or Ultra.

## Next

- Run same-device English quality/latency acceptance and live exact-once insertion across native, browser, and Electron text fields.
- Publish a packaged macOS release when Developer ID signing, notarization, and release assets are ready.
