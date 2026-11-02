# HushKey design system

_Warm editorial. Written 2026-11-01. Source of truth: `HushKey/Views/Theme.swift`._

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
| `paper` | #F4F2EE | #191816 | window, sidebar |
| `sheet` | #FDFCFA | #21201E | raised page, outlined cards |
| `well` | #F6F4EF | #2A2825 | inset cards on the sheet |
| `selection` | #EAE6DF | #2F2D2A | selected sidebar row |
| `hover` | #F0EDE7 | #292724 | hover fills |
| `hairline` | #E6E1D8 | #35322E | borders, dividers |
| `ink` / `ink2` / `ink3` | #1A1918 / #6B665E / #9C968C | #F3F1EC / #A8A298 / #77726A | primary / secondary / tertiary text |
| `keycap` | #F7D58E | #5A4520 | shortcut keys |
| `listening` | red | red | live microphone only |

The system accent color is not used. Red means "the microphone is live" and nothing else.

## Type

- **Display:** New York (`Font.display`) for page titles (30), the greeting (32), banner titles (24), and stat numbers (28).
- **Text:** SF Pro, 13.5 body, 13 controls, 12 metadata, 11 semibold tracked caps for section labels (`SectionLabel`).
- Captions are for metadata, not instructions. If a control needs a paragraph to explain it, the control is wrong.

## Motion

| Token | Spring | Use |
| --- | --- | --- |
| `Theme.snappy` | response 0.32, damping 0.82 | presses, hover, page switch, button state |
| `Theme.gentle` | response 0.5, damping 0.86 | content appearing, numbers, checklist |

- **Page switch:** fade + 8 pt rise on insert, fade on removal.
- **Morph icon (`MorphIcon`):** one 25-point stroked line that blends between hush → waveform → spinner → check over 0.45 s (ease-out cubic). Used in the brand mark, the Dictate button, the composer header, the empty history state, and the floating pill.
- **Pill:** idle bar → hover hint → live waveform → "Transcribing" → check with "Ready to insert" for 1.4 s → idle.
- **Sidebar:** icon bounces on selection; rows fade their fill on hover.
- **History:** rows slide in from the top, delete animates out, hover actions slide in 6 pt.

## Components

`card(style: .well | .outlined)`, `PrimaryButtonStyle`, `SecondaryButtonStyle`, `IconButtonStyle`, `Keycap` / `KeycapShortcut`, `MorphIcon`, `LiveWaveform`, `StatusChip`, `SectionLabel`, `ActivityHeatmap`, `PageHeader`, `pageLayout()`, `CardGroupBoxStyle` (applied to every `GroupBox`).

## Open items

- Settings rows still carry long explanatory captions from the old layout; convert them to label + one-line description + right-aligned control.
- Transforms, Files, and the Silent Lab pages use the shared tokens through `GroupBox` and `pageLayout()`, but their inner controls haven't been individually redesigned.
- `[TBD]` dark-mode banner treatment: the gradient reads well in light mode; in dark mode it sits close to the sheet color.
