# Dictator progress

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
