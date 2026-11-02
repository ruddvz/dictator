# Recording pill: UX gap analysis against Wispr Flow

_2026-11-02. Sources: the user's screenshots of HushKey (idle, recording) and Wispr Flow (hover, Notetaker hover, recording), Wispr's help center, and the existing measurements in `docs/DESIGN_SYSTEM.md`. Only behaviour and proportions are compared. No Wispr assets, code or copy are reused._

## What Wispr Flow does

| State | Wispr Flow (observed or documented) |
| --- | --- |
| Idle | A ~40 × 8 dark capsule bottom-centre. It shrinks to a dot after a few seconds idle. It can be hidden, and newer builds let you drag it to either screen edge. |
| Hover | Grows into a small capsule of icon buttons (dictate, Notetaker, chevron). Each button shows a tiny black tooltip above the bar with the action and its shortcut: "Dictate fn", "Start Notetaker ⌥M". No sentence of instructions. |
| Recording | A very small black capsule, about 28 pt tall: × on the left, dense white vertical level bars in the middle, a white ✓/stop on the right. A ping marks the start. There is no timer, no label, and no live text. |
| Hold vs hands-free | Hold fn to talk; double-tap fn or fn+Space for hands-free. In hands-free the bar keeps the stop control. Clicking again within 0.5 s cancels instead of pasting. |
| Processing | The bars freeze or settle and a small spinner shows. The paste itself is the success state. |
| Cancel | × or Esc. A cancel notice offers **Undo**, which pastes the last transcript. |
| Problems | Short warnings tied to the bar: "Is your microphone muted? We couldn't hear you", "Microphone unavailable", "No microphone detected", each with one action (Open Sound Settings, Choose microphone). Nothing is pasted when no audio was heard. |
| Mic picker | Right-click the bar, then Microphone. |
| Long sessions | Warns at 19 min and stops at 20, then transcribes what it has. |

## Where HushKey falls short

| Area | HushKey today | Gap |
| --- | --- | --- |
| **Size** | The recording pill is about 200 × 32: ×, a 92 pt ribbon, a timer and a stop button. With no text field focused, a 340 pt card sits on top of it. | Roughly 2.5× Wispr's footprint. It covers the content you are dictating into, and reads as a panel instead of an indicator. |
| **Waveform responsiveness** | `VoiceRibbon` draws three thin sine lines that are tapered to zero at both ends, with at most ±9 pt of travel. Ordinary speech moves the centre by 2–4 pt. | This is the main complaint: "the waveform barely moves". The taper hides motion at the edges, the thin strokes have low contrast on dark, and a 1:1 energy curve keeps quiet speech nearly flat. |
| **Contrast** | Sage strokes at 30–100 % opacity on a 96 % sage-black surface. | Wispr's bars are crisp and full-contrast. Ours look faded, especially the two back ribbons. |
| **State clarity** | Preparing and finishing swap the pill for a spinner and a sentence ("Preparing locally", "Writing it up"), so the shape jumps three times in one dictation. The no-target card shows a large faded "Listening…" before any words arrive. | The pill should keep one shape from start to finish and change what is inside it. An empty "Listening…" headline is noise. |
| **Hold vs hands-free** | Identical visuals. | When fn is held, the × and stop buttons can't be used and only add width. Hands-free should look latched. |
| **Confirm affordance** | A grey square stop at 65 % opacity. | Wispr's ✓ reads as "done, type it". A stop square reads as media playback and doesn't stand out from ×. |
| **Hover affordances** | Hover expands into a full sentence, "Hold fn or click to talk". Button help uses `.help`, which shows late and inconsistently in a non-activating panel. | Wispr gives a compact control plus a short tooltip that names the shortcut. Ours gives a sentence and slow tooltips. |
| **Placement** | Centred on `NSScreen.main`, 10 pt above the Dock/visible bottom. It can't be moved or shrunk. | Close enough to Wispr. A drag-to-edge or auto-shrink option is a nice extra, not a gap that hurts. |
| **Dismissal** | × and Esc cancel; the finished card closes with × or Esc. | At parity. There is no Undo after cancel (Wispr pastes the last transcript); HushKey's Paste again only covers failed inserts. |
| **Problems** | The pill error state is already in place (danger icon, short message, Retry / Paste again / dismiss). | At parity on structure. There's no dedicated "we couldn't hear you" or "mic unavailable" action that opens Sound settings or a mic picker. |
| **Tokens** | The pill hard-codes `#141B17` and `#9CCBB4` in `FloatingPill.swift`. | This breaks the design-system rule of no hard-coded colours. |

## Prioritised fixes

**P0, done in this pass**

1. **Level bars instead of the ribbon** (`PillMeter`). Dense, rounded vertical bars that are full-contrast `ink` on the dark pill and centre-weighted. Each bar moves on its own smooth wobble, scaled by the shared `SpeechEnvelope` through a perceptual curve (`√energy`) so quiet speech still shows. They rise fast and fall slowly. In silence they rest as dots that breathe slightly, so the mic still reads as live.
2. **Compact recording capsule**, 28 pt tall: × · bars · ✓. The ✓ is a filled sage `signal` circle, the one primary action. The timer only appears after 30 s, when it starts to help.
3. **Hold mode shows bars only.** While fn (or the custom shortcut) is held, the pill is just the meter, about 80 pt wide. Click or hands-free dictation shows the × and ✓ controls.
4. **One shape through the dictation.** Preparing and finishing keep the recording capsule and animate the bars instead: a soft sweep while waiting for the mic, and a travelling highlight while transcribing. A short hint bubble above the pill names the wait ("Waiting for microphone", "Preparing locally").
5. **Hover hint bubble.** On hover the idle bar becomes a small mic capsule, with a tooltip above it: "Dictate" plus the shortcut keycap. Hovering × or ✓ shows "Cancel · esc" or "Finish · fn" in the same bubble. Instant, unlike `.help`.
6. **Lighter no-target card.** Before words arrive it is a one-line hint strip, not a 340 pt card with a placeholder headline. Live text appears at 16 pt in a 320 pt card once there is something to read.
7. **Tokens only.** The pill uses `Theme.paper`, `Theme.signal`, `Theme.ink` and `Theme.hairline`, which resolve to their dark values because the panel is forced dark.

**P1, next**

- "We couldn't hear you" and "Microphone unavailable" errors with **Open Sound settings** / **Choose microphone** actions, and a right-click mic picker on the pill.
- **Undo after cancel:** keep the cancelled audio for a few seconds and offer "Transcribe anyway".
- Start/stop sounds (optional, off by default).

**P2**

- Auto-shrink the idle bar to a dot, an option to hide it, and drag-to-edge placement that is remembered.
- Follow the screen with the mouse or the key window instead of `NSScreen.main`.
- A Meeting notes button in the hover capsule (HushKey's equivalent of Notetaker).
- A long-session warning before any time limit.
