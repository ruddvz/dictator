# Design and motion pass (25 November 2026)

The owner asked for the design to be "perfected", with tasteful motion: SwiftUI-native, cheap, quick, no 3D, no video, no new dependencies. This pass started with an audit of every page and the pill. Pages were rendered with `HubSnapshotTests` and `PillSnapshotTests` at the default content width (1045 pt, from the 1277 × 888 window), and the running app's Home was captured live. Below are the findings in priority order, then what was done and what was left alone on purpose.

To render the snapshots: `TEST_RUNNER_DICTATOR_SNAPSHOT_DIR=<dir> TEST_RUNNER_DICTATOR_SNAPSHOT_WIDTH=1045 xcodebuild … test -only-testing:DictatorTests/HubSnapshotTests`. Until this pass, every snapshot test skipped with that command: xcodebuild strips the `TEST_RUNNER_` prefix before the test sees the variable, and the tests read only the prefixed name. They now read both names.

## Findings, prioritised

| # | Issue | Why it matters | Files | Status |
| --- | --- | --- | --- | --- |
| 1 | The page-title mark (`RibbonMark`) breathed forever: a 30 fps `TimelineView` + `Canvas` inside every page's scroll view. | It redraws the page header every frame while a page is open, which is the "30/60 fps candidate" in the audit and a likely cause of scroll stutter and idle CPU. `Ambient.swift` already notes that a per-frame `Canvas` costs about a fifth of a core. | `Motion.swift`, `Components.swift` | Fixed: one breath on page arrival (swell 0.38 s, settle 0.7 s), interpolated by an animatable `Shape`, then still. No clock. |
| 2 | Reduce Motion was honoured in 13 places, but about 126 animations ran springs and slides regardless. Button presses scaled even with it on. | Accessibility; the brief asks for Reduce Motion everywhere. | `Theme.swift` and every `ButtonStyle` | Fixed: `Theme.snappy`, `gentle`, `glide` (and `Motion.entrance`) become a 0.15 s ease with no overshoot when Reduce Motion is on. Press scales use `Theme.pressed(_:reduceMotion:)` and stay at 1. |
| 3 | Insights: the lead figure's sage rule pushed "Words dictated" about 6 pt below the other labels in the row. | Broken baseline in the page's most prominent row. | `InsightsView.swift` | Fixed: every figure keeps the rule's slot; only the lead shows it. |
| 4 | Home's empty history was a left-aligned note under a hairline, while Files, Meeting notes and Vocabulary use the centred `EmptyState`. A history search with no match used the system `ContentUnavailableView` in an outlined card, a third style. | Inconsistent between pages. | `DictationView.swift` | Fixed: both use `EmptyState` (clock, lock when history is off, search). |
| 5 | Copy on Home's latest dictation and on a transform preview gave no feedback. History rows and the pill already say "Copied". | No confirmation on a common action. | `Components.swift` (`CopyButton`), `DictationView.swift`, `TransformView.swift` | Fixed: `CopyButton` swaps to a check and "Copied" for 1.4 s, reserves the wider width so nothing shifts, and announces "Copied" to VoiceOver. |
| 6 | Files: the drop zone was a title, a caption and a button with a wide empty middle. It looked unfinished, and only the border answered a held file. | It's the page's main surface. | `FileTranscriptionView.swift` | Fixed: a 44 pt sage file tile (tray before a file, waveform after) that fills and lifts 2 pt while a file is held over the zone. |
| 7 | Settings: switching sections cross-faded the old and new forms with the same 8 pt offset, so two long forms overlapped mid-fade (the live audit's "captured mid-crossfade"). | Messy transition. | `SettingsView.swift` | Fixed: the old section leaves in 0.1 s (`Motion.exit`), the same as page switches; the new one settles in. |
| 8 | Pill errors appeared with the same scale-in as every other card, so a failure didn't stand apart from a notice. | A failed dictation should get a second look. | `FloatingPill.swift`, `Motion.swift` (`Nudge`) | Fixed: the error card gives one 0.37 s sideways nudge (±5 pt) when it appears and when the error changes. None with Reduce Motion. |
| 9 | Hover fades were spelled `.easeOut(duration: 0.12)` in about 20 places. | Drift; no token. | Many | Fixed: `Theme.fade`. |

## Looked at and left alone, with the reason

- **Pill states** (idle, hover, listening, held, preparing, finishing, done, meeting): already on one 28 pt capsule with spring morphs, a 120 fps live ribbon only while dictating, a spring-in check on done, and a transaction that drops all animation with Reduce Motion. Nothing in the snapshots read as broken. Only the error nudge was added.
- **Home hero**: the ambient field is already Core Animation keyframe loops that pause when the window is hidden, and the voice band already blooms on hover and with the voice. Changing it would risk the CPU work done earlier.
- **Sidebar and settings nav selection**: already a `matchedGeometryEffect` slide with an icon bounce, and both honour Reduce Motion.
- **History rows**: already slide in from the top and animate out on delete, with hover actions sliding 6 pt.
- **Toggles and pickers**: native `Toggle(.switch)` and `Menu`, tinted sage. Native motion is the right motion here.
- **Download progress**: native `ProgressView` tinted sage. It doesn't need a custom bar.
- **Insights heatmap**: the faint right-hand columns in snapshots are the staggered entrance caught mid-way, not a layout gap.
- **Onboarding**: not reachable from a set-up app without resetting state. Its code already checks Reduce Motion in 11 places.

## Not verified

- Motion can't be seen in stills. The one-shot mark breath, the Copy swap, the error nudge and the drop-zone lift were checked by reading the code and by compiling, not by watching them.
- Reduce Motion was not switched on to check live. The system setting belongs to the user.
