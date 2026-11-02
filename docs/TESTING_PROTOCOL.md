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
4. Add a local correction such as `Hush Key => HushKey`. Dictate the phrase with punctuation and within a longer word; confirm only complete phrase matches change, the raw transcript remains untouched, and Restore original recognition returns the uncorrected words. Delete the rule and confirm it no longer applies.
5. Test Code formatting in a code editor and the Automatic mapping from TextEdit, Mail, Messages, and an editor using the global shortcut. Confirm the last-capture status shows the selected mode, app profile, and app name when a profile is configured.
6. Leave nearby text hints off first. If the user enables them, grant Accessibility access separately, confirm a supported non-secure text field is required, then verify HushKey only reports extracted terms and saves no surrounding text.
7. In TextEdit and one other supported app, start dictation with the target field focused using the global shortcut, finish, then use the Dictation screen's named-target Insert button. Confirm HushKey returns to that app and inserts once only if the same field and selection remain unchanged. Change the target or field contents before pressing the button and confirm it fails closed. Also insert with the global `⌥⇧I` shortcut, confirm the clipboard did not change, then press `⌥⇧U` immediately while the same field is unchanged. Confirm undo removes the insert; changed focus or content must fail closed. If direct typing is declined, verify paste fallback is offered only for a readable supported text field and never for a button, other non-text control, or secure/password field. Confirm a delayed text-field update is accepted only when the exact expected contents appear in the original field; if verification times out or focus/content changes, the app must report uncertainty, keep the transcript available, restore the clipboard only when unchanged, and require the user to inspect the destination before an explicit retry.
8. Reload the local history entry, restore raw recognition, clear the current draft, and clear history. Confirm microphone audio is never stored by ordinary dictation.
9. During a new live dictation, confirm the History options menu is disabled. Stop and let finalization finish, then delete history; confirm the archive stays empty after reopening HushKey.

## Selected-text voice-edit acceptance

1. Enable text insertion and Accessibility. In TextEdit, select a short non-secure phrase and hold the configured voice-edit shortcut (`⌥⇧E` by default); speak one clear instruction and release. Confirm the live capture stops and the instruction appears in **Transforms**, not dictation history.
2. Confirm only the selected phrase is shown as source. Preview the edit and verify the source stays unchanged. Edit the recognized instruction and confirm the old preview is invalidated. Confirm HushKey uses Apple's on-device model only and gives a clear unavailable message without a remote fallback.
3. Apply once. Confirm only the original selection is replaced, then use `⌥⇧U` in the same unchanged field to undo. Confirm changed focus, field contents, selection, process, or a secure/password field prevents replacement.
4. Try the shortcut without a selection, in an unsupported control, after denying Accessibility, and while meeting capture is active. Confirm no text is read or replaced, no competing audio engine starts, and the UI explains what to do next. Confirm the spoken instruction and selected text are not written to history or audio files.

## Local writing style acceptance

1. With Apple's on-device language model available, create a named writing style such as a warm concise tone or a translation instruction. Confirm blank/overlong names and instructions are rejected, duplicate names are blocked, and no more than 12 styles can be saved.
2. Preview the style on a transcript. Confirm the draft is editable, the source transcript remains unchanged until Apply, changed source text invalidates the preview, and Undo restores the original.
3. Quit and reopen HushKey. Confirm styles remain available on this Mac; edit and delete one, then confirm the changes persist. Confirm no style or transcript is sent to a cloud service.
4. When Apple's model is unavailable, confirm custom styles explain that a local model is unavailable and do not run a remote fallback. Deterministic filler removal should still work.

## Local file transcription acceptance

1. Import a short consented audio file and transcribe it with Apple Speech. Confirm HushKey refuses remote fallback when the selected language lacks on-device support.
2. Edit the transcript, save TXT, and export SRT and WebVTT. Check subtitle timestamps against the source audio, confirm no cue extends past the media duration, and confirm the source file remains unchanged.
3. Confirm a completed job appears in searchable Recent file transcripts. Edit its text, switch screens, return, restore it, and verify the edited text and original timed cues remain. In a disposable data folder, induce a history-save failure while the transcript is edited, choose a second source file, and confirm the source and transcript stay unchanged. After a successful save, choose the second source and verify the first job remains recoverable.
4. Delete one saved job, then clear all saved file transcripts. Also start a transcription and clear history before it finishes; confirm the running job remains exportable but never repopulates Recent file transcripts. Confirm deletion persists after reopening HushKey and that source audio was never copied into Application Support.
5. Choose a WhisperKit model and explicitly download it. Verify the download state reaches completion and the model appears in `~/Library/Application Support/HushKey/WhisperKitModels/`.
6. Disconnect from the network after download and transcribe a local file with WhisperKit. Reopen HushKey to confirm the model remains available, then remove it and confirm the model files are deleted.
7. Repeat with files of increasing length. Watch memory use and report engine, model variant, language, file duration, first-run download time, transcription time, and qualitative errors. Do not claim a model is more accurate without a representative benchmark.

