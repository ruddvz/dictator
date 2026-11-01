# HushKey research reports

## Included reports

1. [Wispr Flow vs TypeWhisper — supplied research report (PDF)](Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf) — the original 10-page report supplied for this HushKey task. The PDF is preserved as received.
2. [HushKey competitor landscape and product opportunities](../COMPETITOR_RESEARCH.md) — HushKey's feature comparison, product gaps, license boundary, and staged implementation recommendations.

## How the findings map to HushKey

The Dictation screen implements a small local-first slice of the recommendations: Natural, Message, Email, Code, and Automatic modes; app-identifier mapping for common apps; explicit spoken correction cues with raw-transcript recovery; optional transient vocabulary hints from a bounded cursor-neighborhood; and a guarded single-step insertion undo.

These changes do not reproduce Wispr Flow or TypeWhisper wholesale. HushKey does not include TypeWhisper code, a remote AI service, LLM rewriting, selected-text editing, downloadable ASR models, file transcription, meeting recording, or workflow plugins. The local app remains usable without those features.

The supplied report describes public product pages and repository material as of 1 November 2026. It is not an installation benchmark or a test of device-specific behavior. Check current primary sources again before relying on pricing, release, or licensing details.

## License boundary

HushKey keeps its own MIT license and preserves the Subvox MIT attribution in the repository notices. The TypeWhisper source is GPLv3 and its repository requires a separate commercial license for rebranded distributions. HushKey therefore uses the reports as product research and implements its own native Swift features; it does not rename or bundle TypeWhisper code.
