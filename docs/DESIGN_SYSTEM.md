# Dictator design system

_Fog & sage (replaced Warm editorial, which read too close to Wispr Flow). Layout measured against Wispr Flow 1.6 on 2026-11-01; tokens completed 2026-11-08. Source of truth: `Dictator/Views/Theme/Theme.swift` and `Dictator/Views/Components/Components.swift`._

The codes follow the dimensional-drawing convention (S spacing, R radius, H/I sizes, W width) so a spec sheet of any component can reference them directly. Values are points.

## Why this exists

A survey of the views before the redesign found 18 distinct padding values, 18 stack gaps, 7 corner radii, 77 caption-size labels, and three page widths. Everything new uses the tokens below; when a value isn't in a table, it doesn't belong in the UI.

## Spacing

A 4-pt grid. Views use the role tokens below the steps, so a page can't pick its own gap.

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| S0 | `Theme.s0` | 2 | hairline-thin nudges: row label ↔ detail, icon-button clusters |
| S1 | `Theme.s1` | 4 | icon ↔ label in tight chips, small offsets |
| S2 | `Theme.s2` | 8 | sheet inset from window, control gaps |
| S3 | `Theme.s3` | 12 | section title → content, items in a stack, chip padding |
| S4 | `Theme.s4` | 16 | card padding, row padding, grid gutter |
| S5 | `Theme.s5` | 24 | between sections on a page, roomy card padding |
| S6 | `Theme.s6` | 32 | page header → first section, page bottom margin |
| S7 | `Theme.s7` | 48 | page top margin |
| S8 | `Theme.s8` | 64 | large plots and label columns |

| Role token | Value | Use |
| --- | --- | --- |
| `pageGutter` | 40 | page column inset from the sheet's sides (`pageLayout`) |
| `pageTop` / `pageBottom` | S7 / S6 | sheet top → page title; below the last section |
| `headerGap` | S6 | page header → first section (owned by `PageHeader`) |
| `sectionGap` | S5 | between sections (owned by `PageColumn`) |
| `sectionTitleGap` | S3 | section title → its content (`PageSection`, `SettingsGroup`) |
| `titleGap` | S2 | title → subtitle in `PageHeader` and `LabHero` |
| `stackGap` | S3 | items inside a card or section |
| `gridGap` | S4 | gutter between cards in a `CardGrid`, both ways |
| `cardPadding` / `cardPaddingL` | S4 / S5 | inside a card / roomy cards (insights, banners, sheets) |
| `rowPaddingV` / `rowPaddingH` | S4 / S4 | settings, group and list rows |
| `controlGap` / `iconGap` | S2 / S2 | buttons in a row / glyph ↔ label |
| `figureGap` | 6 | figure ↔ its unit label |
| `leading` | 3 | extra line spacing for reading text and transcripts |

## Radius

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| R1 | `Theme.r1` | 16 | page sheet only |
| R2 | `Theme.r2` | 12 | cards, lists, option cards, drop zone |
| R3 | `Theme.r3` | 8 | rows inside cards, sidebar rows, icon buttons, bars |
| R4 | `Theme.r4` | 4 | small marks and pill key caps |
| RC | `Theme.controlRadius` | 10 | buttons, menus, fields |
| — | `Capsule` | h ÷ 2 | chips, pill, step strip |

Nested corners are concentric: `Theme.inner(outer, padding:)` gives `outer − padding`, never under R4. Cards (R2) sit at least S4 inside the sheet (R1), so their corners never pinch.

## Strokes

| Token | Value | Use |
| --- | --- | --- |
| `hairlineWidth` | 1 | borders, dividers (`RowDivider`, `SectionRule`) |
| `selectedStroke` | 1.5 | selected cards, focused fields, drop zone |
| `ruleWidth` | 2 | tab underline, quote rule, accent bars |
| `dash` | [6, 4] | dashed drop zone and suggestion chips |

## Size

