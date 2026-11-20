# Dictator feature and gap audit

## What Dictator already implements

### Takeaway

Dictator already has a substantial local-first feature set: configurable global dictation, native on-device recognition, saved writing modes and per-app profiles, correction tools, selected-text editing, file transcription, meeting notes, and privacy controls. Most obvious competitor features should not be presented as new until the exact behavior is compared; the clearest product gaps are end-to-end insertion, streaming into the destination field, language convenience, and multi-file/speaker workflows.

### Cited Findings

- Dictator supports a configurable hold shortcut and press-to-toggle, review/edit/copy/guarded insert, Apple on-device streaming Speech, optional local Parakeet, several writing modes, app profiles, snippets, correction rules, raw-transcript restore, and undo — [README.md](/Users/rudra/Projects/Dictator/README.md:8).
- It already has local Transform drafts, selected-text voice editing behind explicit selection checks, one-file transcription with SRT/VTT export, meeting capture from mic/system audio/both, searchable local notes, and on-device summaries. The README explicitly says meetings have no speaker identification — [README.md](/Users/rudra/Projects/Dictator/README.md:11).
- Nearby text hints are off by default; when opted in they read a bounded slice around the cursor only from a supported field, extract terms, and discard the text — [README.md](/Users/rudra/Projects/Dictator/README.md:16), [TextInsertionService.swift](/Users/rudra/Projects/Dictator/Dictator/Services/TextInsertionService.swift:118).
- Live locale choices are built from the OS locales that support on-device recognition; the user selects a locale. WhisperKit file transcription separately exposes Auto-detect — [DictationCustomization.swift](/Users/rudra/Projects/Dictator/Dictator/TextProcessing/DictationCustomization.swift:9), [WhisperKitFileTranscriber.swift](/Users/rudra/Projects/Dictator/Dictator/Speech/WhisperKitFileTranscriber.swift:12).
- Personalization exposes manual vocabulary, snippets, and correction-rule editing/import. I found no path that automatically adds a word to recognition vocabulary after the user edits a transcript — [PersonalizationView.swift](/Users/rudra/Projects/Dictator/Dictator/Views/Hub/PersonalizationView.swift:350), [AppModel.swift](/Users/rudra/Projects/Dictator/Dictator/App/AppModel.swift:1071).

### Inferences

- The existing local/privacy position and breadth are strengths; adding screen access, chat, or agents would be a separate product expansion, not a prerequisite for matching core dictation quality.
- Dictator's existing per-app profiles and optional nearby context can support carefully bounded improvements without adding cloud accounts or persistent screen surveillance.

### Gaps

- A focused-field `AX` target and live insertion were not acceptance-tested in a real destination app for this audit; current project status explicitly still lists exact-once insertion and live permissions as open — [PROGRESS.md](/Users/rudra/Projects/Dictator/PROGRESS.md:8).

## Highest-value gaps and improvements

### Takeaway

Fix the core typing experience before expanding into agents. The initial audit's recommended local correction-learning offer is now implemented with explicit approval, dismiss, and undo. The largest remaining feature candidates are a separately opt-in streaming insertion mode with strict target validation and undo, automatic language choice, and queued file transcription.

### Cited Findings

