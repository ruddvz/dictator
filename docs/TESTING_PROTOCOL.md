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

## Build and test

Run `xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build test`. Unit tests use synthetic signals and verify classifier behavior, capture segmentation, permission/connection state transitions, dataset persistence, and secure-target insertion guards. They do not emulate AirPods or prove real-world feasibility.
