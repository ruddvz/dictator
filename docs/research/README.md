# HushKey research reports

## Included reports

1. [Wispr Flow vs TypeWhisper — supplied research report (PDF)](Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf) — the original 10-page report supplied for this HushKey task. The PDF is preserved as received.
2. [HushKey competitor landscape and product opportunities](../COMPETITOR_RESEARCH.md) — HushKey's feature comparison, product gaps, license boundary, and staged implementation recommendations.
3. [Critique and improvement roadmap](../CRITIQUE_AND_ROADMAP.md) — critiques of Wispr Flow, TypeWhisper, and HushKey; what AirPods motion can and cannot sense; the layered quiet-input plan (gestures, speaking confirmation, whisper boost, silent commands); and measurable checks.
4. [Dictation alternatives research (1 November 2026)](../COMPETITOR_RESEARCH_ADDENDUM_2026-11-01.md) — analysis of FreeFlow, OpenWhispr, OpenTypeless, SpeakType, and the supplied roundups, with HushKey recommendations and source links.
5. [Open-source dictation landscape (4 November 2026)](OPEN_SOURCE_LANDSCAPE_2026-11-04.md) — dimastatz/whisper-flow plus 20 newer open-source apps (FluidVoice, VoiceInk, Ghost Pepper, Muesli, Pindrop, yap, Talkify…), licences, and the ranked list of gaps HushKey should build.

## How the findings map to HushKey

The Dictation screen implements a local-first slice of the recommendations: Natural, Message, Email, Code, and Automatic modes; app-identifier mapping for common apps; explicit spoken correction cues with raw-transcript recovery; optional transient vocabulary hints from a bounded cursor-neighborhood; conservative filler cleanup; and a guarded single-step insertion undo. Searchable snippets/vocabulary and transcript history with raw restore are available in their own workspace. **Transforms** provides review-first Apple on-device writing drafts and up to 12 user-created local styles when the model is available, with deterministic filler cleanup as a no-model option. **Transcribe files** supports Apple on-device Speech and user-downloaded WhisperKit models, with TXT/SRT/WebVTT export and searchable local transcript recovery; HushKey stores the transcript and timed cues, never the source audio. **Meeting notes** supports explicit microphone, system-audio, or combined capture, searchable local transcripts, text export, and optional on-device summary/action-item drafts.

These changes do not reproduce Wispr Flow or TypeWhisper wholesale. HushKey does not include TypeWhisper code, a remote AI service, voice editing of selected text, or workflow plugins. Meeting system-audio capture uses a private Core Audio tap; **Both sides** combines it with the selected microphone and requires both macOS permissions. Audio is streamed to on-device Speech and is not saved. HushKey does not identify speakers. Text transforms use Apple's Foundation Model on-device when available; Apple Speech file recognition uses the OS-provided on-device engine where supported. WhisperKit models are separate downloads initiated by the user and inference runs locally after download.

The supplied report describes public product pages and repository material as of 1 November 2026. It is not an installation benchmark or a test of device-specific behavior. Check current primary sources again before relying on pricing, release, or licensing details.

See [Local speech engines and model decision](../LOCAL_MODEL_EVALUATION.md) for the current Apple Speech/WhisperKit choice, model storage, attribution, and the benchmark still needed on the M1 Pro.

## License boundary

HushKey keeps its own MIT license and preserves the Subvox MIT attribution in the repository notices. The TypeWhisper source is GPLv3 and its repository requires a separate commercial license for rebranded distributions. HushKey therefore uses the reports as product research and implements its own native Swift features; it does not rename or bundle TypeWhisper code.
