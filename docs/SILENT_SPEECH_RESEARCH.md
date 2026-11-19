# Silent Use: SubVox and similar work (2026-11-02)

How Dictator's Silent Use compares with SubVox and other silent-speech work, what was tried on real takes, and what changed.

## The short answer

Dictator's Silent Use is a close adaptation of [joeblau/subvox](https://github.com/joeblau/subvox) (MIT). It uses the same channels (user acceleration, rotation rate, attitude change), the same per-user templates matched with 1-nearest-neighbour DTW, and the same distance and margin rejection. Its evidence gate (leave-one-out, a permutation test, and a held-out session) is stricter than SubVox's.

SubVox publishes no accuracy figures. Upstream has had no changes since commit `591d028`, the one Dictator adapted. No peer-reviewed work shows mouthed words decoded from commodity earbud head motion. The strong results either use sensors taped to the jaw or decode sentences rather than single words.

On this Mac's own 37 silent takes, decoding is only just above chance. The changes below make the evidence clearly significant (p 0.026 → 0.002), but accuracy is still under 50 % for 5 words.

## Related work

| Project | Licence | Sensor | Vocabulary, users | Reported accuracy | Held-out session? |
|---|---|---|---|---|---|
| [joeblau/subvox](https://github.com/joeblau/subvox) | MIT | AirPods, `CMHeadphoneMotionManager` | user-chosen words, 1 | none published | no |
| [Spiro-12/silent-speech](https://github.com/Spiro-12/silent-speech) | MIT | AirPods Pro 3, `CMHeadphoneMotionManager` at ~50 Hz | 7 sentences + "nothing", 1 | 88 % leave-one-session-out; 0 wrong of 420 at 0.70 confidence | yes; across ears 57–84 % |
| [Gheop/mutix](https://github.com/Gheop/mutix) (Rust/Linux port of SubVox) | MIT | AirPods Pro 3 via the accessory protocol, ~85–100 Hz | 4 / 12 words, 1 | leave-one-out 74 % (4 words), 64 % (12); live about half and "almost none" | no |
| [fivetwentythree/Loq](https://github.com/fivetwentythree/Loq) (SubVox fork) | MIT | AirPods Pro 2, ~50 Hz | user-chosen | none | no |
| [nottherealsanta/speechless](https://github.com/nottherealsanta/speechless) | MIT | AirPods motion + Moonshine-Tiny | — | none | no |
| MuteIt (IMWUT 2022) | no code | two IMUs taped at the jaw joint and behind the ear, 100 Hz | 100 words, 20 users, 5 takes per word | 94.8 % still, ~91 % while moving | yes, >90 % |
| JawSense (HotMobile 2021) | no code | cheek accelerometer, 550 Hz | 9 phonemes, 6 users | 92 % | not reported |
| Unvoiced (SenSys 2024) | no code | twin jaw IMUs → spectrogram → ASR + LLM | free-form, 19 users | <9 % WER | not reported |
| QuietSync / Whispering Wearables (ICMI 2024) | no code | headphone IMU + ExG electrodes | 12 commands, 9 users | 94 % fused (IMU alone reportedly ~80 %, unverified) | not reported |
| EarCommand, EarSSR, HPSpeech, EchoSpeech | no code | in-ear ultrasound / acoustic sensing / sonar on glasses | 8–32 commands | 82–95 % | for contrast: active acoustic sensing, not head motion |

No code was copied. Spiro-12, mutix, Loq and speechless are MIT, so their code could be adapted with attribution in `NOTICE.md`. The academic systems have no published code. Several of the names suggested at the start (TWIST, WhisperWand, EarHear) could not be found.

## Techniques the sources suggest

The sources are ranked by how directly they measured each technique. Results on this Mac's takes come from `Scripts/silent-eval.sh` or the Python prototype that preceded it.

| Technique | Source | Result here | Status |
|---|---|---|---|
| Light smoothing (3-sample moving average) | general; reduces sensor noise at ~50 Hz | **38 % → 43 %** (all takes), **33 % → 48 %** (clean takes); p 0.026 → 0.002 | **adopted** (`MotionFeatures.defaultSmoothing`) |
| Reject takes with head turns or bad length | speechless drops head-turn windows; mutix notes segmentation mismatches | 4 of 37 takes flagged (one 3.8 s take, three with head jerks over 1 rad/s) | **adopted** (`MotionFeatures.takeIssue`) for new takes and live decoding |
| A trained "nothing" class (still, mouth closed) | Spiro-12: 0 of 27 nothing-takes misread | not measurable yet (no such takes) | **adopted** (`TemplateClassifier.restLabel`); never typed |
| Templates from several sessions | Spiro-12: held-out 92 % → 98 % from 1 to 4 sessions | this data is one session | already required by the evidence gate |
| 1 Hz zero-phase high-pass, drop attitude | Spiro-12 | 39 % (rotation + acceleration) | not adopted: no gain on this data |
| Resample to 96 points + narrow DTW band + per-take z-normalisation | Spiro-12 | 30–45 % depending on band | not adopted: unstable |
| Derivative features | mutix (58 % → 75 % there) | 39–42 % | not adopted |
| 3-NN weighted votes | Spiro-12 | 33–48 %, no consistent gain | not adopted |
| Mirror right-ear data into the left-ear frame | Spiro-12: cross-ear 27–34 % → 63–84 % | can't tell which ear is worn | future |
| DTW vs neural models | Spiro-12: DTW 88 % beat MiniRocket 85 % and a 1D CNN 79 % | — | keep DTW at this data size |

A caution on these numbers: with 33–37 takes, one take moves accuracy by about 3 points, and the standard error is about 8 points. Only smoothing improved both accuracy and the permutation p-value in every slice. The other techniques may still help on larger, multi-session data, and the harness is there to check.

## What was broken end to end, and what changed

1. **Silent Use re-locked after every launch and every new take.** The evidence lived only in memory and was cleared whenever templates changed, so you had to run Evaluate again each time. Now `AppModel.silentEvidence` re-runs in the background whenever the silent templates change, including at launch. It no longer depends on which condition the Evaluate screen is showing.
2. **A trained word could not reach another app.** Hold capture only worked while Dictator was frontmost, and insertion refuses to target Dictator itself. You had to capture, switch apps, then press the insert shortcut. Now:
   - Holding **Control** on its own captures a silent word on Train and on an unlocked Silent Use, in any app (`FunctionKeyMonitor(key: .control)`, the same hold logic as fn for dictation). ⌃C and other Control shortcuts cancel the capture.
   - Accepted words are typed into the frontmost app (**Type into the front app**, on by default). Rejected matches and the "nothing" class are never typed.
3. **Junk takes became templates.** Head turns and stray presses were saved silently. They are now refused with a reason, and live captures with the same problems are never typed.

## Head movement versus jaw movement (2026-11-03)

AirPods report the head as one rigid body, so jaw movement and head movement arrive in the same stream. On this Mac's 37 takes they separate cleanly by size and speed:

| | Head tilt over the take | Slow rotation (< 1.5 Hz) peak |
|---|---:|---:|
| 32 mouthed words | 0.3–1.3° | 0.015–0.079 rad/s |
| 5 takes with a nod or turn | 2.0–19.8° | 0.06–0.86 rad/s |

The old check only refused a take whose rotation spiked above 0.6 rad/s, so a slight nod (about 0.2–0.4 rad/s) passed. Now (`MotionFeatures.headMoved`) a take or live capture is refused when the head tilts more than 2.5° from where it began, or slow-band rotation passes 0.12 rad/s, or any spike passes 0.6 rad/s:

- Train won't save it.
- Silent Use won't type it.
- Auto-capture won't start on it.
- Saved takes that fail are flagged and no longer train the classifier.

Removing those 5 takes raised leave-one-out accuracy from 48 % to 53 % (chance 34 %, p = 0.003).

Filtering the slow band out of the classifier's features was also measured and rejected. A 1.5 Hz high-pass dropped clean-take accuracy to 28 % (all channels) or 38 % (rotation + acceleration), and gentler 0.3–0.5 Hz drift removal to 31–38 %. A silently mouthed word moves the jaw slowly too, so the filter removes the word along with the head. The rule is therefore: keep the head still (the app says so live), and refuse anything where it wasn't.

## Measuring further changes

```bash
Scripts/silent-eval.sh            # scores ~/Library/Application Support/com.ruddvz.dictator/dataset.json
Scripts/silent-eval.sh other.json # or any exported dataset
```

The script writes `docs/eval/silent-report.md`, which holds aggregate numbers only. Record a second session (Train → New session) of every word before trusting any gain; until then the held-out-session column stays empty and Silent Use stays locked.
