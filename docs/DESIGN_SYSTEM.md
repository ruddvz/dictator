# HushKey design system

_Fog & sage (replaced Warm editorial, which read too close to Wispr Flow). Updated 2026-11-01. Source of truth: `HushKey/Views/Theme.swift`._

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
| WS | sidebar | 216 | fixed sidebar |
| H1 | `Theme.sidebarRow` | 34 | sidebar row |
| H2 | `Theme.controlHeight` | 32 | primary/secondary buttons |
| H3 | chip | 24 | status chips, mode menu |
| I1 | `Theme.icon` | 16 | inline icons, morph icon in buttons |

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

Pill surface is always dark: #141B17 with sage #9CCBB4 strokes. The system accent color is not used. Sage is the only accent; red appears only for errors.

## Type

- **Display:** SF Pro Rounded semibold (`Font.display`) for page titles (30), the greeting (32), banner titles (24), and stat numbers (28). The serif was dropped: it was Wispr's signature.
- **Text:** SF Pro, 13.5 body, 13 controls, 12 metadata, 11 semibold tracked caps for section labels (`SectionLabel`).
- Captions are for metadata, not instructions. If a control needs a paragraph to explain it, the control is wrong.

## Motion

| Token | Spring | Use |
| --- | --- | --- |
| `Theme.snappy` | response 0.32, damping 0.82 | presses, hover, page switch, button state |
| `Theme.gentle` | response 0.5, damping 0.86 | content appearing, numbers, checklist |

- **Page switch:** fade + 8 pt rise on insert, fade on removal.
- **Morph icon (`MorphIcon`):** one 25-point stroked line that blends between hush → waveform → spinner → check over 0.45 s (ease-out cubic). Used in the brand mark, the Dictate button, the composer header, the empty history state, and the floating pill.
- **Pill:** idle sage bar → hover hint → listening (cancel ×, `VoiceRibbon`, elapsed time, stop) → "Writing it up" → check with "Typed" (or "Ready in HushKey") for 1.4 s → idle. Errors replace the done state: `Theme.danger` icon, short message and dismiss ×, plus Retry and/or Paste again as titled `PillIconButton` capsules. The error stays until it is dismissed or acted on. **Transcript card:** a 340 pt dark card (#141B17, radius `r1`) sits 8 pt above the pill with a sage glyph, an optional grey hint, ×, and the last three lines of text at 17 pt white; the finished no-target card adds a sage `PrimaryButtonStyle` Copy. `VoiceRibbon` is three flowing lines that swell with speech above an adaptive noise floor (fast rise, slow fall), so silence stays calm instead of looking like a broken meter.
- **Sidebar:** icon bounces on selection; rows fade their fill on hover.
- **History:** rows slide in from the top, delete animates out, hover actions slide in 6 pt.

## Components

`card(style: .well | .outlined)`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `IconButtonStyle`, `Keycap` / `KeycapShortcut`, `MorphIcon`, `VoiceRibbon`, `LiveWaveform`, `StatusChip`, `SectionLabel`, `ActivityHeatmap`, `PageHeader`, `pageLayout()`, `CardGroupBoxStyle` (applied to every `GroupBox`).

## Open items

- Settings rows still carry long explanatory captions from the old layout; convert them to label + one-line description + right-aligned control.
- Transforms, Files, and the Silent Lab pages use the shared tokens through `GroupBox` and `pageLayout()`, but their inner controls haven't been individually redesigned.
- Banner is now `signalSoft`; check its contrast in dark mode by eye.
