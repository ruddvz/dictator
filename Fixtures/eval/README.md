# Dictation eval fixtures

Fixed inputs for Dictator's local dictation eval (`Scripts/eval.sh`, report in [docs/eval](../../docs/eval/report.md)).

```
Fixtures/eval/
  dev/        tune against these
    processor.json   deterministic text cases for DictationTranscriptProcessor
    audio.json       audio clips: spoken reference + per-mode checks
    polish.json      Polished-level cases: rule-cleaned input, intended polished output
    audio/           consented recordings, <clip id>.wav|m4a|caf|aiff|mp3 (optional)
  holdout/    same layout; a fair check, not a tuning target
```

## Splits

- **dev** is for iterating on the processor and recognition settings. Read individual results freely.
- **holdout** measures whether a change generalizes. While changing the processor, look only at holdout aggregates in `report.md`; per-case holdout details are only in `report.json`. Add new holdout cases before a change, never in response to a holdout failure.
- `testEvalSplitsAreDisjoint` fails if an ID, processor input, or clip reference appears twice.

## Processor cases (gated in CI)

Each case runs `DictationTranscriptProcessor.process` with its `mode`, `snippets`, `applyCorrections` (default `true`), and `cleanupFillers` (default `false`). `expected` is the **intended** output.

- A case that fails without `"knownGap": true` fails `xcodebuild test`, in either split.
- `knownGap` marks intended behavior that is not implemented yet. It is reported, not gated. When a change makes it pass, the report lists it under "Known gaps now passing"; remove the flag so it is gated from then on.
- Do not edit `expected` to match current output. Change it only when the intended behavior changes.

Categories: `code`, `line-breaks`, `corrections`, `snippets`, `fillers`.

## Polish cases (model-backed, reported)

`polish.json` holds text as it reaches the Polished pass and the `expected` result: only fillers and stutters deleted, punctuation and capitals fixed. `PolishEvalTests` gates that every `expected` passes `DictationSmartCleanup.isSafeCleanup`. With `TEST_RUNNER_DICTATOR_POLISH_MODEL=<path to a GGUF>` it also runs the local model and writes raw vs polished scores to [docs/eval/polish-report.md](../../docs/eval/polish-report.md). The few-shot examples in `DictationSmartCleanup.localExamples` must never repeat a polish input.

## Audio clips (reported, not gated)

Each clip has a `reference` (the exact words spoken), optional `snippets` / `cleanupFillers`, and `checks` keyed by mode (`Natural`, `Message`, `Email`, `Code`):

- `contains`: case-insensitive substrings the processed output must include (`"\n"` for a line break).
- `absent`: case-insensitive whole words or phrases that must not appear.

Every clip is processed in all four modes. Automatic mode resolves to one of them from the frontmost app, so it is not scored separately.

### Audio sources

1. **Recorded** (preferred): a consented recording at `audio/<clip id>.<ext>`. Commit a recording only with the speaker's approval. Read the `reference` text naturally; keep the spoken commands ("new line", "underscore") exactly as written.
2. **Synthetic** (bootstrap): if no recording exists, `Scripts/eval.sh` synthesizes the reference with the local macOS voice `Samantha` (override with `DICTATOR_EVAL_VOICE`) into `.build/eval-audio/`, which is not committed. Synthetic speech is cleaner than real dictation, so its WER is optimistic.

Do not add third-party speech datasets without first checking their license, and never download audio as part of the harness.
