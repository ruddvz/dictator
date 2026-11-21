# Dictator product audit — 2026-11-20

## Scope and evidence

Reviewed the current SwiftUI source for Home, Insights, Style, Transforms, Files, Meeting notes, Vocabulary, Settings, Silent Lab, onboarding and the floating dictation/meeting controls. Checked visible copy, action labels, text editors, navigation, permission messaging, page-width rules and known scrolling paths. The working tree was clean at the start of the audit.

The live app remained installed and running at `/Applications/Dictator.app`; this review did not change its installation, Accessibility grants, or stored user data. I visually inspected the live Settings and Home surfaces at 512 px. The app's macOS Accessibility API is unavailable to this audit process, so I could not automate a trustworthy click-through of every live tab. Static source review is broader than the live visual review.

## Changes made

- Settings now shows the path of the exact running app bundle instead of assuming the app is installed at `/Applications/Dictator.app`. The path can be selected and copied.
- Added VoiceOver names and short hints to the Home, transform, file-transcript, meeting-note, vocabulary, correction-rule and app-specific snippet editors. Silent Lab's collapsed icon now announces its name and expanded state.
- The training-take Delete button is now named for VoiceOver and becomes visible when keyboard or accessibility focus reaches it.
- Renamed the remaining user-facing `Hush Key` correction example to `Dictator`.
- Changed the setup action from **Enable typing** to **Open typing settings** because it navigates to Settings and does not change the switch itself.
- Clarified file-export behavior: SRT and WebVTT keep the original recognized wording and timing; **Save text** includes the user's edits. This avoids implying that edits currently rewrite the timed subtitle cues.

No features were removed. The shared page layout still uses a 1,040 pt maximum width for all hub tabs; the source does not contain the page-specific width mismatch described earlier. The actual full-window proportions of every tab still need visual acceptance.

## Remaining checks

- Scrolling smoothness has not been measured. Source inspection found lazy history lists and continuous 30/60 fps animation candidates; neither proves the reported stutter or identifies its cause. A live scroll profile is still needed.
- SRT/WebVTT exports do not apply edits from the full transcript editor to the original timed cues. This is now explicit in the UI; a separate timed-cue editing/synchronization flow would be needed to change that behavior safely.
- Only Settings and Home received live screenshots in this pass. A complete page-by-page visual sign-off, including reduced-motion, VoiceOver, narrow-window and large-window behavior, remains open.
- No ASR model was promoted. See [Voice model versions](../models/voice-model-versions.md) for Parakeet, Wispr Flow and alternative-model research plus a benchmark/update gate.

## Reference lens

[Hallmark v2](https://github.com/Nutlope/hallmark) is a design skill with an audit mode and screenshot-based review. I reviewed its public approach and applied the relevant checks manually; its audit command is not installed as a callable tool in this workspace. [Wispr Flow's accessibility guide](https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow) also informed the editor and focus-label pass.

## Verification

- Full macOS suite: **374 passed, 8 skipped, 0 failed** on macOS 27.0.1.
- `git diff --check`: passed.
- User-confirmed exact-once insertion is recorded in the current repository status; this pass left the working installed copy and its permissions untouched.

## Next fresh session

Profile scrolling while the Home and history pages are moving, then perform live visual/VoiceOver acceptance across every tab. Separately benchmark Parakeet Ultra, Moonshine and Nemotron candidates against the same consented local speech set before changing any default.
