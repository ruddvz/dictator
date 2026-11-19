# Dictator: end-to-end audit brief (for Antigravity or any coding agent)

Paste everything below the line into the agent.

---

You are taking over quality work on **Dictator**, a local-first macOS dictation app (Swift 6, SwiftUI + AppKit, macOS 26, Apple Silicon). Your job is an **end-to-end bug hunt, critique and polish pass** whose bar is "Apple quality, as smooth as Wispr Flow". Find real defects, fix the ones you can verify, and report the rest with evidence. Don't redesign the product, and don't remove features.

## 1. Repo, branch and rules (read first)

- Repo: `~/Projects/Dictator` (GitHub `ruddvz/dictator`, private). Work on **`main`** (everything is merged there; there are no feature branches). Push small commits straight to `main`.
- Read `AGENTS.md`, `CLAUDE.md`, `PROGRESS.md` (newest entries first) and `docs/DESIGN_SYSTEM.md` before touching code.
- Before starting: `git pull --ff-only`. If another agent may be editing, work in a worktree: `git worktree add ../Dictator-<task> -b <you>/<task>`. Never use bare `git stash`. Commit small, focused changes with clear messages. Record what you did and what's next at the top of `PROGRESS.md`.
- GitHub Actions is deliberately broken (billing). Ignore the red `build-test` check, and verify on this Mac instead.
- **Licences:** never copy GPL code (TypeWhisper, VoiceInk, FluidVoice, MacParakeet). MIT code (FreeFlow, OpenWhispr, OpenTypeless, amirrsyed/hushkey) may be adapted with attribution in `NOTICE.md`. Wispr Flow is closed: match behaviour and measurements, not assets or copy.
- **Product rules:**
  - Everything stays on this Mac (no network calls for user data).
  - fn (Globe) is the default dictation key.
  - Sage `Theme.signal` is the only accent, and there are no hard-coded colours (use `Theme.swift` tokens).
  - `BreathRibbon` is the one voice form everywhere: no level bars.
  - Keep the hub (main window), Silent Lab, Meeting notes and every existing setting.
- Don't change macOS privacy permissions yourself. Ask the user to approve prompts.

## 2. Build, test, run

```bash
osascript -e 'quit app "Dictator"'        # a running copy can abort the test run
xcodegen generate
xcodebuild -project Dictator.xcodeproj -scheme Dictator -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
Scripts/package-app.sh && open dist/Dictator.app
```

- The baseline is 317 tests, 3 skipped, 0 failures. Keep it green, and add tests for any logic you fix.
- `package-app.sh` signs with the local "Dictator Local Signing" identity, so Accessibility permission survives rebuilds. Only one Dictator may run at a time, and only one dictation app may own fn: quit TypeWhisper and Wispr Flow while testing.
- Use `open`, never the raw binary, or microphone and speech permission won't stick.
- Unit tests don't prove that the mic, text insertion or permissions work. Say exactly what you checked live and what you didn't.
- **Logs** (use `/usr/bin/log`; in zsh, `log` is a builtin):
  - `/usr/bin/log show --predicate 'subsystem == "com.ruddvz.dictator"' --last 10m --style compact`
  - Categories: `start` (per-step dictation start timing and pill phase changes), `insertion` (focus and insert results), `parakeet` (confidence, peak, auto-insert), `shortcut`.

## 3. Architecture map

| Area | Files |
|---|---|
| App, state, dictation flow | `Dictator/App/AppModel.swift` (3,100 lines: `startDictation`, `stopDictation`, `finish…`, cancel/retry, Dock policy), `DictatorApp.swift` (scenes, menu bar menu, app delegate), `StartTiming.swift` |
| fn / shortcuts | `Services/FunctionKeyMonitor.swift` (pure `FunctionKeyGesture` state machine: 120 ms hold delay, tap, double-tap hands-free), `App/KeyCombo.swift` |
| Audio | `Audio/AudioService.swift` (AVAudioEngine built/started/stopped on a serial queue; `AudioLevelMailbox` at 30 Hz), `SpeechEnvelope.swift`, `OutputMuter.swift`, `DictationSounds.swift` |
| Recognition and cleanup | `Audio/ParakeetDictationEngine.swift`, `MicTranscriber.swift` (Apple Speech preview), `DictationCleanup.swift` (fillers, self-corrections, Apple Intelligence delete-only polish), `DictationCustomization.swift` |
| Insertion | `Services/TextInsertionService.swift` (AX set-text, paste fallback with verification) |
| Recovery and review | `Recording/DictationRecovery.swift` (`DictationNotice`, `ParakeetAutoInsertGate`: peak ≥ 0.06 and confidence ≥ 0.35, `TranscriptCard`) |
| Pill | `Views/FloatingPill.swift` (non-activating panel, fixed minimum 220 × 84 transparent frame, phases idle / hover / preparing / listening / finishing / error / done, Flow-style notice card, `CountdownCloseButton`) |
| Hub | `Views/ContentView.swift` (sidebar + sheet), `HubToolbar.swift` (theme, notices bell, profile), `TrafficLightInset.swift`, `DictationView.swift` (home), `InsightsView.swift`, `SettingsView.swift`, `OnboardingView.swift` + `Onboarding/OnboardingFlow.swift`, `HushIcons.swift` (native SF Symbols), `Ambient.swift` (`BreathRibbon`, `AmbientField`) |
| Silent Lab | `Decoding/*`, `Motion/HeadphoneMotionService.swift`, `Views/TrainView.swift`, `EvaluateView.swift`, `UseView.swift`, `SetupView.swift` |
| Storage | `Recording/LocalJSONArchive.swift`, `SessionRecorder.swift`, `DictatorPersonalDataBackup.swift`, `VoiceProfile.swift` |

