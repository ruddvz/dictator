# HushKey design system

_Fog & sage (replaced Warm editorial, which read too close to Wispr Flow). Layout measured against Wispr Flow 1.6 on 2026-11-01. Source of truth: `HushKey/Views/Theme.swift` and `HushKey/Views/Components.swift`._

The codes follow the dimensional-drawing convention (S spacing, R radius, H/I sizes, W width) so a spec sheet of any component can reference them directly. Values are points.

## Why this exists

A survey of the views before the redesign found 18 distinct padding values, 18 stack gaps, 7 corner radii, 77 caption-size labels, and three page widths. Everything new uses the tokens below; when a value isn't in a table, it doesn't belong in the UI.

## Spacing

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| S1 | `Theme.s1` | 4 | icon ↔ label in tight chips |
| S2 | `Theme.s2` | 8 | sheet inset from window, row gaps, control gaps |
| S3 | `Theme.s3` | 12 | card padding (grouped), sidebar row inset |
| S4 | `Theme.s4` | 16 | card padding (primary), column gap |
| S5 | `Theme.s5` | 24 | section gap on a page, banner padding |
| S6 | `Theme.s6` | 32 | page side and bottom margin |
| S7 | `Theme.s7` | 48 | page top margin |

## Radius

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| R1 | `Theme.r1` | 16 | page sheet, hero banner |
| R2 | `Theme.r2` | 12 | cards, lists, checklist |
| R3 | `Theme.r3` | 8 | sidebar rows, icon buttons |
| R4 | `Capsule` | h ÷ 2 | buttons, chips, search, pill |

Nested corners: a card inside the sheet sits at least S4 from the sheet edge, so `R2 ≤ R1 − S2` holds and corners never look pinched.

## Size

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| W | `Theme.pageWidth` | 800 | page column, left edge shared with home (see `pageLayout`) |
| WH | `Theme.homeWidth` | 1040 | Dictation home, Train, Meeting notes (main column + 248 side card) |

`pageLayout` centres a 1040 frame and anchors each page's column to its left edge, so a page title sits at the same x on every screen. Narrower pages end earlier on the right instead of shifting left and right.
| WS | `Theme.sidebarWidth` | 216 | fixed sidebar |
| H1 | `Theme.sidebarRow` | 36 | sidebar and settings-nav rows, 4 pt apart |
| H2 | `Theme.controlHeight` | 36 | buttons, menus, search fields |
| H3 | `Theme.listRow` | 52 | minimum list row |
| H4 | settings row | ≥ 64 | label + description + control, 18 pt vertical padding |
| WM | `Theme.menuWidth` | 196 | right-aligned menus in settings rows |
| RC | `Theme.controlRadius` | 10 | buttons, menus, fields |
| I1 | `Theme.icon` | 18 | inline icons |

## Wispr Flow measurements

Measured from Wispr Flow 1.6 (Electron) in a 1350 × 850 pt window with background accessibility frames and 1.5× zooms. Values are points. Only structure and spacing are matched; HushKey keeps its own palette, type face, icon set, MorphIcon and voice ribbon.

