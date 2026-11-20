# Wispr Flow recognition and text quality

## Which recognition model does Flow use, and what does “real-time” mean in the app?

### Takeaway
As of 2026-11-20, Wispr says desktop dictation runs on its in-house Canto speech model, not an OpenAI Whisper wrapper. Canto is described as a real-time model, but the current desktop user flow inserts the completed transcript after the user stops; the public documentation does not establish that desktop shows streaming partial words. Canto's architecture, parameter count, and downloadable weights are not publicly specified in the material reviewed.

### Cited Findings
- Wispr introduced Canto as its first in-house real-time speech model on 2026-09-17; its November 9 report calls the released version “Canto 1” and says the model had been live for two months. — [Canto announcement](https://wisprflow.ai/canto), [Canto 1 results](https://wisprflow.ai/canto-1-results), [What's new](https://wisprflow.ai/whats-new)
- The model was pretrained on “millions of hours of speech and text,” then trained with supervised fine-tuning followed by reinforcement learning using Group Relative Policy Optimization (GRPO). Wispr describes scoring multiple full transcript candidates against references and learning from their relative scores. — [Canto training description](https://wisprflow.ai/canto)
- The November report says its latency budget is below 700 ms from end of speech to visible text, including recognition, formatting, OS and network time. After Canto replaced the prior multi-recognizer ensemble, Wispr reports dictations taking over one second fell 54% on desktop and 37% on mobile. These are vendor-reported operational metrics. — [Canto 1 results](https://wisprflow.ai/canto-1-results)
- The Help Center says desktop transcription needs internet, and desktop inserts the finished text after Stop rather than showing words one by one while the user speaks. Therefore “real-time model” should not be interpreted as proof of visible live transcription in the desktop composer. — [What is Wispr Flow?](https://docs.wisprflow.ai/articles/2772472373-what-is-flow)
- The company says Canto replaced a previous setup that ran multiple recognizers per dictation and waited for them before selecting the result. The current Canto successor is described as still training at more than 10× Canto 1's scale; no public launch date is given. — [Canto 1 results](https://wisprflow.ai/canto-1-results)
- Flow's transcription is cloud-based: audio goes to Wispr servers and is processed there. Wispr says model-improvement opt-in, persistent cloud storage, and cloud processing are separate settings/actions; disabling model improvement does not stop server-side transcription. — [Wispr security and privacy](https://wisprflow.ai/dictation-blogs/is-wispr-flow-safe-security-and-privacy)

### Inferences
- Dictator should measure end-of-speech-to-insertion tail latency (especially p90/p95 and percentage over one second), not only model inference time or average speed. This is directly comparable to Wispr's user-visible latency budget.
- Visible incremental words are a product choice separate from recognition speed. Dictator's Apple Speech path already exposes partials locally, while its Parakeet path runs after key release; these are documented in `MicTranscriber.swift` and `ParakeetDictationEngine.swift`. A polished design should make the chosen behavior and finalization state clear rather than label a fast final result “streaming.”
- A cloud model could be evaluated as an optional engine, but it would change Dictator's current local-first privacy posture and add network/provider availability to the critical path. It should not silently replace on-device engines.

### Gaps
- Wispr does not disclose the Canto model architecture, parameter count, training corpus composition beyond broad statements, full inference pipeline, per-model comparison details sufficient to reproduce its reported win, or a general release cadence in the sources reviewed.
- The published “100+ languages” product claim and desktop Help Center language count do not establish that every locale is served by Canto. Canto's published evaluation is English; its successor is explicitly intended to broaden language coverage. — [Canto evaluation](https://wisprflow.ai/canto), [What is Wispr Flow?](https://docs.wisprflow.ai/articles/2772472373-what-is-flow)
- Public documentation does not state whether desktop audio is streamed to servers during capture or uploaded after Stop. It only documents cloud recognition and post-Stop insertion. Don't infer transport chunking from “real-time model.”

## What mechanisms improve Flow's wording and personalization?

### Takeaway
Flow combines speech recognition with a separate editing/context layer: selectable cleanup, app and field context, dictionaries, correction entries, and writing styles. The strongest transferable lesson is controlled contextual help paired with preservation/undo—not simply asking a larger model to rewrite every transcript.

### Cited Findings
- Flow says its post-processing handles fillers, punctuation, run-on thoughts and spoken self-corrections. Its Auto Cleanup selector currently exposes None, Light and Medium; completed dictations can expose Undo AI edit / Redo AI edit when both raw and formatted versions exist, and standard Cmd-Z undoes the immediate paste. — [What is Wispr Flow?](https://docs.wisprflow.ai/articles/2772472373-what-is-flow), [Auto Cleanup](https://docs.wisprflow.ai/articles/4283510616-Auto-Cleanup:-control-how-much-Flow-edits-your-dictation)
- Context Awareness on Mac/Windows uses readable active-field text to help with names and formatting. It also classifies six app categories (AI, Email, Work messaging, Personal messaging, Document, Other), with browser-site recognition; when text cannot be read, dictation continues without those cues. — [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-Context-Awareness)
- Wispr says screen context can be used to recognize proper nouns and match casing, spacing and punctuation. Password/sensitive/numeric fields and financial apps have explicit exclusions; full screenshots require a separate capture option that is off by default. — [Context Awareness privacy details](https://docs.wisprflow.ai/articles/4678293671-Context-Awareness), [Security and privacy](https://wisprflow.ai/dictation-blogs/is-wispr-flow-safe-security-and-privacy)
- Users can add preferred spellings and one literal misspelling-to-correction mapping per dictionary item. Correction matching is whole-word and case-insensitive; the saved replacement retains its intended capitalization and punctuation. — [Teach Flow your words](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)
- Wispr describes using opt-in user edits as model-training signals, attempting to distinguish actual recognition corrections from unrelated rewrites using forced-alignment confidence and edit shape. The same research write-up explicitly says the work discussed after the released Canto training description extends beyond the model's training, so this selective correction-grafting method should not be represented as already deployed in Canto 1. — [Canto correction-learning research](https://wisprflow.ai/canto)
- Wispr reports that Canto 1 was post-trained to use personal vocabulary context and that the desktop dictation edit rate fell 13% after deployment. The metric is Wispr's own production metric, not an independent trial. — [Canto 1 results](https://wisprflow.ai/canto-1-results)
- A Voice Profile is generated from qualifying desktop dictation history after word-count milestones. Its public help article describes it as an Insights report; the reviewed source does not explain whether or how its contents condition the recognizer. — [Voice Profile updates](https://docs.wisprflow.ai/articles/7470830521-voice-profile-updates-when-the-update-your-voice-profile-notification-appears)

### Inferences
- Dictator already has local counterparts for several mechanics: Apple Speech contextual strings, local vocabulary/correction rules, app-specific style profiles, spoken-correction and filler-cleanup controls, and a reversible raw transcript. These are confirmed in `Dictator/Speech/MicTranscriber.swift`, `Dictator/TextProcessing/DictationVocabularySnapper.swift`, `Dictator/TextProcessing/DictationCustomization.swift`, `Dictator/TextProcessing/DictationTone.swift`, and `Dictator/Views/Hub/StyleView.swift`.
- Safe opportunities are clearer per-transcript raw-versus-cleaned provenance, a simple Undo/Redo affordance, correction acceptance that is explicit and local, and robust tests for context being unavailable or misleading. Do not use surrounding text or screenshots without clear opt-in and sensitive-field safeguards.

### Gaps
- Wispr's public pages don't provide the full contextual-data ranking/prompt policy or a reproducible correction-adaptation algorithm for the shipped Canto 1 model. Some research is explicitly future-facing.
- It is unclear whether Voice Profile changes recognition, formatting only, or neither; its Help Center defines it as an Insights report, so assuming model adaptation would be unsupported.

## What should Dictator borrow, and how should quality be kept current?

### Takeaway
Borrow Wispr's evaluation discipline and user-visible controls, not its cloud dependency or proprietary model claims. Keep the model choice evidence-driven with Dictator-specific holdout tests for spontaneous speech, names, corrections, noisy/quiet speech, and insertion latency; version updates should be opt-in or compatibility-gated until that benchmark passes.

### Cited Findings
- Wispr says it added A/B tests and expanded real-usage benchmarks after a period where older models caused inconsistent edits and corrections. — [What's new: formatting and model consistency](https://wisprflow.ai/whats-new)
- Wispr's Canto launch study uses 10 hours of English dictations from over 2,300 opt-in speakers, with speaker-level separation between training and test sets; a separate 3-hour set targets speech with background voices, music, traffic, wind, whispering/far-field audio, and 1–2-word utterances. Wispr reports lowest WER in its model comparison on the first set and lowest among real-time systems on the challenge set; these are company-run evaluations and the model comparison details are not enough for independent reproduction. — [Canto evaluation methodology](https://wisprflow.ai/canto)
- Wispr also reports public English evaluations on LibriSpeech, FLEURS and Common Voice: it tied on LibriSpeech but did not lead FLEURS or Common Voice. — [Canto public benchmark discussion](https://wisprflow.ai/canto)
- Dictator's current source defines Apple Speech as on-device with partial text during dictation; optional Parakeet TDT 0.6B runs locally through FluidAudio/Core ML after key release; WhisperKit is offered for file transcription. — `Dictator/Speech/ParakeetDictationEngine.swift`, `Packages/DictatorParakeet/Sources/DictatorParakeet/ParakeetRecognizer.swift`, `Dictator/Speech/WhisperKitFileTranscriber.swift` (local code, not public Wispr claims).

### Inferences
- Keep an automated model-version audit (upstream release notes, model files/checksums, license changes) and run a fixed, consented, de-identified Dictator evaluation corpus whenever the runtime or checkpoint changes. Track WER plus human correction rate, proper-name accuracy, false dictionary overrides, p95 end-of-speech-to-insert latency, and exact-once insertion. Dataset updates should be versioned to prevent regressions being hidden by a changing test set.
- Treat large vendor-reported gains as hypotheses to benchmark, not as guarantees for Dictator users. Test side by side on the same audio, languages, device and post-processing rules, then ship only when improvements are reliable without breaking local-only behavior.

### Gaps
- This review did not benchmark models on Dictator's hardware or audio fixtures; no claim here establishes that Canto or another cloud model would outperform Dictator's current local recognizers for this user's languages, microphone, privacy needs, or app targets.
- The published Canto successor is not yet released, and Wispr has not given a public cadence/date for it. “More than 10× scale” is a training-development note, not a promise of a proportional accuracy improvement.