| Code | Token | Value | Use |
| --- | --- | --- | --- |
| H1 | `Theme.controlHeight` | 36 | buttons, menus, form fields (macOS large) |
| H2 | `Theme.fieldHeight` | 32 | inline search fields, `IconButtonStyle`, step strip |
| H3 | `Theme.toolbarButton` | 28 | toolbar icon controls |
| H4 | `Theme.chipHeight` | 24 | chips, compact menus, category bars |
| H5 | `Theme.sidebarRow` | 36 | sidebar and settings-nav rows, 4 pt apart |
| H6 | `Theme.listRow` | 52 | minimum list row |
| H7 | `Theme.rowMinHeight` | 64 | settings row: label + description + control |
| H8 | `Theme.optionCardHeight` | 136 | `SelectableCard` minimum |
| — | `editorShort` / `editorMedium` / `editorTall` | 72 / 140 / 220 | inline editors' minimum heights |
| — | `editorShortMax` / `editorTallMax` | 120 / 260 | where editors stop growing |
| — | `progressHeight` / `dot` | 4 / 8 | thin progress tracks / status dots |
| I1 | `Theme.iconXS` | 12 | chevrons, tiny checks |
| I2 | `Theme.iconS` | 14 | chips, meta lines, arrows |
| I3 | `Theme.iconM` | 16 | buttons, inline glyphs, the selected check |
| I4 | `Theme.iconL` | 18 | sidebar, nav, option cards, notices |
| I5 | `Theme.iconXL` | 28 | empty states, feature glyphs, brand mark |
| — | `iconColumn` / `iconTile` / `tileL` | 20 / 32 / 44 | fixed glyph slot so labels line up / tinted notice tile / Files drop-zone tile |
| W | `Theme.pageWidth` | 1040 | shared page column maximum, with 40 pt gutters (see `pageLayout`) |
| WH | `Theme.homeWidth` | 1040 | Home, Insights, Train, Meeting notes |
| WC | `Theme.sideColumn` | 280 | side list beside a home-width column (notes, Train words) |
| WS | `Theme.sidebarWidth` | 216 | fixed sidebar (68 collapsed) |
| WN | `Theme.settingsNavWidth` | 176 | settings section nav |
| WM | `Theme.menuWidth` / `menuWidthCompact` | 196 / 160 | menus in settings rows / menus sharing a line |
| WB | `Theme.buttonMinWidth` | 96 | trailing buttons in a settings column |
| WD | `Theme.detailWidth` | 440 | settings-row label + detail column |
| WR | `Theme.readingWidth` | 560 | subtitles and paragraphs |
| WE | `Theme.noteWidth` | 384 | centred empty-state messages |
| WT | `Theme.sheetWidth` / `sheetWidthWide` | 520 / 620 | editor sheets / grid sheets (languages) |
| WP | `Theme.popoverWidth` | 320 | toolbar popovers |
| — | `searchWidth` / `timeColumn` / `valueWidth` / `meterWidth` | 180 / 80 / 48 / 120 | search text, history time column, numeric readouts, level meters |

`pageLayout` centres a 1040 frame and anchors each page's column to its left edge, so a page title sits at the same x on every screen. Narrower pages end earlier on the right instead of shifting left and right.

## Wispr Flow measurements

Measured from Wispr Flow 1.6 (Electron) in a 1350 × 850 pt window with background accessibility frames and 1.5× zooms. Values are points. Only structure and spacing are matched; Dictator keeps its own palette, type face, native SF Symbols and voice ribbon.

