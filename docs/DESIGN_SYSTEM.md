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
| W | `Theme.pageWidth` | 800 | page column, centered |
| WH | `Theme.homeWidth` | 1040 | Dictation home, Train, Meeting notes (main column + 248 side card) |
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
| Hero banner | Full-width, ~180 high, radius 16, 32 padding, 32 serif title, chips 36 high | `signalSoft` hero, 28 padding, 26–28 rounded title, example chips 36 high |
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
| `ink` / `ink2` / `ink3` | #1E2321 / #66706B / #949D98 | #E9EEEB / #9BA6A0 / #6C7671 | primary / secondary / tertiary text |
| `signal` | #4F7F6A | #7FB39C | the one accent: primary buttons, live mic, progress |
| `signalSoft` | #E3ECE7 | #22322B | tinted fills (next-step banner, active capture) |
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
- **Morph icon (`MorphIcon`):** one 25-point stroked line that blends between hush → waveform → spinner → check over 0.45 s (ease-out cubic). Used in the brand mark, the Dictate button, the composer header, the empty history state, and the floating pill.
- **Speech envelope (`SpeechEnvelope`):** the ribbon, the bars and the morph icon all measure speech the same way: level above a room-noise floor that falls at once and rises 0.02 per second, gate 0.06, span 0.4. Silence stays calm; a long sentence keeps moving.
- **Pill:** see `docs/PILL_UX_ANALYSIS.md`. Idle sage bar → hover: a small mic capsule and a `PillHint` tooltip ("Dictate" + shortcut) → recording: a 28 pt capsule with × · `PillMeter` · ✓ (filled `signal`). While the shortcut is held, it is the meter only. The timer appears after 30 s. Preparing and transcribing keep the same capsule: the meter sweeps while it waits (a hint names the wait) and runs a brisker highlight while it works. Done shows a check with "Typed" (or "Ready in HushKey") for 1.4 s. Idle shrinks to a dot after 5 s. The hover capsule adds a Meeting notes button. Right-click opens a mic / sounds / hide menu, and drag slides the pill along the bottom edge (remembered). Cancel shows a neutral "Cancelled · Undo" for 5 s. A silent mic shows "We couldn't hear you" with Mic and Sound settings. Hovering × or ✓ shows "Cancel · esc" or "Finish · fn" straight away. Errors use the `Theme.danger` icon, a short message and dismiss ×, plus Retry and/or Paste again as titled `PillIconButton` capsules, and stay until handled. **Transcript card:** before any words, a one-line strip (glyph, hint, ×). With text, a 320 pt `paper` card (radius `r2`) with the last three lines at 16 pt. The finished no-target card adds a sage Copy (⌘C) and, when typing into apps is off, "Type for me next time". **`PillMeter`:** 13 bars, 2.5 wide and 2 apart, centre-weighted. Each bar wobbles on its own, scaled by √(speech) from `SpeechEnvelope`. They rise fast (28/s), fall slower (7/s), and rest as breathing dots.
- **Sidebar:** icon bounces on selection; rows fade their fill on hover.
- **History:** rows slide in from the top, delete animates out, hover actions slide in 6 pt.

## Components

- **Surfaces:** `card(style: .well | .outlined)`, `SettingsGroup`, `GroupRow`, `ListGroup`, `RowDivider`.
- **Rows:** `SettingsRow` (label, one-line detail, right-aligned control), `ListRow` (hover fill and actions).
- **Controls:** `PrimaryButtonStyle(tint:foreground:)`, `SecondaryButtonStyle(minWidth:)`, `DestructiveButtonStyle`, `IconButtonStyle`, `MenuPicker`, `RowToggle`, `UnderlineTabs`, `Keycap` / `KeycapShortcut`.
- **Page:** `PageHeader` (title, optional subtitle, trailing actions), `pageLayout(maxWidth:)`, `EmptyState`.
- **Silent Lab:** `LabProgress` (Connect → Train → Evaluate → Silent Use strip on every lab page), `LabHero`, `HeroMetric`.
- **Motion:** `MorphIcon`, `PillMeter`, `VoiceRibbon`, `LiveWaveform`, `StatusChip`, `SectionLabel`, `ActivityHeatmap`.

## Open items

- Sheets (writing-style editor, vocabulary entry editor) still use stock form layout.
- Pill hover hints, Esc, hold-to-talk (meter only) and the meter moving with real speech still need checking live, with a person speaking.
- Check `signalSoft` hero contrast in dark mode by eye.
