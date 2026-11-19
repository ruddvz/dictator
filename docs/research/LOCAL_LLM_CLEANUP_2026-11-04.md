# Local LLM cleanup before macOS 26 (2026-11-04)

Gap 2 in [OPEN_SOURCE_LANDSCAPE_2026-11-04.md](OPEN_SOURCE_LANDSCAPE_2026-11-04.md): make the Style page's **Polished** level work without Apple Intelligence (macOS 14–15, or 26+ with it off).

## Licences checked

| Piece | Licence | Used how |
|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) b11900 (incl. ggml) | MIT, © 2023-2026 The ggml authors | Linked: the official prebuilt `llama-b11900-xcframework.zip`, pinned by SHA-256 in `Packages/DictatorLlama`. Licence text in `docs/licenses/LLAMA-CPP-MIT-LICENSE.txt`, shipped in the app's Resources. |
| [LLM.swift](https://github.com/eastriverlee/LLM.swift) | MIT, © 2023 eastriver | **Not used.** It needs swift-syntax for its macros and swift-testing pinned to `main`, which is a lot of build for ~150 lines of calls. Dictator's `LlamaRunner` is written from llama.h directly. |
| [matthartman/ghost-pepper](https://github.com/matthartman/ghost-pepper) | README badge says MIT, but the repository has **no LICENSE file** (GitHub reports no licence) | Idea only: a small local GGUF model for cleanup. No code or prompt copied. |
| [SmolLM2 360M Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct) (Hugging Face) | Apache-2.0 | The model. The Q4_K_M GGUF by [bartowski](https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF) (Apache-2.0) is downloaded only when the user picks **Download**, pinned to commit `7be6f65` and checked by size and SHA-256. Not bundled or modified. |
| Qwen3 0.6B, Qwen3.5 0.8B (Alibaba Qwen; GGUFs by Unsloth) | Apache-2.0 | Evaluated, not shipped. |

## Model choice

All four candidates ran through `PolishEvalTests` (llama.cpp b11900, greedy, Metal, this Mac) on `Fixtures/eval/*/polish.json`, with the short local prompt and six worked examples in `DictationSmartCleanup.localExamples` (none overlap the fixtures). Raw text scores 8/16 dev and 4/10 holdout words-match, 13.3% and 20.0% WER.

| Model (Q4_K_M) | Size | Dev words / exact / WER / rejected | Holdout words / exact / WER / rejected | Holdout median |
|---|---|---|---|---|
| SmolLM2 135M | 105 MB | 12 / 8 / 6.7% / 7 | 8 / 5 / 4.0% / 3 | 0.09 s |
| **SmolLM2 360M** | **271 MB** | **13 / 10 / 3.8% / 4** | **10 / 8 / 0.0% / 1** | **0.15 s** |
| Qwen3 0.6B (thinking off) | 397 MB | 13 / 8 / 4.8% / 2 | 7 / 5 / 8.0% / 1 | 0.20 s |
| Qwen3.5 0.8B | 533 MB | 11 / 5 / 8.6% / 2 | 6 / 3 / 14.0% / 2 | 0.25 s |

SmolLM2 360M is the smallest model that does the job. Its mistakes are answering a question ("The capital of France is Paris.") or following an instruction ("write a poem…"); `isSafeCleanup` rejects those, so the rule-cleaned text is typed instead and nothing is reworded. With Apple's long instructions and no examples, every model just echoed the input, so the local model gets its own prompt.

## How it fits

- `DictationSmartCleanup.engine`: Apple Intelligence first; the local model only when Apple's isn't available and the model is downloaded.
- `prepare()` loads the model while you talk; `clean()` waits at most `min(4, 1.5 + chars/200)` s, including load, then falls back to the rule text.
- The model is freed after 10 minutes idle and at quit (ggml's Metal backend asserts if a model is still loaded at exit).
- `-localCleanupOnly YES` at launch forces the local model on a Mac with Apple Intelligence, for testing.