| Element | Wispr Flow | Dictator |
| --- | --- | --- |
| Sidebar | 216 wide; rows 192 × 36 at x 12, 40 pitch; icon 18; label ~15.5 regular | 216; rows 36, 4 gap; icon 16 regular; label 15 regular, semibold when selected |
| Content sheet | Inset 8 from window edge, radius ~16, starts below a 45 pt toolbar strip | Inset 8, `r1` 16 |
| Page column | Shared 1040 maximum across every page, with narrower reading measures inside prose | `pageWidth` and `homeWidth` 1040 |
| Page title | 28 semibold sans; ~48 below the sheet top; actions right-aligned on the same line | `hkTitle1` 28 serif, `pageTop` 48 below the sheet top; `PageHeader` centres trailing actions on the title line; first section `headerGap` 32 below |
| Buttons | 36 high, radius ~10, 16 horizontal padding, 15–16 medium; primary filled dark, secondary neutral fill | 36, `controlRadius` 10, 16 padding, `hkControl` 15 medium; primary sage, secondary `hover` fill, destructive red text |
| Tabs | Text tabs 16, 2 pt underline under the selected one, hairline under the bar | `UnderlineTabs` 15, 2 pt ink underline (matched geometry) |
| Hero banner | ~895 × 208 dark card, radius 16, blurred photo, 32 serif title, white Start now button | `HeroCard`: `heroBase` panel (dark in both modes) with `AmbientField` and a `BreathRibbon` at 78 % across; radius `r2`, `s5` padding, `hkTitle1` title whose last words are `heroGlow`, `heroInk2` detail, `heroInk` button with `heroBase` text; min 200 high, matches the stats card |
| Lists | Outlined container, radius 12, 1 pt hairline, rows 52–53, text 16, 16 padding | `ListGroup` / `ListRow`, `r2` 12, rows ≥ 52, `hkBody` 16, 16 padding, hover fill + actions |
| History row | Time column 82 + 16 gap, time 14 gray, text 16 on 20 line | `timeColumn` 80 + 16 gap, time `hkSubhead` 14 `ink2`; text 16, `leading` 3; `rowPaddingV` 16 |
| Stats card | 248 wide, 24 padding, numbers 28, labels 16 | Home: one figures line, `hkDisplayBand` 24 figures; Insights: `InsightCard` `cardPaddingL` 24, `hkFigureXL` 36 |
| Settings | Modal: 208 nav (caps section headers 11, rows 36) + content; serif 26 title; grouped filled card radius 12, 20 side padding; rows ~88 for two lines; label 16 medium, description 15 gray; controls 164 × 36 right-aligned | In-page: 176 nav + content; `SettingsGroup` (`well`, `r2`, `s4` 16 side padding; detail column capped at `Theme.detailWidth` 440), `SettingsRow` (`hkRowTitle` 16 medium, `hkCallout` 15, control right), `MenuPicker` 196 × 36, `RowToggle` |
| Transform cards | 3-column grid, ~210 × 165, shortcut chip, 16 semibold title, 14 gray description, dashed "Create your own" | `SelectableCard` in a 3-column `CardGrid` (equal row heights, `gridGap` 16), min `optionCardHeight` 136, glyph + `hkCardTitle`, `hkCaption`; "New transform" lives in the header |
| Toolbar icons | 28 × 28 | `ToolbarButtonStyle` 28 × 28; in-page `IconButtonStyle` 32 × 32 (= `fieldHeight`, level with search fields) |
| Row hover | Fill plus trailing actions (play, copy, more) appear on hover | `ListRow`: `well` fill, actions fade and slide in 6 pt |
| Idle dictation bar | ~40 × 8 capsule centered ~20 above the screen bottom | 46 × 13 sage-on-dark capsule |

## Color

Each color has a light and dark value (`Theme.dynamic`). Light is the default; Settings › Appearance offers System / Light / Dark.

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

New York (`Font.display`, the system serif) at a regular weight for titles and figures; SF Pro for everything else. Views never call `.system(size:)` or `.display(_:)` directly.

| Token | Face / size / weight | Use |
| --- | --- | --- |
| `hkFigureXL` | serif 36 | the lead figure on a card (Insights) |
| `hkFigureL` | serif 34 | home band headline |
| `hkTitle1` | serif 28 | page titles, the word being trained |
| `hkFigureM` | serif 28 | stat figures beside a label |
| `hkSheetTitle` | serif 26 | sheet titles, hero metrics |
| `hkDisplayBand` | serif 24 | banner titles, inline figures |
| `hkTitle2` | serif 22 | card titles, large values |
| `hkCardTitle` | serif 20 | option cards, empty states, the wordmark (medium) |
| `hkDisplayS` | serif 18 | small serif values |
| `hkQuote` | serif 16 | quoted samples |
| `hkTitle3` | 18 semibold | section titles (`SectionTitle`) |
| `hkHeadline` | 16 semibold | emphasised row titles |
| `hkRowTitle` | 16 medium | settings and list row labels |
| `hkBody` | 16 | reading text, list rows, editors |
| `hkTranscript` | 17 | the live transcript |
| `hkCallout` | 15 | row descriptions, subtitles |
| `hkControl` | 15 medium | buttons, menus |
| `hkNav` | 15 | sidebar and settings nav (medium when selected) |
| `hkSubhead` | 14 | time column, notice titles, step strip |
| `hkCaption` | 13 | status lines, card descriptions |
| `hkMeta` | 12 | timestamps, counts |
| `hkBadge` | 11 semibold | step numbers |

