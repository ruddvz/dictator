# HushKey feasibility and safety protocol

## Before recording

- Use a Mac with compatible head-tracking headphones connected as its active audio output. Confirm that Setup shows **Streaming**, a nonzero sample rate, and changing motion plots in diagnostics.
- Record the headphone model as reported by the user or packaging. HushKey cannot identify the hardware model from Core Motion.
- Choose five short, distinct words or commands and keep the same vocabulary for all conditions.
- Choose a quiet location. Keep posture, headphone fit, microphone, and distance consistent. Record fit changes as separate sessions.
- For each condition, collect at least 10 templates for every word. Use at least two separate session IDs; do not use templates from the held-out session during training.

## Conditions

Run the same randomized word list separately for:

1. Normal voice
2. Whisper
3. Silent mouthing

Do not mix templates from conditions in an evaluation. The decoder uses Silent templates only.

## Required reports

For acceleration, rotation, attitude, and combined features, capture:

- Leave-one-out accuracy and the majority-class baseline.
- Confusion matrix.
- 500 label-permutation runs, including the 95th percentile and p-value.
- Leave-one-session-out accuracy and the training-fold majority baseline.
- Number of words, takes per word, sessions, condition, sample rate, and headphone fit notes.

Treat a condition as promising only when accuracy exceeds its baseline, the permutation test is significant (`p < 0.05`), and the held-out session also beats its baseline. A failed check means the current motion features do not show reliable evidence for that user's data; do not tune the thresholds to conceal that result.

## False-positive controls

Record labeled segments during:

- Quiet rest with no mouthing.
- Looking left/right, nodding, and ordinary conversation without target words.
- Chewing and swallowing.
- Adjusting or reseating the headphones.

Report how many segments are triggered and accepted. Repeat after reseating the headphones. Auto-detection is a separate experiment from word classification; a segmentation success is not evidence of word recognition.

## Data handling

Start a session recording explicitly. If the microphone is active, audio is stored locally alongside motion for later alignment. Export only when needed, and delete logs or templates from the Local data & privacy panel when finished. Do not share recordings without consent from everyone recorded.

## Voice dictation acceptance

Run this separately from the AirPods motion study:

1. Start from the packaged `dist/HushKey.app`; grant Microphone and Speech permissions only if the user wants live dictation. Confirm the selected language supports on-device recognition.
2. Dictate one short normal-voice phrase and one whispered phrase. Stop immediately after the final word and confirm the app finishes recognition instead of dropping the last partial result.
3. Try an explicit “scratch that” correction, restore the original recognition, and confirm history keeps the processed text and raw text separately.
4. Test Code formatting in a code editor and the Automatic mapping from TextEdit, Mail, Messages, and an editor using the global shortcut. Confirm the last-capture status shows the selected mode and app.
5. Leave nearby text hints off first. If the user enables them, grant Accessibility access separately, confirm a supported non-secure text field is required, then verify HushKey only reports extracted terms and saves no surrounding text.
6. In TextEdit and one other supported app, insert once, confirm the clipboard did not change, then press `⌥⇧U` immediately while the same field is unchanged. Confirm that the insert is removed; change focus or edit the field and confirm undo fails closed.
7. Reload the local history entry, restore raw recognition, clear the current draft, and clear history. Confirm microphone audio is never stored by ordinary dictation.

## Local file transcription acceptance

1. Import a short consented audio file and transcribe it with Apple Speech. Confirm HushKey refuses remote fallback when the selected language lacks on-device support.
2. Edit the transcript, save TXT, and export SRT and WebVTT. Check subtitle timestamps against the source audio and confirm the source file remains unchanged.
3. Confirm a completed job appears in searchable Recent file transcripts. Edit its text, switch screens, return, restore it, and verify the edited text and original timed cues remain. Choose a second source file and verify the first job remains recoverable.
4. Delete one saved job, then clear all saved file transcripts. Confirm deletion persists after reopening HushKey and that source audio was never copied into Application Support.
5. Choose a WhisperKit model and explicitly download it. Verify the download state reaches completion and the model appears in `~/Library/Application Support/HushKey/WhisperKitModels/`.
6. Disconnect from the network after download and transcribe a local file with WhisperKit. Reopen HushKey to confirm the model remains available, then remove it and confirm the model files are deleted.
7. Repeat with files of increasing length. Watch memory use and report engine, model variant, language, file duration, first-run download time, transcription time, and qualitative errors. Do not claim a model is more accurate without a representative benchmark.

## Meeting notes acceptance

1. Start capture explicitly and grant only the selected source's permission (Microphone/Speech, System Audio Recording/Speech, or both for Both sides). Confirm no capture begins merely by opening the page, selecting a note, or opening the menu-bar item.
2. Use the configured microphone for a short consented conversation. Confirm the live transcript updates, stop produces a saved note, and microphone audio is not present in HushKey's Application Support data.
3. Edit the title and transcript, search for text in the transcript, export transcript and all notes as TXT, restart HushKey, and confirm the edited note is still available.
4. With Apple's on-device model available, create summary and action-item drafts, edit them, and confirm they persist locally. Include a transcript longer than 12,000 characters to verify chunking. With the model unavailable, confirm the app explains that it did not send transcript text elsewhere.
5. Start dictation and meeting capture in both orders; verify the capture gate prevents two microphone engines from starting. Test stop during speech and confirm final words are retained.
6. On macOS 14.2 or later, choose System audio and capture a short consented call/test sound. Confirm the System Audio Recording prompt appears only after Start meeting, remote app playback is recognized, and microphone speech is not included unless it is played into system output.
7. On macOS 14.2 or later, choose Both sides. Confirm the microphone prompt appears only after Start meeting, speak into the selected microphone while playing a separate consented voice from an app, and verify both are represented in one transcript. Stop and confirm the audio engine/tap ends and the capture gate is released. Confirm a denied microphone or System Audio Recording permission stops capture, releases the gate, and leaves System audio-only capture available. Repeat with audio routed to headphones and speakers. HushKey does not provide speaker labels.
8. With Accessibility insertion enabled, press the global insert shortcut from Meeting Notes, Files, Settings, and Snippets/Vocabulary; it must not insert an old Silent Lab prediction. Press it from Silent Use with an accepted prediction; confirm it inserts that prediction once. Confirm insertion is blocked during meeting capture.

## Build and test

Run `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`. Unit tests use synthetic signals and verify classifier behavior, capture segmentation, permission/connection state transitions, dataset persistence, and secure-target insertion guards. They do not emulate AirPods or prove real-world feasibility.