## Meeting notes acceptance

1. Start capture explicitly and grant only the selected source's permission (Microphone/Speech, System Audio Recording/Speech, or both for Both sides). Confirm no capture begins merely by opening the page, selecting a note, or opening the menu-bar item.
2. During “Getting ready,” cancel setup or dismiss/deny a pending macOS permission request. Confirm the startup indicator ends, the shared capture gate is released, and a late permission grant does not begin capture. Retry after the permission choice and confirm the app remains usable.
3. Use the configured microphone for a short consented conversation. Confirm the live transcript updates, stop produces a saved note, and microphone audio is not present in HushKey's Application Support data.
4. Edit the title and transcript, search for text in the transcript, export transcript and all notes as TXT, restart HushKey, and confirm the edited note is still available.
5. With Apple's on-device model available, create summary and action-item drafts, edit them, and confirm they persist locally. Include a transcript longer than 12,000 characters to verify chunking. With the model unavailable, confirm the app explains that it did not send transcript text elsewhere.
6. Start dictation and meeting capture in both orders; verify the capture gate prevents two microphone engines from starting. Test stop during speech and confirm final words are retained.
7. On macOS 14.2 or later, choose System audio and capture a short consented call/test sound. Confirm the System Audio Recording prompt appears only after Start meeting, remote app playback is recognized, and microphone speech is not included unless it is played into system output.
8. On macOS 14.2 or later, choose Both sides. Confirm the microphone prompt appears only after Start meeting, speak into the selected microphone while playing a separate consented voice from an app, and verify both are represented in one transcript. Stop and confirm the audio engine/tap ends and the capture gate is released. Confirm a denied microphone or System Audio Recording permission stops capture, releases the gate, and leaves System audio-only capture available. Repeat with audio routed to headphones and speakers. HushKey does not provide speaker labels.
9. During a longer meeting, wait for the local transcript to update, then force quit HushKey. Reopen Meeting notes and confirm the partial transcript is offered as a recoverable draft, can be saved as a note or explicitly discarded, and no audio file was written. In a separate run, stop normally and confirm the temporary draft is removed after the note is saved.
10. With Accessibility insertion enabled, press the global insert shortcut from Meeting Notes, Files, Settings, and Snippets/Vocabulary; it must not insert an old Silent Lab prediction. Press it from Silent Use with an accepted prediction; confirm it inserts that prediction once. Confirm insertion is blocked during meeting capture.

## Personal data backup acceptance

1. Save a dictation with a processed/raw difference, then add vocabulary, a snippet, a correction rule, a custom writing style, and an Automatic app profile with at least one override. Export **Settings → Data & privacy → Your files → Personal data backup** and confirm the version-3 JSON contains these items, the profile refers to its style, and no audio or app text is included.
2. Import the file into a second HushKey data folder or a clean test account. Choose Merge and confirm it adds missing entries while keeping local entries with matching IDs/cues and local profiles with matching bundle identifiers. Confirm an imported profile that names a style conflict points to the retained local style. Confirm history remains capped at 50.
3. Import again and choose Replace. Confirm the confirmation lists the data counts and that replacement changes dictation history, vocabulary, snippets, corrections, writing styles, and app profiles.
4. Import version-1 and version-2 backups; confirm both are accepted and Replace preserves local app profiles. Version 1 preserves local styles; version 2 replaces them. Try a non-HushKey JSON file, an unsupported version, malformed rules/profile fields, and a file over 10 MiB. Confirm each is rejected before local data changes.
5. In a disposable test account, corrupt the local dictation-history JSON and relaunch. Confirm HushKey shows a recovery copy path, blocks export of incomplete history, and can replace the archive only after a valid backup is selected and confirmed. Verify the recovery copy still contains the original bytes.

## Build and test

Run `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`. Unit tests use synthetic signals and verify classifier behavior, capture segmentation, permission/connection state transitions, dataset persistence, and secure-target insertion guards. They do not emulate AirPods or prove real-world feasibility.