| Element | Wispr Flow | HushKey |
| --- | --- | --- |
| Sidebar | 216 wide; rows 192 × 36 at x 12, 40 pitch; icon 18; label ~15.5 regular | 216; rows 36, 4 gap; icon 16 regular; label 15 regular, semibold when selected |
| Content sheet | Inset 8 from window edge, radius ~16, starts below a 45 pt toolbar strip | Inset 8, `r1` 16 |
| Page column | 800 centered (Dictionary, Snippets, Transforms); home spans ~1040 with 40 margins | `pageWidth` 800; `homeWidth` 1040 |
| Page title | 28 semibold sans; ~48 below the sheet top; actions right-aligned on the same line | `hkTitle1` 28 rounded semibold; `PageHeader` takes trailing actions |
| Buttons | 36 high, radius ~10, 16 horizontal padding, 15–16 medium; primary filled dark, secondary neutral fill | 36, `controlRadius` 10, 16 padding, `hkControl` 15 medium; primary sage, secondary `hover` fill, destructive red text |
| Tabs | Text tabs 16, 2 pt underline under the selected one, hairline under the bar | `UnderlineTabs` 15, 2 pt ink underline (matched geometry) |
| Hero banner | ~895 × 208 dark card, radius 16, blurred photo, 32 serif title, white Start now button | `HeroCard`: `heroBase` panel (dark in both modes) with `AmbientField` and a `BreathRibbon` at 78 % across; 28 padding, `display(30)` title whose last words are `heroGlow`, `heroInk2` detail, `heroInk` button with `heroBase` text; min 200 high, matches the stats card |
| Lists | Outlined container, radius 12, 1 pt hairline, rows 52–53, text 16, 16 padding | `ListGroup` / `ListRow`, `r2` 12, rows ≥ 52, `hkBody` 16, 16 padding, hover fill + actions |
| History row | Time column 82 + 16 gap, time 14 gray, text 16 on 20 line | Same: time 14 `ink2`, 82 wide; text 16, 3 pt line spacing |
| Stats card | 248 wide, 24 padding, numbers 28, labels 16 | 248, 24 padding, `display(28)`, labels 15 |
| Settings | Modal: 208 nav (caps section headers 11, rows 36) + content; serif 26 title; grouped filled card radius 12, 20 side padding; rows ~88 for two lines; label 16 medium, description 15 gray; controls 164 × 36 right-aligned | In-page: 176 nav + content; `SettingsGroup` (`well`, `r2`, 20 side padding), `SettingsRow` (`hkRowTitle` 16 medium, `hkCallout` 15, control right), `MenuPicker` 196 × 36, `RowToggle` |
| Transform cards | 3-column grid, ~210 × 165, shortcut chip, 16 semibold title, 14 gray description, dashed "Create your own" | `TransformCard` 3 columns, min 132 high, badge chip, `hkHeadline`, `hkCaption`; dashed create card |
| Toolbar icons | 28 × 28 | `IconButtonStyle` 30 × 30 |
| Row hover | Fill plus trailing actions (play, copy, more) appear on hover | `ListRow`: `well` fill, actions fade and slide in 6 pt |
| Idle dictation bar | ~40 × 8 capsule centered ~20 above the screen bottom | 46 × 13 sage-on-dark capsule |

## Color

Each color has a light and dark value (`Theme.dynamic`). Light is the default; Settings → General → Appearance offers System / Light / Dark.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | #EEF0EE | #121614 | window, sidebar |
| `sheet` | #FAFBFA | #1A1F1D | raised page, outlined cards |
| `well` | #F2F4F2 | #222826 | inset cards on the sheet |
| `selection` | #E0E7E2 | #26302B | selected sidebar row |
| `hover` | #E7ECE8 | #1E2522 | hover fills |
| `hairline` | #DCE1DD | #2C3430 | borders, dividers |
| `ink` / `ink2` / `ink3` | #1E2321 / #626B66 / #5D6761 | #E9EEEB / #9BA6A0 / #8B9690 | primary / secondary / tertiary text; secondary and tertiary now meet 4.5:1 on the common window, sheet and inset surfaces |
| `signal` | #4F7F6A | #7FB39C | the one accent: primary buttons, live mic, progress |
| `signalSoft` | #E3ECE7 | #22322B | tinted fills (active capture, selected cards) |
| `heroBase` | #18201C | #0E1311 | home hero panel, dark in both modes |
| `heroInk` / `heroInk2` | #F1F4F2 / #AAB8B0 | #E9EEEB / #9BA6A0 | text and button on the hero |
| `heroGlow` | #7FB39C | #7FB39C | sage lit for the dark hero: ambient glow, voice ribbon, title accent |
| `heroMist` | #8FA7B4 | #7F97A4 | fog glow in the ambient field only; never an accent |
| `keycap` / `keycapEdge` | #DDE7E1 / #9DB5A8 | #2A3A33 / #4C6A5C | shortcut keys |
| `finishing` | #6F8796 | #9AB2C0 | slate: transcribing |
| `success` / `danger` | #3F7A5C / #B5534A | #8CC4A5 / #E0877E | done / errors and conflicts |

The pill panel is forced dark, so the pill and its card use the dark values of `paper`, `ink`, `ink2`, `hairline`, `well` and `signal`, with no colours of their own. The system accent color is not used. Sage is the only accent; red appears only for errors.