- Descriptions are one line, two at most. If a control needs a paragraph, the control is wrong.

## Motion

| Token | Spring | Use |
| --- | --- | --- |
| `Theme.snappy` | response 0.32, damping 0.82 | presses, hover, page switch, button state |
| `Theme.gentle` | response 0.5, damping 0.86 | content appearing, numbers, checklist |
| `Theme.glide` | timing curve (0.05, 0.6, 0.4, 0.95), 0.28 s | panels, sidebar width |
| `Theme.fade` | ease-out 0.12 s | colour and opacity only: hover fills, focus rings, drop targets |
| `Theme.calm` | ease-in-out 0.15 s | what `snappy`, `gentle` and `glide` become with Reduce Motion |
| `Motion.exit` | ease-out 0.1 s | outgoing page or settings section, so old and new never overlap |
| `Motion.confirmHold` | 1.4 s | how long "Copied" or a check stays before it settles back |
| `Theme.pressScale` | 0.97 | pressed buttons (icon buttons 0.9, rows and cards 0.98); 1 with Reduce Motion via `Theme.pressed` |

**Rules.** Most motion takes 150–350 ms; springs for things that move, `fade` for things that only change colour. Never put a per-frame clock (`TimelineView(.animation)`, a `Canvas` redrawn every frame) in a page at rest. Use Core Animation (`AmbientField`), an animatable `Shape` driven once (`RibbonMark`), or nothing. A clock may run only while something is live (dictating, a meeting, a download), and must pause when the window is hidden. Motion never waits on or delays dictation or insertion. **Reduce Motion:** the three springs check the system setting themselves, so `withAnimation(Theme.snappy)` is already safe; anything with its own `.spring(...)`, offset, scale or keyframes must check `accessibilityReduceMotion` and fall back to opacity or nothing.

