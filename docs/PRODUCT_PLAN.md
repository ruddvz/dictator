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

1. **Dictation** — Hold a global shortcut to talk or press it to toggle; also start/stop with the button. Choose an on-device-supported language and Natural, Message, Email, Code, or Automatic mode. Automatic maps common frontmost app identifiers when launched with the global shortcut. Review/edit the local transcript, apply explicit spoken correction cues, restore the raw recognition, expand personal snippets, copy, insert once into a supported focused field, and reload recent local transcripts. Optional nearby vocabulary hints use a bounded cursor slice only after explicit Accessibility opt-in.
2. **Transforms** — Create an editable preview for polish, concise, professional, bullet, or action-item writing with Apple's on-device Foundation Model on macOS 26+ when available. Deterministic filler removal also works without the model. Applying requires explicit user action; undo restores the prior transcript.
3. **Snippets & Vocabulary** — Search, add, edit, and remove personal expansions and local recognition hints.
4. **Transcribe files** — Import one audio file, choose Apple on-device Speech or an explicitly downloaded WhisperKit model, edit the local transcript, and export TXT, SRT, or WebVTT with timestamps.
5. **Setup** — Entered only when the user opens the Silent Lab. Motion support, permission/connection status, live sample rate, and a brief next-step guide; detailed plots stay collapsed.
6. **Train** — Choose normal voice, whisper, or silent mouthing as an experiment condition; select a word; capture, inspect, and remove motion templates.
7. **Evaluate** — Select a condition and feature set; check study readiness; see leave-one-out results, majority baseline, permutation result, session holdout, and confusion matrix.
8. **Silent Use** — Experimental trained-word decoding. Hold to capture or use calibrated auto-capture after evidence passes; inspect accepted/rejected words. Threshold tuning and candidate distances stay under Advanced.
9. **Settings & Data** — Dictation language and mode controls, spoken-correction and filler-cleanup preferences, shortcut and vocabulary hints, opt-in nearby context, transcript-history control, motion capture and insertion shortcuts, microphone input, synchronized session recording, local data, export, and deletion.

## File map

- `HushKey/App/` — app lifecycle, shared state, screen routing, shortcuts.
- `HushKey/Motion/` — Core Motion access and normalized samples.
- `HushKey/Audio/` — local microphone input, on-device speech recognition, file transcription, and local text transforms.
- `HushKey/Decoding/` — features, capture segmentation, DTW classifier, templates.
- `HushKey/Recording/` — local synchronized experiment sessions and recent dictation history.
- `HushKey/Services/` — Accessibility insertion and system hotkey handling.
- `HushKey/Views/` — one view file per workflow plus shared visual components.
- `HushKey/Assets.xcassets/` — HushKey's app icon and bundled visual assets.
- `HushKeyTests/` — classifier, permission-state, insertion-safety, and local storage tests.
- `docs/` — user build instructions, testing protocol, product plan, and licensing notices.
- `docs/research/` — the supplied Wispr Flow vs TypeWhisper PDF and a short index linking both research reports to HushKey decisions.
- `Scripts/` — deterministic icon generation and app packaging helpers; the package script builds in a temporary directory and publishes only `dist/HushKey.app`.
- `.build/` — hidden local Xcode test/build output; excluded from source control and cleared by packaging to prevent stale app copies.
- `dist/HushKey.app` — the one packaged app to open.

## Current delivery sequence

- **Completed:** make Voice/Whisper dictation the launch screen; keep Setup, Train, Evaluate, and Silent Use in a separate Silent Lab.
- **Completed:** add global start/stop dictation, live local transcription, transcript editing, copy, safe phrase insertion, recent local history, and personal vocabulary hints.
- **Completed:** add five local writing modes, common app mapping, explicit spoken correction with raw restore, optional transient nearby terms, and a focus-checked insertion undo shortcut.
- **Completed:** add conservative optional filler cleanup, snippet-line validation, Apple on-device audio-file transcription, and downloadable WhisperKit model selection with local storage and TXT/SRT/WebVTT export.
- **Completed:** add a searchable Snippets & Vocabulary workspace, searchable transcript history, and processed/raw restore actions; package only this app without deleting unrelated Xcode outputs.
- **Completed:** add review-first text transforms using Apple's on-device Foundation Model when available, deterministic filler removal on older macOS versions, explicit apply, stale-preview protection, and undo; test the offline cleanup and undo paths.
- **Completed:** defer Motion access until the Silent Lab opens; display live state and avoid presenting a failed evidence result as a pass.
- **Next:** complete manual acceptance of microphone/Speech, normal voice and whisper, global shortcuts, TextEdit and a second-app insertion/undo, history, and both file engines. Then compare Apple Speech and WhisperKit on consented local sample audio before recommending a default model. Meeting workflows remain deferred until this acceptance passes.

## Completion checks

- A first-time user can start dictating without pairing headphones or granting Motion access.
- Voice and whisper dictation can be reviewed, edited, copied, and inserted into a supported text field.
- Spoken corrections preserve a locally recoverable raw transcript; writing modes format only documented deterministic tokens.
- Nearby context remains off by default and reads only a bounded text-field slice after an explicit Accessibility opt-in.
- The dictation shortcut works while another app is frontmost.
- Recent transcripts and personal terms stay in local storage.
- The Silent Lab explains its permissions, evidence gates, and experimental limits.
- File transcription can run with Apple Speech when available or with an explicitly downloaded local WhisperKit model, and supports editable transcripts plus SRT/WebVTT export.
- Text transforms never silently replace a transcript, run without a cloud fallback, and can be undone before insertion or further editing.
- A trained word shows its sample count and can be captured without confusing it with a session recording.
- Evaluation explains what passes or blocks silent use.
- The Use screen prioritizes capture and transcript; advanced controls remain available.
- Microphone and Accessibility permissions are requested only for their corresponding features.
- Data stays local; export and deletion remain discoverable.
