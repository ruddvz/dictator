# UI and copy polish audit (4 November 2026)

To review a screen, run `HubSnapshotTests` or `PillSnapshotTests` with `TEST_RUNNER_DICTATOR_SNAPSHOT_DIR=<dir>`. They write PNGs of 8 hub screens (light and dark) and every pill phase. The audit was made from those renders against `docs/DESIGN_SYSTEM.md`.

## Done (on main)

- **Pill:** a `Metrics` grid (28 pt capsule, 20 pt controls, 4 pt inset, 8 pt gaps); × and ✓ glyphs of matching weight; a neutral disabled ✓; the Meeting notes button now uses the pill's material; quieter hint; no sideways jump on hover; the timer gets its own slot; the Typed check springs in.
- **Copy:** notices, the pill, the menu bar (title case) and Home prompts rewritten in one voice.
- **Visual:** empty ring (`HushIcon.ring`) for unselected cards; light `ink3` now quieter than `ink2`; light `signal` darkened for AA contrast on buttons; Style cards are equal height; fixed truncation in Remove fillers and Voice profile; group titles flush; Meetings menu width matches.

## Voice guide

1. Calm and plain. Speak to "you"; the app is "Dictator", never "we".
2. Outcome first, then one next step. Errors are two short sentences at most, with no internal values (confidence, AX, Core ML, raw errors).
3. In-window buttons, titles and toggles use sentence case and start with a verb. Menu bar and context-menu items use title case.
4. One name per feature (table below). Paths use ›, for example Settings › Typing.
5. Helper text is one sentence of 20 words or fewer, ending with a full stop. Tooltips have no full stop.
6. Use … only when more input follows. Use curly ’ and “ ” throughout, and contractions ("Couldn’t").
7. Say "on this Mac" once per screen, not in every row.

## Naming (unified on 2026-11-08; Settings › Cleanup kept, to avoid two things called Style)

| Concept | Use | Still varies in |
|---|---|---|
| Home page | Home | sidebar "Dictation" (AppModel.swift:26), "Go to Dictation" (TransformView), "the Dictation page" (SettingsView) |
| Typing into apps | Typing | Settings section "Insertion", "Turn on insertion" (ContentView, HubToolbar), "Text insertion is off." (TextInsertionService) |
| One history item | Dictation | "Latest dictation" vs "Paste last transcript" (HubToolbar, SettingsView), "Keep recent transcripts" |
| Paste last again | Paste Again | "Insert again" (HubToolbar, SettingsView) |
| Cleanup page | Style | page title "Style & Cleanup"; Settings "Cleanup" duplicates it |
| Vocabulary page | Vocabulary | "Snippets & Vocabulary", "Vocabulary & snippets", "Vocabulary and snippets" |
| Settings | Settings | "Settings & Data" |
| Lab | Silent Lab | "Silent lab" (ContentView, HubToolbar) |

The sidebar name should match the page title.

## Visual fixes (ranked; all 14 done on 2026-11-08)

1. **Insights:** the heatmap legend uses ink greys while the cells are sage. Use `signal.opacity(0.3 + 0.7·level)` (InsightsView ~160).
2. **Transforms:** Make concise, Bullet points and Action items share one glyph (`.list`). Give each its own icon (LocalTransformService 19–22, HushIcons 74/79).
3. **Settings/Files:** the Language control lacks `MenuPicker` chrome (LanguagePickerView 15).
4. **Settings:** "Download model" sits on its own row. Make it the trailing control of the Parakeet row (DictationEngineSettings 24–45).
5. **All pages:** header trailing actions are centred on title + subtitle. Align them to the title line (Components 12, DictationView 51).
6. **Files/Transforms:** the header→content gap is `s6`; other pages use `s5`. Move the gap into `PageHeader`.
7. **Home:** the hero radius is `r1` but the stats card is `r2`. Use one. Hero display 30 and 28 padding are off-scale; use `hkTitle1` and `s5` (DictationView ~603–643).
8. **Style:** example boxes use `r2` inside `r2` cards. Use `r3` inside so the corners are concentric (StyleView 174/216).
9. **Personalization:** banner title display(26) is off-scale. Use `hkTitle2` (PersonalizationView 223).
10. **Tabs:** the selected label changes weight and reflows by about 2 pt. Reserve the width; show counts in `ink3` and hide them at 0 (Components 290).
11. **Insights:** uppercase meta labels. Use sentence case `hkMeta` `ink2` (InsightsView 130/151/179/320). The WPM card shows 0 next to "–", has no divider, and relies on a magic offset (58–67). The subtitle has a stray capital (15). The "count as Other" note shows with no data (140).
12. **Transforms:** the badge is off-token and faint in dark mode. Use `hkMeta.medium`, `ink2`, `s2` padding (TransformView 605).
13. **Settings:** row details wrap unevenly. Cap the detail column at 440 (Components 136–141).
14. Off-scale values: Components 92, 101, 133, 148/166, 245, 339; DictationView 284, 321. Also no-op ternaries at Components 469 and FileTranscriptionView 154.

## Systemic (fix once)

- **One `SelectableCard`** to replace CleanupLevelCard, ToneCard and TransformCard: equal heights, `r3` inner radius, ring/check glyphs, one fill.
- **One section header:** `hkTitle3` for page sections, `SectionLabel` (on `hkMeta`) only inside cards.
- **One card surface:** `card(style:)` with a hairline. A borderless `well` on light `paper` is 1.04:1 and nearly invisible.
- **One empty state:** `EmptyState` takes a custom icon view, so Home's hand-rolled empty history can use it.
- **Page rhythm:** `PageHeader`/`pageLayout` owns the header gap and action alignment.
- **Controls:** `MenuPicker` should use `hkControl`, the same as buttons.

## Remaining copy

- Pill finished card: "Check X first. Retry only if…" → "It may already be in X. Paste only if it’s missing" (FloatingPill ~813).
- Home: "Double-tap for hands-free" → "Double-press for hands-free" (DictationView 62–64).
- "Delete history" / "Delete all history…" → "Delete All History…" in both places (DictationView 35/380).
- Settings › Typing: "Paste fallback" → "Paste if typing fails" / "Your clipboard is put back afterwards." (SettingsView 350–356).
- TextInsertionService status lines: shorten to one sentence each (254, 269, 516–517). Standardise paths on ›.
- Over 20 words: SettingsView 261, 292, 457; StyleView 95; InsightsView 15.