- **P0 — insertion trust/reliability:** Dictator relies on Accessibility trust to inspect the focused control and validate the target; it refuses insertion when trust/target checks fail. That is a correct safety guard, but the project progress records unresolved live permissions and insertion — [TextInsertionService.swift](/Users/rudra/Projects/Dictator/Dictator/Services/TextInsertionService.swift:149), [PROGRESS.md](/Users/rudra/Projects/Dictator/PROGRESS.md:8).
- **P1 — stream into the destination:** Apple Speech reports partial results while listening, but README describes inserting a complete phrase after capture/review. Offer a separate opt-in mode that updates one captured field incrementally, replaces interim text safely as recognition revises it, and has an explicit undo. Do not silently submit forms or send messages — [MicTranscriber.swift](/Users/rudra/Projects/Dictator/Dictator/Speech/MicTranscriber.swift:72), [README.md](/Users/rudra/Projects/Dictator/README.md:8). This is an architectural/product recommendation, not an implemented behavior.
- **P1 — automatic language detection:** Live dictation uses a selected on-device locale; consider a detectable-language mode or a fast language confirmation step, with confidence/fallback behavior and benchmark coverage. Do not claim support merely from the model's language list — [DictationCustomization.swift](/Users/rudra/Projects/Dictator/Dictator/TextProcessing/DictationCustomization.swift:9), [AppModel.swift](/Users/rudra/Projects/Dictator/Dictator/App/AppModel.swift:1799).
- **P1 — correction learning (implemented after this audit):** A reviewed transcript edit that replaces exactly one distinctive word now offers the user a preview, explicit Add word action, dismiss, and undo. It saves only the corrected word locally. See [DictationCustomization.swift](/Users/rudra/Projects/Dictator/Dictator/TextProcessing/DictationCustomization.swift:327), [DictationView.swift](/Users/rudra/Projects/Dictator/Dictator/Views/Hub/DictationView.swift:181), and [PROGRESS.md](/Users/rudra/Projects/Dictator/PROGRESS.md:3). The helper's heuristic has unit coverage; this is not equivalent to a live dictation or UI acceptance test.
- **P2 — batch transcription:** Current file flow is documented as one audio file at a time. A queue with per-file progress, retry, and bulk subtitle/text export would fit the existing local WhisperKit path — [README.md](/Users/rudra/Projects/Dictator/README.md:14), [FileTranscriptionView.swift](/Users/rudra/Projects/Dictator/Dictator/Views/Hub/FileTranscriptionView.swift:313).
- **P2 — speaker-aware meeting notes:** Dictator can combine microphone and system audio but explicitly does not identify speakers. Optional diarization with editable speaker labels would improve meeting-note utility; make clear when labels are inferred — [README.md](/Users/rudra/Projects/Dictator/README.md:15).
- **P3 — screen-aware writing:** A one-shot “use my screen for context” command could create a reviewable draft, but needs a separate Screen Recording permission, a visible capture indicator, no default capture, and a clear retention policy. The existing context hints inspect text fields and are not equivalent to screenshots — [README.md](/Users/rudra/Projects/Dictator/README.md:16), [COMPETITOR_RESEARCH.md](/Users/rudra/Projects/Dictator/docs/COMPETITOR_RESEARCH.md:90).

### Inferences

- Ship P0 reliability first. Correction learning now provides a small reversible improvement; streaming insertion is the feature most directly connected to the user's repeated complaint that dictated text does not land in the target field. It also has the highest correctness risk, so it must be opt-in, target-validated, and covered by real app acceptance tests.
- Batch transcription and speaker labels are valuable but should follow the reliable core typing path. Screen-aware chat, pointer drawing, connected-app agents, and recurring computer-use tasks materially expand permission, privacy, and safety scope and should be treated as separate product decisions.

### Gaps

- No latency, language accuracy, insertion success rate, or competitor usability benchmark was run in this audit. Feature comparisons alone do not establish that another app is more accurate or reliable.
- Feasibility of local image understanding for screen-aware drafts, and diarization quality for Dictator's current speech stack, needs a separate technical spike before committing to implementation.

## HeyClicky-inspired scope

### Takeaway

HeyClicky ideas that fit Dictator's core are on-demand, user-controlled context and smoother speech-to-text feedback. Full-screen automation capabilities are not safe to bolt onto the dictation flow without a separate consent and review design.

### Cited Findings

- The current HeyClicky audit says its product includes on-demand screen understanding, voice/typed chat, visual pointers, and agents; it distinguishes these from Dictator's transient focused-field hints — [COMPETITOR_RESEARCH.md](/Users/rudra/Projects/Dictator/docs/COMPETITOR_RESEARCH.md:88).
- The same audit says no HeyClicky code or assets were copied and notes that screen capture and computer-use agents need separate permissions and safety controls — [COMPETITOR_RESEARCH.md](/Users/rudra/Projects/Dictator/docs/COMPETITOR_RESEARCH.md:90).
- The initial audit found no distinct additions from this comparison. A subsequent change added the explicit one-word correction-learning offer described above; other HeyClicky features were not ported — [PROGRESS.md](/Users/rudra/Projects/Dictator/PROGRESS.md:3).

### Inferences

- The best immediate remaining “HeyClicky-inspired” work is reliable live insertion and interruption-safe recovery, preserving Dictator's local-first design. Screen-aware drafting could be evaluated later as a one-shot, review-first feature; agents, visual click guidance, cloud context, and cross-app routines should not be mixed into ordinary dictation.

### Gaps

- This audit maps current Dictator implementation and gaps only. Use the adjacent HeyClicky and open-source competitor notes for the full competitor feature inventory and licenses.
