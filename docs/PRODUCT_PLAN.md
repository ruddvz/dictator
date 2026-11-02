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
2. **Transforms** — Create an editable preview for polish, concise, professional, bullet, action-item, or up to 12 user-defined writing styles with Apple's on-device Foundation Model on macOS 26+ when available. Styles can describe tone, format, or translation and are stored on this Mac. Deterministic filler removal also works without the model. Applying requires explicit user action; undo restores the prior transcript.
3. **Snippets & Vocabulary** — Search, add, edit, and remove personal expansions, local recognition hints, and whole-word correction rules for repeat transcription mistakes.
4. **Transcribe files** — Import one audio file, choose Apple on-device Speech or an explicitly downloaded WhisperKit model, edit and export TXT/SRT/WebVTT, and search or restore up to 50 local transcript jobs. Save transcript text and timed cues only; never copy the source audio.
5. **Meeting notes** — Start microphone, system-audio, or combined capture explicitly; stream only to on-device recognition and checkpoint partial transcript text locally during capture for crash recovery. Promote the checkpoint to a searchable note at stop, then remove the temporary draft. Create reviewable on-device summaries and action items. Search/edit/export/delete locally. Audio is transient and HushKey does not provide speaker identification.
6. **Setup** — Entered only when the user opens the Silent Lab. Motion support, permission/connection status, live sample rate, and a brief next-step guide; detailed plots stay collapsed.
7. **Train** — Choose normal voice, whisper, or silent mouthing as an experiment condition; select a word; capture, inspect, and remove motion templates.
8. **Evaluate** — Select a condition and feature set; check study readiness; see leave-one-out results, majority baseline, permutation result, session holdout, and confusion matrix.
9. **Silent Use** — Experimental trained-word decoding. Hold to capture or use calibrated auto-capture after evidence passes; inspect accepted/rejected words. Threshold tuning and candidate distances stay under Advanced.
10. **Settings & Data** — Dictation language and mode controls, spoken-correction and filler-cleanup preferences, shortcut and vocabulary hints, opt-in nearby context, transcript-history control, motion capture and insertion shortcuts, microphone input, synchronized session recording, local data, export, and deletion.

## File map

- `HushKey/App/` — app lifecycle, shared state, screen routing, shortcuts.
- `HushKey/Motion/` — Core Motion access and normalized samples.
- `HushKey/Audio/` — local microphone input, exclusive capture coordination, on-device speech recognition, meeting note generation, file transcription, and local text transforms.
- `HushKey/Decoding/` — features, capture segmentation, DTW classifier, templates.
- `HushKey/Recording/` — local synchronized experiment sessions, recent dictation history, and searchable meeting notes.
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
- **Completed:** add local per-app profiles for Automatic dictation. Each profile chooses Natural/Message/Email/Code formatting and adds app-specific speech vocabulary; profiles match only the frontmost app's bundle identifier and never read its text.
- **Completed:** add conservative optional filler cleanup, snippet-line validation, Apple on-device audio-file transcription, and downloadable WhisperKit model selection with local storage and TXT/SRT/WebVTT export.
- **Completed:** add a searchable Snippets & Vocabulary workspace, searchable transcript history, and processed/raw restore actions; package only this app without deleting unrelated Xcode outputs.
- **Completed:** add user-managed local correction rules that replace complete recognized words or phrases before mode formatting and snippet expansion. Keep the raw recognition available for restoration.
- **Completed:** add validated, versioned JSON backup and import for dictation history, vocabulary, snippets, and correction rules. Imports offer merge or replace, and malformed or oversized files are rejected before data changes.
- **Completed:** add review-first text transforms using Apple's on-device Foundation Model when available, deterministic filler removal on older macOS versions, explicit apply, stale-preview protection, and undo; test the offline cleanup and undo paths.
- **Implemented; live acceptance pending:** add a dedicated hold shortcut for voice-editing selected text in another app, on-device preview, explicit Apply, and exact app/field/text/selection revalidation. Spoken instructions remain outside dictation history. Secure controls and stale targets fail closed.
- **Completed:** add up to 12 named local writing styles with validation, edit/delete, persistent local storage, and preview-first execution through Apple's on-device model. Style instructions and transcripts have no cloud fallback.
- **Completed (implementation):** add explicit microphone, system-audio, or combined meeting capture with local transcript search, editing, export, and review-first on-device summaries/action items. System audio uses a private Core Audio tap; combined capture adds the selected microphone as a drift-corrected aggregate subdevice. Each macOS permission is requested only after Start meeting. Audio is never saved. Manual source-permission and remote-call acceptance remains open.
- **Completed:** defer Motion access until the Silent Lab opens; display live state and avoid presenting a failed evidence result as a pass.
- **Next:** complete hands-on acceptance of selected-text voice edit, microphone/Speech, normal voice and whisper, global shortcuts, TextEdit and a second-app insertion/undo, history, file engines, and all three Meeting Notes sources. Then compare Apple Speech and WhisperKit on consented local sample audio.

## Completion checks

- A first-time user can start dictating without pairing headphones or granting Motion access.
- Voice and whisper dictation can be reviewed, edited, copied, and inserted into a supported text field.
- Spoken corrections preserve a locally recoverable raw transcript; writing modes format only documented deterministic tokens.
- Nearby context remains off by default and reads only a bounded text-field slice after an explicit Accessibility opt-in.
- The dictation shortcut works while another app is frontmost.
- Recent transcripts and personal terms stay in local storage.
- The Silent Lab explains its permissions, evidence gates, and experimental limits.
- File transcription can run with Apple Speech when available or with an explicitly downloaded local WhisperKit model, and supports editable transcripts plus SRT/WebVTT export.
- Meeting notes start only by explicit action, retain transcript text locally, never save microphone audio, allow searching/editing/export/deletion, and use only on-device models for generated notes.
- Text transforms never silently replace a transcript, run without a cloud fallback, and can be undone before insertion or further editing.
- Custom writing styles are bounded, locally stored, and always produce an editable preview before they can change a transcript.
- A trained word shows its sample count and can be captured without confusing it with a session recording.
- Evaluation explains what passes or blocks silent use.
- The Use screen prioritizes capture and transcript; advanced controls remain available.
- Microphone and Accessibility permissions are requested only for their corresponding features.
- Data stays local; export and deletion remain discoverable.
