# HushKey product and interface plan

## Product goal

Make ordinary voice and whispered dictation usable locally on a Mac, while keeping silent mouthing as a separate, measurable experiment. Keep private data local and be honest about the limits of each input method.

## Experience principles

- Lead with the immediately usable feature: voice and whisper dictation. Do not require headphones or Motion permission to dictate.
- Keep the silent-mouthing research controls available in a separate lab, without making them the first thing a new user must understand.
- Make motion readiness and decoding eligibility visible in plain language.
- Separate voice dictation from per-word motion training and synchronized experiment recording.
- Make dictated text reviewable and editable before safe insertion; expose copy and recent local history.
- Keep advanced thresholds and diagnostics collapsed. Explain what Accessibility insertion does before it is enabled.
- Preserve macOS conventions, keyboard access, readable hierarchy, and the current appearance setting.
- Open as a standard resizable Mac window, with the menu-bar item as a secondary shortcut rather than the only way into the app.
- Never present a low-confidence nearest match as a successful word.

## macOS visual system

- Prefer native macOS controls and materials: `NavigationSplitView`, `GroupBox`, system button styles, SF Symbols, and the user's current appearance and accent color.
- Use Dynamic Type system text styles for page titles and body copy. Keep color, motion, and custom decoration secondary to the research task.
- Show connection and permission states with a clear label and symbol; never rely on color alone. Give the current state one useful next action, such as opening Sound or Motion settings.
- Keep the app icon and menu-bar mark related: a simple H keycap with a quiet motion trace. Use the detailed, layered mark in the Dock/Finder and a monochrome template version in the menu bar.
- Keep advanced plots and thresholds collapsed until requested. Let the main window answer “what should I do next?” before showing research controls.

## Primary navigation

1. **Dictation** — Hold a global shortcut to talk or press it to toggle; also start/stop with the button. Choose an on-device-supported language, see live local recognition, edit the phrase, expand personal snippets, copy it, insert it once into a supported focused field, and reload recent local transcripts.
2. **Setup** — Entered only when the user opens the Silent Lab. Motion support, permission/connection status, live sample rate, and a brief next-step guide; detailed plots stay collapsed.
3. **Train** — Choose normal voice, whisper, or silent mouthing as an experiment condition; select a word; capture, inspect, and remove motion templates.
4. **Evaluate** — Select a condition and feature set; check study readiness; see leave-one-out results, majority baseline, permutation result, session holdout, and confusion matrix.
5. **Silent Use** — Experimental trained-word decoding. Hold to capture or use calibrated auto-capture after evidence passes; inspect accepted/rejected words. Threshold tuning and candidate distances stay under Advanced.
6. **Settings & Data** — Dictation language, shortcut and vocabulary hints, local snippets and transcript-history control, motion capture and insertion shortcuts, microphone input, synchronized session recording, local data, export, and deletion.

## File map

- `HushKey/App/` — app lifecycle, shared state, screen routing, shortcuts.
- `HushKey/Motion/` — Core Motion access and normalized samples.
- `HushKey/Audio/` — local microphone input and on-device speech recognition.
- `HushKey/Decoding/` — features, capture segmentation, DTW classifier, templates.
- `HushKey/Recording/` — local synchronized experiment sessions and recent dictation history.
- `HushKey/Services/` — Accessibility insertion and system hotkey handling.
- `HushKey/Views/` — one view file per workflow plus shared visual components.
- `HushKey/Assets.xcassets/` — HushKey's app icon and bundled visual assets.
- `HushKeyTests/` — classifier, permission-state, insertion-safety, and local storage tests.
- `docs/` — user build instructions, testing protocol, product plan, and licensing notices.
- `Scripts/` — deterministic icon generation and app packaging helpers; the package script builds in a temporary directory and publishes only `dist/HushKey.app`.
- `.build/` — hidden local Xcode test/build output; excluded from source control and cleared by packaging to prevent stale app copies.
- `dist/HushKey.app` — the one packaged app to open.

## Current delivery sequence

- **Completed:** make Voice/Whisper dictation the launch screen; keep Setup, Train, Evaluate, and Silent Use in a separate Silent Lab.
- **Completed:** add global start/stop dictation, live local transcription, transcript editing, copy, safe phrase insertion, recent local history, and personal vocabulary hints.
- **Completed:** defer Motion access until the Silent Lab opens; display live state and avoid presenting a failed evidence result as a pass.
- **Next:** in a fresh session, validate voice permission, microphone selection, transcription, shortcuts, and insertion into TextEdit and another app; then extend language choice and optional text cleanup if desired.

## Completion checks

- A first-time user can start dictating without pairing headphones or granting Motion access.
- Voice and whisper dictation can be reviewed, edited, copied, and inserted into a supported text field.
- The dictation shortcut works while another app is frontmost.
- Recent transcripts and personal terms stay in local storage.
- The Silent Lab explains its permissions, evidence gates, and experimental limits.
- A trained word shows its sample count and can be captured without confusing it with a session recording.
- Evaluation explains what passes or blocks silent use.
- The Use screen prioritizes capture and transcript; advanced controls remain available.
- Microphone and Accessibility permissions are requested only for their corresponding features.
- Data stays local; export and deletion remain discoverable.
