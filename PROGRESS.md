# Dictator progress

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
