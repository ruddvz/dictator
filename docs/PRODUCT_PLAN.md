# HushKey product and interface plan

## Product goal

Help one person test whether processed headphone motion can distinguish a small, trained set of mouthed words. Keep the experiment local, explicit, measurable, and honest when the signal is weak.

## Experience principles

- Lead with the next safe action. Start at setup, then guide the user through training, evaluation, and use.
- Keep the research controls available without making them the first thing a new user must understand.
- Make motion readiness and decoding eligibility visible in plain language.
- Separate per-word template capture from synchronized session recording; they save different data.
- Keep voice comparison, advanced thresholds, diagnostics, and Accessibility insertion optional and clearly labeled.
- Preserve macOS conventions, keyboard access, readable hierarchy, and the current appearance setting.
- Open as a standard resizable Mac window, with the menu-bar item as a secondary shortcut rather than the only way into the app.
- Never present a low-confidence nearest match as a successful word.

## Primary navigation

1. **Setup** — Motion support, permission/connection status, live sample rate, and a brief next-step guide. Detailed plots are collapsible diagnostics.
2. **Train** — Choose voice, whisper, or silent mouthing; select a word; capture examples; inspect and remove takes. Keep shortcut configuration elsewhere.
3. **Evaluate** — Select a condition and feature set; check study readiness; see leave-one-out results, majority baseline, permutation result, session holdout, and confusion matrix.
4. **Use** — Hold to capture or optionally calibrate auto-capture; inspect accepted/rejected words in a prominent transcript. Put threshold tuning, candidate distances, and voice reference under Advanced.
5. **Settings & Data** — Capture and insertion shortcuts, optional microphone reference, session recording, local data location, export, and delete controls.

## File map

- `HushKey/App/` — app lifecycle, shared state, screen routing, shortcuts.
- `HushKey/Motion/` — Core Motion access and normalized samples.
- `HushKey/Audio/` — optional local microphone input and on-device speech reference.
- `HushKey/Decoding/` — features, capture segmentation, DTW classifier, templates.
- `HushKey/Recording/` — local synchronized experiment sessions.
- `HushKey/Services/` — Accessibility insertion and system hotkey handling.
- `HushKey/Views/` — one view file per workflow plus shared visual components.
- `HushKey/Assets.xcassets/` — HushKey's app icon and bundled visual assets.
- `HushKeyTests/` — classifier, permission-state, insertion-safety, and storage tests.
- `docs/` — user build instructions, testing protocol, product plan, and licensing notices.
- `Scripts/` — deterministic icon generation and app packaging helpers; the package script builds in a temporary directory and publishes only `dist/HushKey.app`.
- `.build/` — hidden local Xcode test/build output; excluded from source control.
- `dist/HushKey.app` — the one packaged app to open.

## Current delivery sequence

- **Completed:** split the interface into Setup, Train, Evaluate, Use, and Settings & Data; make first-run guidance and decoding eligibility explicit; document the screen and source layout.
- **Completed:** opened the packaged build as a standard desktop app and confirmed the Setup window renders; Spotlight now resolves only to the canonical `dist/HushKey.app` package rather than the old visible Debug/Release copies.
- **Next:** connect compatible AirPods as the Mac's active output, verify the live stream and Motion permission, then run the study in `TESTING_PROTOCOL.md`.
- **After hardware results:** adjust thresholds or interaction only from measured false-positive and held-out accuracy results. Do not expand to free-form dictation unless evidence supports it.

## Completion checks

- A first-time user sees how to check motion before training.
- A trained word shows its sample count and can be captured without confusing it with a session recording.
- Evaluation explains what passes or blocks silent use.
- The Use screen prioritizes capture and transcript; advanced controls remain available.
- Optional microphone and Accessibility features are clearly separate from the core local motion experiment.
- Data stays local; export and deletion remain discoverable.
