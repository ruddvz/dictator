# App-wide UX gap analysis against Wispr Flow

_2026-11-02. Sources: Wispr Flow's installed app (home screen and its accessibility tree, read today), the measurements in `docs/DESIGN_SYSTEM.md` (Wispr 1.6, 2026-11-01), `docs/CRITIQUE_AND_ROADMAP.md`, and Wispr's help centre. The pill has its own write-up in `docs/PILL_UX_ANALYSIS.md`. Behaviour and structure only; no Wispr assets, code or copy are reused._

## Where things stand

Dictator matches or beats Wispr on **breadth**: local dictation, modes, vocabulary and snippets, transforms, app profiles, file transcription, meeting notes, history with raw restore, recovery and Paste again. Layout, spacing and type were already matched to Wispr's measurements.

The gap is in how much of that breadth **shows up where you'd look for it**, and how much happens without setup. Wispr puts a few strong ideas on screen. Dictator has the same or better machinery, but much of it sits in Settings rows.

| Area | Wispr Flow | Dictator | Gap |
| --- | --- | --- | --- |
| **Style** | A sidebar page with tabs for Personal messages, Work messages, Email and Other. Each tab shows the apps it covers and three tone cards (Formal, Casual, Very casual) with a live sample message. The choice applies whenever you dictate into those apps. | Writing *modes* (Natural, Message, Email, Code) picked automatically by app, plus per-app profiles in Settings. There is no tone choice: everything comes out fully capitalised and punctuated. | **Large.** It's the most visible personalisation in Wispr and Dictator has no equivalent page or tone control. |
| **Recording pill** | Compact, crisp bars, ×/✓, hover tooltips, right-click mic menu, drag to an edge, warnings about mic problems, cancel with Undo. | Done in the pill passes (see `PILL_UX_ANALYSIS.md`). | Closed, apart from live checks. |
| **Home** | Greeting with the fn keycap, a full-width hero ("Make Flow sound like you"), a stats card (words, wpm, streak), a Voice Profile progress card, and day-grouped history. Rows have play, copy, flag and more on hover. A dismissed dictation stays in history with **Recover**. | Greeting with keycap, a next-step hero, a stats card with a 12-week heatmap, a composer, and day-grouped history with hover actions. | **Small.** The hero should point at Style the way Wispr's does. Dictator keeps no audio by design, so there is no play action. A cancelled dictation stays in History with **Recover** until you quit (done). |
| **Dictionary / Snippets** | Separate pages. | One "Vocabulary" page with sections, plus import/export. | Parity. |
| **Transforms** | Card grid with shortcuts. | Card grid, on-device writing styles. | Parity. |
| **Notetaker** | Its own page plus a setup checklist (connect calendar, import meetings, tour). | Meeting notes page (local capture). | Different by design; Dictator has no calendar. |
| **Insights** | Your Usage (WPM gauge, fixes made, total words with books and monthly change, usage by app category, streak heatmap) and a Leaderboard. | **Insights** page with the same Your Usage cards, from a local daily ledger (counts only). | Done for Your Usage. The Leaderboard needs accounts and a server, so it's left out on purpose. |
| **Scratchpad** | Being removed from Wispr's default bar (July 2026 help article). | The home composer covers it. | None. |
| **Onboarding** | A sidebar checklist plus a "Take 2-min tour" button. | A sidebar checklist ("Get set up"). | Small: there's no guided tour. |
| **Chrome** | Theme, notifications and account buttons in the toolbar. | Appearance lives in Settings. | Cosmetic. |

## Prioritised fixes

1. **Style page (done in this pass).** A new sidebar page, **Style**, with Wispr-like contexts: Personal messages, Work messages, Email, Other. Each shows the apps it covers and three tone cards (Formal, Casual, Very casual) with a live preview made by the same on-device formatter dictation uses. Tone is applied after mode formatting and before snippets. Code mode is never touched. The default is Formal everywhere, so nothing changes until someone picks a tone.
   - *Formal*: as recognised, with capitals and full punctuation.
   - *Casual*: capitals kept, the final full stop dropped.
   - *Very casual*: lower-case sentence starts (except "I" and words in capitals) and no full stops at sentence ends. Question and exclamation marks stay.
2. **Home hero points at Style (done in this pass)** once insertion is on, the way Wispr's "sound like you" banner does.
3. **Recover cancelled dictations from history** for the session (in memory only, matching Dictator's privacy stance). Done.
4. **A guided 2-minute tour** from the setup checklist. Next.
5. **Insights page:** done (Your Usage only).
6. **Searchable Languages grid** like Wispr's picker: done. Single choice, since on-device recognition has no auto-detect or multi-language mode.