## Type

Matched to Wispr's measured sizes; SF Pro / SF Pro Rounded instead of Wispr's sans and serif.

| Token | Size / weight | Use |
| --- | --- | --- |
| `hkTitle1` | 28 rounded semibold | page titles, greeting |
| `hkTitle2` | 22 rounded semibold | note titles, large values |
| `hkTitle3` | 18 semibold | group and section titles |
| `hkHeadline` | 16 semibold | card titles |
| `hkRowTitle` | 16 medium | settings and list row labels |
| `hkBody` | 16 | reading text, list rows, editors |
| `hkCallout` | 15 | row descriptions, subtitles |
| `hkControl` | 15 medium | buttons, menus |
| `hkCaption` | 13 | status lines |
| `hkMeta` | 12 | timestamps, counts |

- **Display:** `Font.display` (SF Pro Rounded) for titles, hero copy and big numbers. The serif stays Wispr's.
- Descriptions are one line, two at most. If a control needs a paragraph, the control is wrong.

## Motion

| Token | Spring | Use |
| --- | --- | --- |
| `Theme.snappy` | response 0.32, damping 0.82 | presses, hover, page switch, button state |
| `Theme.gentle` | response 0.5, damping 0.86 | content appearing, numbers, checklist |

- **Page switch:** fade + 8 pt rise on insert, fade on removal.
- **Breath ribbon (`BreathRibbon`):** HushKey's voice form, used instead of level bars because HushKey also hears whispers and mouthed speech. One filled ribbon, tapered at both ends: at rest a thin line (half-thickness 0.14) that breathes once every 5 s (`restLoop`); with speech it swells by speech^0.45 (a whisper at energy 0.06 already doubles it), shaped by three slow travelling lobes and a faint halo, and its spine undulates a little. Rises 24/s, falls 6/s. Waiting and working send a bead of breath along the line (0.35 and 0.8 traversals a second). Reduce Motion stops travel; the voice still swells it, and waiting/working fade in place. Used in the pill (58 × 18, `ink`), the home hero (`heroGlow`; drawn by `AmbientField` at rest, 60 fps while dictating), and as `MorphIcon`'s listening state.
- **Ambient field (`AmbientField`):** the hero's backdrop, built from Core Animation layers: three radial glows (`heroGlow`, `heroMist`) on 40–70 s Lissajous loops, seven faint `heroInk` ribbons that pinch toward the voice ribbon with swells drifting along them (one 40 s loop), and the resting `BreathRibbon` (one 5 s breath). Every shape is a precomputed keyframe loop that the render server plays, so the app does no per-frame work (a per-frame SwiftUI `Canvas` re-laid out the whole window, about a fifth of a core). Paused while the window is hidden, minimised or fully covered (`onWindowVisibilityChange`); a fixed still frame with Reduce Motion. The live ribbon replaces the resting one only while a dictation runs, in its own `IsolatedHost`.
- **Morph icon (`MorphIcon`):** one 33-point stroked line that blends between hush → breath lens → spinner → check over 0.45 s (ease-out cubic). At rest it is the app icon's ribbon, traced along its top edge and back along its bottom a hair apart so the stroke tapers, and listening opens it into the ribbon's lens. Used in the Dictate button, the composer header, the empty history state, and the floating pill.
- **Speech envelope (`SpeechEnvelope`):** the ribbon and the morph icon both measure speech the same way: level above a room-noise floor that falls at once and rises 0.02 per second, gate 0.06, span 0.4. Silence stays calm; a long sentence keeps moving.
- **Pill:** see `docs/PILL_UX_ANALYSIS.md`. Idle: a 44 × 13 `paper` capsule (82 %, hairline, faint shadow so it reads on light desktops) holding a short sage line → hover: the same capsule opens to 28 pt with the hush glyph, "Dictate" and the shortcut as a `PillKey`, a hairline, then a quiet Meeting notes button (no fill until hovered). The capsule clips its contents while it grows and they fade in after it opens; the panel grows at once and shrinks only after the closing animation, so nothing clips or flickers → recording: a 28 pt capsule with × · `BreathRibbon` · ✓ (filled `signal`). While the shortcut is held, it is the meter only. The timer appears after 30 s. Preparing and transcribing keep the same capsule: the meter sweeps while it waits (a hint names the wait) and runs a brisker highlight while it works. Done shows only the check for 0.8 s; the success cue says it landed (start, success and error cues: `DictationCue`). Idle shrinks to a dot after 5 s. Right-click opens a mic / sounds / hide menu, and drag slides the pill along the bottom edge (remembered). Cancel shows a neutral "Cancelled · Undo" for 5 s. A silent mic shows "We couldn't hear you" with Mic and Sound settings. Hovering × or ✓ (or Meeting notes) shows "Cancel · esc", "Finish · fn" or "Meeting notes" in a 24 pt `PillHint` above, straight away. Errors use the `Theme.danger` icon, a short message and dismiss ×, plus Retry and/or Paste again as titled `PillIconButton` capsules, and stay until handled. **Transcript card:** only when there is no text box to type into, or typing failed. Before any words, a one-line strip (glyph, hint, ×). With text, a 320 pt `paper` card (radius `r2`) with the last three lines at 16 pt. The finished no-target card adds a sage Copy (⌘C) and, when typing into apps is off, "Type for me next time". **Meter:** the `BreathRibbon` (see above), 58 × 18 in `ink`.
- **App icon and menu bar:** the breath ribbon in sage on a fog squircle; the menu bar and the centred sidebar brand row use the same ribbon (template glyph, a fuller lens while dictating). Drawn by `Scripts/generate-app-icon.swift`.
- **Sidebar:** icon bounces on selection; rows fade their fill on hover.
- **History:** rows slide in from the top, delete animates out, hover actions slide in 6 pt.