- **Page switch:** fade + 8 pt rise on insert, fade on removal.
- **Breath ribbon (`BreathRibbon`):** Dictator's voice form, used instead of level bars because Dictator also hears whispers and mouthed speech. One filled ribbon, tapered at both ends: at rest a thin line (half-thickness 0.14) that breathes once every 5 s (`restLoop`); with speech it swells by speech^0.45 (a whisper at energy 0.06 already doubles it), shaped by three slow travelling lobes and a faint halo, and its spine undulates a little. Rises 24/s, falls 6/s. Waiting and working send a bead of breath along the line (0.35 and 0.8 traversals a second). Reduce Motion stops travel; the voice still swells it, and waiting/working fade in place. Used in the pill (58 × 18, `ink`) and the home hero (`heroGlow`; drawn by `AmbientField` at rest, 60 fps while dictating).
- **Ambient field (`AmbientField`):** the hero's backdrop, built from Core Animation layers: three radial glows (`heroGlow`, `heroMist`) on 40–70 s Lissajous loops, seven faint `heroInk` ribbons that pinch toward the voice ribbon with swells drifting along them (one 40 s loop), and the resting `BreathRibbon` (one 5 s breath). Every shape is a precomputed keyframe loop that the render server plays, so the app does no per-frame work (a per-frame SwiftUI `Canvas` re-laid out the whole window, about a fifth of a core). Paused while the window is hidden, minimised or fully covered (`onWindowVisibilityChange`); a fixed still frame with Reduce Motion. The live ribbon replaces the resting one only while a dictation runs, in its own `IsolatedHost`.
- **Home voice band (`VoiceBandBackdrop`, `Motion.swift`):** the one Home band (Field). Over the ambient field: a soft `heroGlow` bloom ellipse (2.2 × 3.4 ribbon sizes) that breathes with the resting ribbon (opacity 0.24) and rises with the voice (+0.6 at full level, eased 0.18 s); hovering the band lifts it a little (`bandBloomInvite`), waiting and working hold it at 0.25 and 0.4. The faint lines fade to 30 % behind the words on the left; a 6 % `heroInk` sheen lights the top edge. The resting ribbon crossfades to the live one in 0.3 s (`Motion.handover`), and the live ribbon's halo is five shape-following veils (`softHalo`) instead of one flat band. Tokens live in `Motion` and `AmbientField`.
- **Other motion pieces (`Motion.swift`):** `RibbonMark` (the page-title mark: one breath when a page opens, 0.38 s in and 0.7 s out to a swell of 0.5, through an animatable `RibbonMarkShape`, then still, with no clock; still with Reduce Motion), `ChorusRibbons` (several out-of-step ribbons, for several voices), `Nudge` / `.nudge(on:)` (one ±5 pt sideways shake of about 0.37 s, for the pill's error card; none with Reduce Motion), `waveIn` (staggered entrances).
- **Confirmations:** `CopyButton` swaps its glyph and title to a check and "Copied" for `confirmHold`, keeps the wider width, and announces "Copied" to VoiceOver.
- **Files drop zone:** a `tileL` 44 pt sage tile (tray, or waveform once a file is chosen) fills with `signal` and lifts 2 pt with a 1.08 scale while a file is held over it.
- **Settings sections:** the new section fades in from 6 pt below, and the old one leaves in `Motion.exit`.
- **State icon (`StateIcon`):** the idle Dictator ribbon mark and native waveform, hourglass and check symbols for listening, working and completion. The compact listening waveform responds to mic level; it does not animate the surrounding page or rebuild a custom path.
- **Speech envelope (`SpeechEnvelope`):** the ribbon and the morph icon both measure speech the same way: level above a room-noise floor that falls at once and rises 0.02 per second, gate 0.06, span 0.4. Silence stays calm; a long sentence keeps moving.
- **Pill:** see `docs/PILL_UX_ANALYSIS.md`. Idle: a 44 × 13 `paper` capsule (82 %, hairline, faint shadow so it reads on light desktops) holding a short sage line → hover: the same capsule opens to 28 pt with the hush glyph, "Dictate" and the shortcut as a `PillKey`, a hairline, then a quiet Meeting notes button (no fill until hovered). The capsule clips its contents while it grows and they fade in after it opens; the panel grows at once and shrinks only after the closing animation, so nothing clips or flickers → recording: a 28 pt capsule with × · `BreathRibbon` · ✓ (filled `signal`). While the shortcut is held, it is the meter only. The timer appears after 30 s. Preparing and transcribing keep the same capsule: the meter sweeps while it waits (a hint names the wait) and runs a brisker highlight while it works. Done shows only the check for 0.8 s; the success cue says it landed (start, success and error cues: `DictationCue`). Idle shrinks to a dot after 5 s. Right-click opens a mic / sounds / hide menu, and drag slides the pill along the bottom edge (remembered). Cancel shows a neutral "Cancelled · Undo" for 5 s. A silent mic shows "We couldn't hear you" with Mic and Sound settings. Hovering × or ✓ (or Meeting notes) shows "Cancel · esc", "Finish · fn" or "Meeting notes" in a 24 pt `PillHint` above, straight away. Errors use the `Theme.danger` icon, a short message and dismiss ×, plus Retry and/or Paste again as titled `PillIconButton` capsules, and stay until handled. **Transcript card:** only when there is no text box to type into, or typing failed. Before any words, a one-line strip (glyph, hint, ×). With text, a 320 pt `paper` card (radius `r2`) with the last three lines at 16 pt. The finished no-target card adds a sage Copy (⌘C) and, when typing into apps is off, "Type for me next time". **Meter:** the `BreathRibbon` (see above), 58 × 18 in `ink`.
- **App icon and menu bar:** the breath ribbon in sage on a fog squircle; the menu bar and the centred sidebar brand row use the same ribbon (template glyph, a fuller lens while dictating). Drawn by `Scripts/generate-app-icon.swift`.
- **Sidebar:** icon bounces on selection; rows fade their fill on hover.
- **History:** rows slide in from the top, delete animates out, hover actions slide in 6 pt.

## Components

- **Page:** every hub and lab page is `PageColumn(maxWidth:) { PageHeader(…); sections }`. `PageColumn` spaces sections by `sectionGap` and applies `pageLayout`; `PageHeader` (title, optional subtitle or custom `detail` line, trailing actions centred on the title line) adds the rest of `headerGap`, so content starts the same distance below every title. Home uses `PageHeader`'s `detail` slot for its warning line.
- **Sections:** `SectionTitle(_:subtitle:trailing:)` is the one in-page heading (`hkTitle3`, at least `fieldHeight` tall so a search field or icon button beside it never changes the row). `PageSection` adds its content `sectionTitleGap` below; `SettingsGroup` titles use `SectionTitle` too. `SectionRule` is the hairline between sections.
- **Surfaces:** `surface(_ style:radius:)` draws fill + edge; `card(padding:style:)` adds `cardPadding` and full width. Styles: `.well`, `.outlined`, `.wellOutlined`, `.selected`, `.tinted`, `.soft`. Also `SettingsGroup`, `GroupRow`, `ListGroup`, `RowDivider`.
- **Selectable cards:** `SelectableCard` (optional glyph, `hkCardTitle`, sage check when chosen, `hkCaption` description, optional footer pinned to the bottom; `well` → `hover` → `signalSoft` with a `selectedStroke` `signal` edge) inside `CardGrid`, a `Grid` whose rows take their tallest card's height with `gridGap` gutters. Used by Style's cleanup and tone cards and the Transforms tiles; Insights' voice tiles use `CardGrid` with `InsightCard`.
- **Rows:** `SettingsRow` (label, one-line detail capped at `detailWidth`, right-aligned control, ≥ `rowMinHeight`), `GroupRow`, `ListRow` (hover fill and actions, ≥ `listRow`).
- **Controls:** `PrimaryButtonStyle(tint:foreground:)`, `SecondaryButtonStyle(minWidth:)`, `DestructiveButtonStyle`, `IconButtonStyle` (`fieldHeight` square), `ToolbarButtonStyle`, `MenuPicker`, `RowToggle`, `UnderlineTabs`, `SearchField` (Home history, Files, Meeting notes), `Keycap` / `KeycapShortcut`.
- **Insights page:** `InsightCard`s (`.wellOutlined`, `cardPaddingL`), `hkFigureXL` metrics, `CategoryBar`s in `signal` at falling opacity over a `track`, and `InsightsHeatmap` (its cell geometry is chart-local).
- **Languages sheet:** `LanguagePickerSheet` on `sheet`: a `well` search field, a `signalSoft` "Selected" chip, and a 3-column grid of `LanguageTile`s.
- **Sheets:** `EditorSheet` (`hkSheetTitle`, subtitle, close, footer note, Cancel + primary; `sheetWidth`), `SheetField` (`well`, hairline, `signal` focus ring), `SheetNotice` (`danger`); inline `TextEditor`s use `.editorField()`.
- **Live level:** `LiveLevel` reads the mic level in its own body; never read `audio.level` in a page body.
- **Silent Lab:** `LabProgress`, `LabHero`, `HeroMetric`.
- **Motion:** `BreathRibbon`, `AmbientField` (`Ambient.swift`), `StateIcon`, `StatusChip`, `SectionLabel`, `ActivityHeatmap`.

### Literals that stay

Only these keep numbers of their own: motion maths (`Ambient.swift`, `Motion*.swift`, spring and stagger values, `Reveal` distance), illustrations (`BreathRibbon`, `Keycap` proportions, Onboarding's large `LiveKeycap`), chart geometry (`ActivityHeatmap`, `InsightsHeatmap`, `CategoryBar`, `SignalPlot`), the toolbar's notice badge, colour opacities that encode data (heatmap levels, category emphasis), and the pill, whose `FloatingPill.Metrics` grid is its own token source.

## Open items

- Pill hover hints, Esc, hold-to-talk (meter only) and the meter moving with real speech still need checking live, with a person speaking.