Reference docs: `docs/DESIGN_SYSTEM.md` (tokens, measured Flow layout), `docs/WISPR_FLOW_FULL_AUDIT.md` (ranked gaps against Flow), `docs/PILL_UX_ANALYSIS.md`, `docs/research/INSTANT_START_AND_MENU_BAR.md` (how TypeWhisper, FreeFlow, OpenWhispr and VoiceInk start instantly; menu and pill geometry), `docs/TESTING_PROTOCOL.md`.

## 4. State as of 2026-11-04

**Recently done:**
- The pill's meter is the breath ribbon again.
- The fn start is smooth: no panel resize, the audio engine runs off the main thread, the hint is delayed 600 ms. Typical fn → listening is now about 220–330 ms. The user confirmed the start works.
- Typing is restored (the review gate floor was too high).
- Flow-style notice card with a countdown ring.
- Flow-matched title strip (traffic lights 21 pt down; icons at 99 / 94 / 58 / 22 pt).
- Menu bar first: the Dock icon shows only while the hub is open.
- History rows: hover pill, ⋯ menu, delete with Undo, expand, meta line.
- Settings split, plus a shortcut recorder, a paste-last shortcut and history retention.
- Voice profile and time saved.
- A 60-second first run.

**Never verified by eye:** the notice card and its countdown ring, the copy card, the Dock icon leaving when the window closes, light mode of the new title strip, History rows, the Settings split, the shortcut recorder, onboarding (including permission prompts), VoiceOver, unplugging the mic mid-dictation, AirPods, and Silent Lab end to end.

**User complaints still open:**
1. The app isn't at "Apple grade". Margins, spacing, sizes and placement still feel slightly off next to Flow, especially in the hub.
2. Smoothness and motion everywhere.
3. They want TypeWhisper's lightness: one menu bar icon that does everything, with no window needed.
4. The copy / no-text-box card design. The user will share a screenshot of what they want.

## 5. What to do, in order

1. **Baseline.** Pull, build, test, package and launch. Record the start-timing logs for five fn holds. Confirm none shows `micOpen` above about 350 ms on the built-in mic.
2. **Live acceptance**, with the user doing the speaking and clicking:
   - Hold fn in TextEdit, Notes, Safari, Slack and Claude; check the text lands and is cleaned up ("um so I need to leave at four PM no actually 5 PM" → "I need to leave at 5 PM").
   - Hands-free (double-tap fn), Esc cancel → Undo, near-silence (no invented text), mic unplugged mid-dictation, no focused field (copy card), a permission revoked.
   - Record pass/fail in `docs/TESTING_PROTOCOL.md`.
3. **Bug hunt** (read code and reproduce):
   - Races between the start, stop, cancel and retry generations (`dictationStartGeneration`, `AudioService.startGeneration`, `stopsWhenStarted`).
   - Engine shutdown on the queue racing a fast restart.
   - The pill's panel frame on multiple displays and when the Dock is on the left or right.
   - Whether clicks through the pill's transparent 220 × 84 area really pass to the app underneath (test by clicking just above the idle pill).
   - Dock policy flicker when Settings or sheets open.
   - Insertion into secure fields (must refuse), Electron apps, terminals, and web text areas.
   - Memory and CPU at idle (the hub's `AmbientField` should do no per-frame work when hidden).
   - Crash-safety of the JSON archives.
   - Anything that blocks the main thread over 16 ms during dictation.
4. **Polish against Flow.** Put Wispr Flow's hub and Dictator's side by side at the same window size and measure: sidebar row height and font size, icon size, logo lockup, content panel insets and radius, card padding, list row height, section headers, empty states, popovers. Fix differences only where Flow is clearly better, and keep Dictator's Fog & sage identity. Do the same for the pill (idle, hover, recording, notice, copy card) and its motion: springs and timings are in `docs/research/INSTANT_START_AND_MENU_BAR.md`.
5. **Menu bar first, completed.** Extend the menu bar menu toward TypeWhisper's structure (behaviour only):
   - A status line first, then Start/Stop.
   - Microphone, Language and Model submenus.
   - History, Transcribe file, Recover last recording, Last transcription (copy / paste), Pause shortcuts, Settings, Quit.
   - The menu bar glyph shows recording (sage or red-tinted) and transcribing states.
6. **Instant start, phase two** (optional, measure first): prepare the audio engine at idle for built-in and USB mics only (never Bluetooth or AirPods, which would force HFP). It expires on device change, sleep and screen lock.
7. **Report.** Write `docs/AUDIT_<date>.md` with:
   - Every finding: severity (P0–P3), file and line, how to reproduce, and fixed or not.
   - Before/after screenshots at 1× for UI changes.
   - What was verified live versus by tests only.

   Update `PROGRESS.md`, commit, and push to `main`. Summarise the changes for the user.

## 6. Definition of done

- Tests are green, and new logic has tests.
- Packaged app checked live for every change, and anything unchecked is said plainly.
- No main-thread stall over 16 ms in the dictation path.
- No hard-coded colours, no GPL code, and no removed features.
- The user agrees the pill and hub feel as smooth and as carefully spaced as Wispr Flow.
