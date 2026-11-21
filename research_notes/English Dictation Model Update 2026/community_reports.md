# Community reports on English Parakeet models

## What Mac and open-source users report

### Takeaway
Community experience favors Parakeet for fast local English dictation, but user anecdotes favor v2 for English while v3 mainly buys language coverage. Recent discussion of Parakeet Unified describes better streaming responsiveness, with a reported end-of-utterance truncation/workaround; this is useful UX evidence, not a controlled quality result.

### Cited Findings
- A July 2026 Reddit discussion asks specifically about English accuracy and disfluencies; two commenters recommend v2 for English, saying v3 loses some English accuracy, while one user reports v3 sometimes rendered accented English in another script. These are individual reports without controlled audio or quantified WER. [r/LocalLLaMA: Parakeet TDT v2 vs v3](https://www.reddit.com/r/LocalLLaMA/comments/1sbs9mk/parakeet_tdt_v2_vs_v3/)
- A Reddit post about MacParakeet says it runs Parakeet v3 through FluidAudio, and its developer reports near-instant dictation after first model load and daily use. The author calls it best with English but provides no published corpus, transcripts, or measured error rate in the post. [r/MacOSApps: MacParakeet](https://www.reddit.com/r/MacOSApps/comments/1rtxz6b/macparakeet-local-alternative-to-wisprflow-using/)
- In a second MacParakeet thread, a commenter says they use Hex with Parakeet v3 on an M1 MacBook and like the speed. Another commenter distinguishes stream responsiveness from final accuracy and points out that many open dictation tools wait until silence. [r/LocalLLaMA: MacParakeet open-source app](https://www.reddit.com/r/LocalLLaMA/comments/1s3x30d/macparakeet-free-opensource-wisprflow-alternative/)
- An August 2026 post about Handy recommends Parakeet v2 for English, v3 for multilingual use, and describes Parakeet Unified as a newer streaming option that begins displaying text after about two seconds. Its author reports “stranded” final words when the utterance ends without enough context, with the informal workaround of saying “end of dictation”; this is a small anecdotal post, not a systematic bug study. [r/StrategicProductivity: A Handy Parakeet Update](https://www.reddit.com/r/StrategicProductivity/comments/1w1v0bs/a_handy_parakeet_update/)
- A July 2026 Reddit benchmark post links its full methodology and raw transcripts. The author discloses that they build the app used in the evaluation. With identical LibriSpeech clips, scorer, production-code paths, and an M2 Pro, they report v2 int8 Core ML at 2.01% / 3.40% WER (test-clean / test-other) versus v3 at 2.51% / 4.28%. It is a real, reproducible community benchmark for v2 vs v3, but does not test Ultra or Unified. [Reddit post](https://www.reddit.com/r/MacOS/comments/1v3himu/turns_out_the_speech_engine_built_into_macos-26-basically-ties-the-best-downloadable-ai-models/), [methodology and raw data](https://lyonesse.app/blog/parakeet-moss-apple-speech-benchmark.html)
- An independent-for-this-repo but vendor-authored Typd report tested 955 public English clips on an M3 Pro on Nov 17, 2026: Ultra 3.05% WER and 2.61% on babble audio, versus v3 3.63% / 5.22%. It also says Cohere Transcribe scored 2.28% on the same clip set and Qwen3-ASR and Granite Speech outperformed Ultra, but the listed comparison is Typd's own engine results and does not establish that those are drop-in, local, streaming macOS choices. [Typd's method and results](https://gettypd.app/blog/parakeet-ultra/)

### Inferences
- User reviews support v2 as a mature English baseline and v3 as a fast local option with multilingual coverage, but popularity and reports of “good” accuracy cannot establish a model winner.
- The July same-harness benchmark is strong evidence that simply moving from v2 to v3 can reduce English accuracy. It says nothing directly about whether Ultra has closed or reversed that gap versus v2.
- Unified's potential advantage is incremental visible text and lower wait after stopping, which may improve perceived responsiveness. The single report about the final words is a reason to test final-window behavior, not enough to reject Unified.

### Gaps
- I found no community benchmark comparing v2, v3, Ultra, and Unified on one identical English corpus, same Mac, same decoder/runtime, and same scoring.
- Community dictation reports do not establish performance on the user's microphone, accent, vocabulary, noise, or desired insertion path.

## What current benchmarks say about the newer FluidAudio choices

### Takeaway
Ultra is a measurable improvement over v3, but community and upstream evidence does not prove it is better than v2. FluidAudio's English Parakeet Unified is a separate newer batch/streaming architecture with promising results; because published tables use different aggregates across model families, choosing Ultra or Unified as the most accurate requires a direct equal-protocol comparison.

### Cited Findings
- FluidAudio's current benchmark guide still explicitly says “Use v2 if you only need English, it is a bit more accurate.” Its displayed v2 result is 2.1% average WER on LibriSpeech test-clean. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- In a same-session M5 Pro ANE table that reports **corpus-level** WER, FluidAudio lists v3 at 2.27%/4.12%, Ultra at 2.13%/3.81%, and Phonon-2 at 2.47%/4.62% for test-clean/test-other. The guide calls Ultra the most accurate of these three and Phonon-2 the fastest. These figures compare v3-family derivatives, not v2. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Phonon-2 details](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/Phonon2.md)
- FluidAudio describes Ultra as a post-trained v3 derivative, with the same architecture, tokenizer, 25-language contract, and output behavior; its docs list macOS 14+ and about 630 MB for the model directory. It is not a new NVIDIA Parakeet generation or an English-only checkpoint. [Parakeet Ultra documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md)
- FluidAudio's English Parakeet Unified supports both batch and streaming. Its M5 Pro test-clean benchmark reports 2.15% mean per-file WER / 1.68% aggregate WER for batch, and 2.21% / 1.79% for streaming; text includes punctuation and capitalization. The documentation says Unified batch beats TDT v3 on its comparable mean-WER/throughput test and recommends streaming for live audio. Do not compare its aggregate numbers directly with the v3/Ultra corpus-level values above. [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md), [Unified model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- FluidAudio's English-only Phonon-2 is a newer quantization-aware v3 derivative. In the same M5 Pro table it is faster than v3/Ultra but has higher WER; the docs explicitly recommend v3/Ultra if the user wants the last accuracy margin. It is therefore not the best current choice when transcription accuracy is the priority. [Phonon-2 documentation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/Phonon2.md)
- The latest FluidAudio release checked on Nov 21 is v0.18.4, released Nov 19. Its headline updates are Nemotron streaming hardware support and general ASR reliability improvements; the release notes do not announce a new Parakeet TDT v4. [FluidAudio v0.18.4 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.18.4)
- FluidAudio has recently accepted/fixed Unified reliability work: issue #704 about streaming timing exposure and latency was closed with implementation work; v0.18.4 also reports runtime reliability work elsewhere. This indicates active maintenance but does not quantify end-to-end Dictator reliability. [FluidAudio issue #704](https://github.com/FluidInference/FluidAudio/issues/704), [v0.18.4 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.18.4)

### Inferences
- If accuracy alone is the decision rule and the app must ship immediately without a fresh test, v2 currently has the strongest directly comparable shipped-Core-ML community result for English. Its age does not make it inherently obsolete, but it conflicts with the user's preference for the newest model.
- If the decision rule is “newest model with evidence of accuracy gain over its predecessor,” Ultra is the strongest supported choice: it improves on v3, stays near its speed, and avoids the demonstrably less accurate Phonon-2 trade-off. The gain over v2 remains unknown.
- If “dictation” includes visible text while speaking, Unified deserves a focused candidate test because it is English-focused and streaming. Its model/API is separate from TDT v2/v3/Ultra, and adopting it would require changing Dictator's streaming pipeline, not merely swapping the enum.
- “Latest runtime” and “latest/highest-accuracy weights” are different: FluidAudio 0.18.4 is current software, while v2 remains the community benchmark leader against v3 on English-only held-out read speech.

### Gaps
- The most important missing evidence is a single same-device comparison of Dictator's pipeline using v2, Ultra, and Unified on a consented set of the user's natural English dictation (including sentence fragments, names, Indian English, noise, short phrases, and code terms), measuring WER, final-word loss, stop-to-text latency, and peak memory.
- No source found proves one model is best for all English speech or that any model will fix app-level focus, microphone capture, or exact text insertion.

## Recommendation for a one-model app

### Takeaway
Use a one-model installation and decide the single model by the user's priority. Current evidence does **not** justify describing Ultra as proven better than v2; it does make Ultra the newer, accuracy-improved choice over v3. For the most complete live English dictation experience, first benchmark Unified against Ultra and v2 in Dictator's actual pipeline, then keep only the winner's weights in the product.

### Cited Findings
- Ultra's ~630 MB package is downloaded only on demand through FluidAudio; v3 and Phonon-2 require their own model directories, so exposing all three stores duplicates several hundred megabytes. [Parakeet Ultra docs](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ParakeetUltra.md), [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- A Reddit community practitioner recommends v2 for English and the newer Unified for streaming, while describing an end-of-speech issue; this underlines separate accuracy and UX testing. [Handy Parakeet report](https://www.reddit.com/r/StrategicProductivity/comments/1w1v0bs/a_handy_parakeet_update/)

### Inferences
- Do not include v2, v3, Ultra, and Unified as simultaneously downloadable choices. Select one after a fixed-corpus bake-off, keep weights out of the application bundle, and delete only Dictator-owned old model directories after ensuring no process is using them.
- If the user chooses newest supported weights over proven v2 accuracy before such a bake-off, use Ultra as the one model and label accuracy claims conservatively. If the user insists on the strongest existing direct English result, use v2. If the user wants best live transcription interaction, prototype Unified and compare it head-to-head.

### Gaps
- No candidate can be called “perfect” or best on this user's real speech without running the same-device test and then checking live microphone plus insertion behavior.
