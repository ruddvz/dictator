# Critique and improvement roadmap: Wispr Flow, TypeWhisper, HushKey

_Written 2026-11-01. Builds on [COMPETITOR_RESEARCH.md](COMPETITOR_RESEARCH.md) and the [supplied report](research/Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf)._

## Ground rules

We study how other products **behave** — screens, states, flows, timing, failure handling — and build our own native version that improves on them. We do not copy proprietary source, assets, or text (Wispr Flow), and we do not copy GPL code (TypeWhisper, VoiceInk) into HushKey's MIT codebase. Permissively licensed libraries (MIT/Apache, e.g. WhisperKit) can be used with attribution after a license check.

Every "better" claim below should become a measurable check in the evaluation harness (see [Measuring it](#measuring-it)).

---

## Wispr Flow

**What it gets right**

- **One gesture to dictate anywhere.** Hold `fn`, talk, release. The shortcut is the product; the window is secondary.
- **Always-visible state.** A tiny bar sits at the bottom of the screen and expands while listening. You never wonder whether it heard you.
- **Polished output by default.** Removes fillers and self-corrections ("no wait, Tuesday"), formats lists, adapts tone per app.
- **A home that rewards use.** Greeting, words / wpm / streak, and a day-grouped history with play, copy, and flag actions on hover.
- **Personalization is first-class.** Dictionary, Snippets, Style (personal / work / email), Transforms, Auto Cleanup levels.
- **Onboarding as a checklist** in the sidebar rather than a blocking wizard.

**Critique**

- **Cloud-dependent.** Its help center says desktop transcription needs an internet connection. Offline, on a plane, or under a strict privacy policy, it stops working, and sensitive text leaves the Mac.
- **Polish can overreach.** Rewriting is the default; recovering *exactly what you said* is a secondary action. For legal, medical, or code text, silent rewriting is a liability.
- **Opaque context use.** App-aware styling is convenient, but users can't easily see what context was read for a given dictation.
- **Heavy runtime.** It's an Electron app (the REA inventory found an `app.asar` marker), so it carries more memory and battery cost than a native utility.
- **Voice only.** You still have to speak audibly. Open offices, libraries, late nights next to a partner, calls in progress: speaking is socially costly, and whispering degrades accuracy.
- **Subscription friction** for a tool people use for seconds at a time.
- **Feature sprawl.** Notetaker, Insights, Scratchpad, team invites, and referrals compete with the core loop in the sidebar.

**What HushKey should do better**

| Wispr behavior | HushKey improvement |
| --- | --- |
| Cloud transcription | On-device by default (Apple Speech, WhisperKit), with a visible "nothing left this Mac" receipt per dictation |
| Rewrite-first output | Raw and processed text are both kept; one keystroke flips between them; polishing is a visible, reversible step |
| Hidden context | Per-dictation chip shows mode, target app, and whether nearby text hints were used (partly shipped) |
| Voice-only | Voice → whisper → silent commands → head gestures, chosen per situation (see the multimodal lane below) |
| Electron | Native SwiftUI/AppKit; target <80 MB idle memory and no background CPU while idle |
| Sprawling sidebar | Write / Silent Lab / Manage, with labs hidden until headphones are present |

## TypeWhisper

**What it gets right**

- **Local engines and model choice**, including plugin engines and a macOS 26 SpeechAnalyzer path.
- **Workflows:** per-app, per-site, and per-hotkey rules that pick engine, prompt, and output.
- **Developer surface:** local HTTP API and CLI for recording, dictionary, and per-request engine choice.
- **File and subtitle transcription** (SRT/VTT), filler-word add-on, statistics, backup/restore.
- **No telemetry, no mandatory cloud.**

**Critique**

- **Power-user first.** The settings surface is large; recent releases are still reshaping settings and adding a setup wizard, which signals onboarding friction.
- **Optional cloud LLMs blur the privacy story.** It's local unless a workflow sends text to OpenAI or Gemini, and users must know which workflows do that.
- **Plugin breadth over a polished core loop.** Quality depends on which engine and plugins the user assembled.
- **GPL-3.0 plus a commercial license for rebranded distributions.** That's fine for them; for us it means ideas only, no code.
- **Voice only**, like Wispr.

**What HushKey should do better**

| TypeWhisper behavior | HushKey improvement |
| --- | --- |
| Many engines, user assembles | One recommended engine per Mac, chosen by our own benchmark; advanced choice tucked away |
| Workflows as rules | Keep rules, but show them as plain sentences ("In Xcode, use Code mode") with a live preview |
| Optional cloud LLM | On-device Foundation Model only; no cloud fallback, stated in UI |
| Local API/CLI | Worth matching later (App Intents + Shortcuts first, since they're native and permissioned) |
| Statistics, backup | Stats shipped on the home; add export/import of vocabulary, snippets, and history |

## HushKey today: honest critique

- **The core loop isn't accepted on real apps yet.** Microphone, whisper capture, global shortcut, insertion, and undo still need the manual pass in TextEdit plus a second app. Nothing else matters until this works every time.
- **No streaming insertion.** Text appears only after stop plus finalization; Wispr feels faster because the release-to-text gap is short. Measure and minimize that gap.
- **Insertion uses Accessibility only.** That's safer than clipboard paste, but some apps (Electron, terminals, web editors) reject AX value writes. We need a per-app fallback policy that the user can see.
- **Polishing is a separate screen.** Transforms should be reachable from the pill and history rows, not only from a sidebar page.
- **The Silent Lab reads as a science project.** Its evidence gates are right, but the user doesn't see a reason to use it day to day yet. The multimodal lane below fixes that by shipping the reliable pieces first.
- **No benchmark.** We can't yet say HushKey is more accurate than anything. The eval harness is the fix.

---

## The multimodal lane: what makes HushKey different

### What the AirPods actually sense

Through Apple's public `CMHeadphoneMotionManager` API, compatible AirPods report **head motion only**: attitude (pitch/roll/yaw), rotation rate, gravity, and user acceleration, at a low rate (HushKey's Setup screen shows the live rate). That's all a third-party app receives.

- **Head movement:** sensed directly and reliably.
- **Jaw movement:** sensed **indirectly**. Chewing or mouthing words causes tiny vibrations and tilts that travel through the skull to the earbud. The signal is weak, low-rate, and easily swamped by walking or turning your head. Research systems that decode silent words from jaw motion (e.g. MuteIt, ACM IMWUT 2022) place IMUs near the jaw, use two IMUs to cancel head motion, and still restrict themselves to about 100 command words.
- **Lip movement:** **not sensed by AirPods.** Apple patents and reports describe future AirPods that read facial-skin or lip micro-movements, but no such sensor or API is available today. Lips can only be read today by the Mac's camera.
- **AirPods' internal voice accelerometer:** Apple uses it for voice isolation, but it isn't exposed to apps.

So "silent dictation of anything" is not achievable with today's hardware, and we shouldn't promise it. A **layered quiet-input system** is achievable, and it's something neither Wispr nor TypeWhisper has.

### The layers, from most to least reliable

1. **Head gestures as hands-free commands.** _Feasible now; high value._ Nod to insert, shake to discard, tilt to restore the original, double-nod to start or stop. Head motion is exactly what the sensor measures well, and a 4–6 gesture set can be trained in minutes with the existing template/DTW pipeline. This makes the whole voice loop hands-free, which is something Wispr can't do.
2. **Speaking confirmation for the microphone.** _Feasible; needs validation._ Use jaw-induced micro-motion as a second signal that *the wearer* is talking. This can reject a colleague's voice or TV audio during hold-to-talk, and trim leading and trailing silence. It's a binary "is the wearer articulating?" question, which is far easier than word recognition.
3. **Whisper boost.** _Research._ When whisper mode is on, motion-based segmentation marks word boundaries to help the recognizer on low-energy audio. Measure the WER change on whispered clips; keep it only if it helps.
4. **Silent command vocabulary.** _Research; behind evidence gates._ A small, user-trained set (10–20 commands such as "send", "new line", "undo", "next field") recognized from motion alone, unlocked per user only when leave-one-session-out accuracy beats baseline (already built into Evaluate). Commands, not free dictation.
5. **Camera lip-reading.** _Optional future; strictly opt-in._ On-device visual speech recognition from the Mac camera, fused with whisper audio and head-motion segmentation. It needs a license-compatible on-device model and a clear camera indicator, and it never runs by default.

### Product shape

- **Quiet level picker** on the pill and home: *Voice*, *Whisper*, *Silent commands*, *Gestures only*. HushKey suggests a level from context (e.g. a call is active, so suggest Gestures) but never switches silently.
- **The pill reflects every channel:** waveform for audio, a small head icon that pulses when motion confirms you're speaking, and a gesture glyph when a nod or shake is recognized.
- **Silent Lab becomes "Train gestures and commands"**: a 2-minute guided session, a per-gesture confidence readout, and an honest "not reliable for you yet" state.
- **Everything stays local.** Motion data never leaves the Mac; training data can be exported or deleted, as today.

---

## Prioritized roadmap

**Now (core reliability)**
1. Manual acceptance of mic, whisper, shortcut, insertion, and undo in TextEdit plus one Electron app; fix what fails.
2. Measure the release-to-text latency and show it in dev builds; target under 600 ms for short phrases on M1 Pro.
3. Per-app insertion fallback policy (AX first; opt-in paste for apps that reject AX), shown in the target-app chip.
4. Pill states verified live: listening, transcribing, inserted, failed with reason.

**Next (beat Wispr on the loop)**
5. Head-gesture commands (nod insert, shake discard, tilt restore) using the existing motion pipeline, with a training flow.
6. Raw ↔ polished toggle on the pill and in history; Transforms reachable from both.
7. Streaming partial text in the pill for long dictations.
8. Vocabulary, snippets, and history export/import; App Intents for Shortcuts.

**Later (research lanes, evidence-gated)**
9. Motion-based "wearer is speaking" confirmation, measured on false accepts and rejects with a second voice in the room.
10. Whisper boost via motion segmentation, measured as a WER change.
11. Silent command vocabulary, unlocked per user by the existing evaluation gates.
12. Opt-in camera lip-reading prototype, after a model and license review.

## Measuring it

Each item ships with a check in the held-out evaluation harness:

- **Dictation:** WER on dev and holdout clips (normal and whispered), formatting checks per mode, release-to-text latency.
- **Insertion:** success rate per app category; no duplicate inserts; undo restores exactly.
- **Gestures:** per-gesture precision and recall on a held-out session; false triggers per hour while walking and talking.
- **Speaking confirmation:** false-accept rate with another speaker present.
- **Silent commands:** leave-one-session-out accuracy vs. majority baseline, with a permutation test (existing protocol).

"Better than Wispr" is claimed only where a number says so.

## Sources

- Wispr Flow product and help pages; installed v1.6.1337 visible-UI review (see [COMPETITOR_RESEARCH.md](COMPETITOR_RESEARCH.md)).
- [TypeWhisper repository](https://github.com/TypeWhisper/typewhisper-mac) and [release notes](https://newreleases.io/project/github/TypeWhisper/typewhisper-mac/release/v1.3.0); [Digital Trends hands-on](https://www.digitaltrends.com/computing/i-found-a-better-way-to-dictate-on-my-mac-and-it-doesnt-need-the-cloud/); [AlternativeTo listing](https://alternativeto.net/software/typewhisper/about).
- MuteIt, jaw-motion IMU silent speech: [ACM IMWUT 2022, doi:10.1145/3550281](https://doi.org/10.1145/3550281).
- Apple silent-speech patent and reports (not shipping hardware): [MobileIDWorld](https://mobileidworld.com/new-apple-patent-explores-silent-voice-recognition-for-future-airpods-111301/), [Macworld](https://www.macworld.com/article/675759/patent-control-your-airpods-with-a-wink-or-smile.html).

## Related project: amirrsyed/hushkey (checked 2026-11-01)

- An independent MIT project by Amir Syed, created 2026-10-31, with the **same name**. It does silent dictation by **webcam lip reading**: a native Mac app plus a local Python model server. The model is a frozen Auto-AVSR conformer with LoRA adapters, a lip/jaw/throat "kinematic" branch, and in-app "Train on my mouth" personalisation. It reports 19.1% WER on voiced LRS3 and says outright that silent webcam use is worse.
- Why it matters to us: it covers the channel AirPods can't sense (lips), and its roadmap lists AirPods head/jaw motion as a future input, which is what our Silent Lab does. The two approaches complement each other.
- Ideas worth taking (MIT, attribute in `NOTICE.md` if code is adapted): a HUD with a live partial transcript (we now have the transcript card), Esc to cancel, clipboard restore after paste, energy-gate segmentation with pre-roll/hang-over, and paired-bootstrap eval comparisons for our eval harness.
- Risk: the shared name could confuse people on GitHub and in search. Decide whether to keep "HushKey" before any public release.
- A Codex session cloned it to `~/Documents/ChatGPT/HushKey` and left uncommitted edits there. They belong to that repo, not ours, and were not merged.
