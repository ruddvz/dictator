# Instant start, menu bar first, pill geometry (2026-11-04)

How other dictation apps start recording without a stutter, live in the menu bar, and size their pill. TypeWhisper and VoiceInk are GPL: behaviour only, no code. FreeFlow and OpenWhispr are MIT.

## Instant start

- **FreeFlow** (`Sources/AppState.swift` `beginRecording`): capture starts on a background queue; the "initializing" overlay shows only if no audio arrives within 0.2 s; the waveform and start sound wait for the first non-silent buffer; context capture runs after the recorder starts. A generation counter stops a cancelled slow start from coming back (`RecordingCaptureTiming.swift`).
- **OpenWhispr** (`micStreamHold.js`, `micWarmState.js`): optional idle mic hold; "warm" expires after 5 s.
- **TypeWhisper** (behaviour): optional pre-roll keeps built-in/USB input armed with a 0.5 s ring buffer; not for Bluetooth by default (it forces HFP and degrades output); released on sleep/lock; starts on a dedicated queue; rebuilds once on an all-silent Bluetooth stream.
- **VoiceInk** (behaviour): prepares the CoreAudio unit ahead of time on a setup queue and invalidates it on device change.

**Dictator, measured before the fix:** fn → listening took 280–710 ms, mostly on the main thread: audio engine build + start 116–391 ms, cue + mute 30–107 ms, Apple Intelligence prewarm 9–36 ms. The pill panel also resized as it opened, which showed the old pill up and to the left for a frame, and the "Waiting for microphone" hint flashed.

**Done:** engine build/start/stop on a serial queue; cue playback on its own queue; cleanup prewarm after the mic opens; a fixed minimum panel size so idle → hover → recording never resizes the window; the waiting hint and sweep only after 600 ms. **Later:** prepare the engine at idle for built-in/USB mics (not Bluetooth), expiring on device change, sleep and lock.

## Menu bar first

- FreeFlow, TypeWhisper, VoiceInk: `LSUIElement`/`.accessory`, `.regular` only while a window is open. OpenWhispr warns not to infer Dock state from occlusion events. Wispr Flow has a "Show in dock" toggle.
- TypeWhisper's menu: status line, shortcut submenu, Start Recorder, Microphone / Language / Model submenus, Settings, History, Error Log, Pause Dictation Hotkeys, Transcribe File, Recover Last Recording, Last Transcription, Copy Last Transcription, Correct Last Dictation, Check for Updates, Quit. Recording icon: red badge.
- Superwhisper's status dot: yellow loading, red recording, blue processing, green done.

**Done:** Dictator shows in the Dock only while the hub is open ("Always show in Dock" keeps the old behaviour). **Next:** a status line first in the menu, and Language / Model / History / Transcribe file / Recover last recording entries.

## Pill geometry

| App | Idle | Recording | Above visible bottom | Motion |
|---|---|---|---|---|
| VoiceInk | 184 × 40, r 20 | 300 wide, r 14 | 24 pt | easeInOut 0.3 s |
| TypeWhisper (minimal) | 42 wide | 76 processing, body 52 tall | 20 pt, in a 420 × 160 transparent host | spring 0.38 / 0.78, reveal from 0.92 |
| OpenWhispr | 40 × 40 | 98 × 36 | 12 px | 260 ms acknowledge, 300 ms grow `cubic-bezier(0.2,0,0,1)`, meter +100 ms |
| FreeFlow | top, under the notch, 92 wide | — | — | 0.18 s slide, 0.22 s resize, spring 0.28 no bounce; 9 bars at 30 fps |
| Wispr Flow | bottom centre, draggable | white bars | unverified | unverified |

TypeWhisper also hosts its pill in a larger transparent panel, which is the approach Dictator now takes.