## Components

- **Surfaces:** `card(style: .well | .outlined)`, `SettingsGroup`, `GroupRow`, `ListGroup`, `RowDivider`.
- **Rows:** `SettingsRow` (label, one-line detail, right-aligned control), `ListRow` (hover fill and actions).
- **Controls:** `PrimaryButtonStyle(tint:foreground:)`, `SecondaryButtonStyle(minWidth:)`, `DestructiveButtonStyle`, `IconButtonStyle`, `MenuPicker`, `RowToggle`, `UnderlineTabs`, `Keycap` / `KeycapShortcut`.
- **Style page:** `StyleView`: `UnderlineTabs` for the four contexts, plain app chips, and three `ToneCard`s (`well`, or `signalSoft` with a 1.5 pt `signal` border when selected) whose previews run through `DictationTone.apply`.
- **Insights page:** `InsightsView`: `InsightCard`s on `well` with a hairline border, display-font metrics with uppercase `ink2` labels, a `PaceArc` gauge (hairline track, `signal` progress), category bars in `signal` at falling opacity with `inverseInk` percentages, and the shared `ActivityHeatmap`.
- **Languages sheet:** `LanguagePickerSheet` on `sheet`: a `well` search field, a `signalSoft` "Selected" chip, and a 3-column grid of `LanguageTile`s (language on top, native name and region in `ink2` below; selected tiles match `ToneCard`).
- **Sheets:** `EditorSheet` (display title, subtitle, close, footer note, Cancel + primary), `SheetField` (`well`, hairline, `signal` focus ring), `SheetNotice` (`danger`); inline `TextEditor`s use `.editorField()`.
- **Live level:** `LiveLevel` reads the mic level in its own body; never read `audio.level` in a page body.
- **Page:** `PageHeader` (title, optional subtitle, trailing actions), `pageLayout(maxWidth:)`, `EmptyState`.
- **Silent Lab:** `LabProgress` (Connect → Train → Evaluate → Silent Use strip on every lab page), `LabHero`, `HeroMetric`.
- **Motion:** `MorphIcon`, `BreathRibbon`, `AmbientField` (`Ambient.swift`), `StatusChip`, `SectionLabel`, `ActivityHeatmap`.
- **Home:** greeting "Hey Name, hold [fn] and just talk" (`hkTitle1`, keycap 17) with one `ink2` line under it; `HeroCard` + stats card; history whose first day label ("TODAY") carries search and the options menu.

## Open items

- Pill hover hints, Esc, hold-to-talk (meter only) and the meter moving with real speech still need checking live, with a person speaking.
