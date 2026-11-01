# HushKey competitor landscape and product opportunities

**Reviewed:** 2026-11-01  
**Scope:** Mac voice dictation and transcription products, using their own current product pages, help centers, and source repositories. Features and availability change; this is a product scan, not hands-on testing.

## What the market already offers

| Product | Notable offer | What HushKey should learn |
| --- | --- | --- |
| [Wispr Flow](https://wisprflow.ai/?hl=en-US) | Cross-app dictation; removes fillers and spoken revisions; automatic language detection; personal dictionary, reusable snippets, writing styles, searchable history, and a meeting notetaker. Its help center says desktop transcription requires an internet connection. | The baseline is a fast shortcut, polished text, useful personalization, and a clear review/history area. HushKey can distinguish itself with an explicit offline path and its measured silent-input experiment. |
| [Superwhisper](https://ai.superwhisper.com/voice-to-text-mac) | Local/offline transcription on Apple Silicon, configurable modes, context-aware formatting, system-wide typing, file transcription, and iOS sync. | Treat a “mode” as a simple preset for language, output style, and task. Offer model choice without making setup intimidating. |
| [Aqua Voice](https://aquavoice.com/mac) | Real-time dictation, custom dictionary/instructions, and [Edit Mode](https://aquavoice.com/edit-mode) to revise selected text by voice. Its optional [Deep Context](https://aquavoice.com/deep-context) reads a screenshot at dictation start to find on-screen terms; it is off by default. The changelog also describes a “Send it” voice command. | Voice should also help fix existing text. Any app-context access should be visibly optional, narrowly scoped, and off until chosen. |
| [Typeless](https://www.typeless.com/help/quickstart/dictate) | Turns rough, reordered thoughts and self-corrections into polished writing; offers Dictate, Translate, and Ask Anything experiences, with desktop and mobile apps. | A useful “clean up what I meant” action is more valuable than raw transcription alone. Keep literal transcript available beside any rewrite. |
| [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) | Many local and cloud speech engines, live previews, batch audio/video transcription, SRT/VTT export, per-app/site/hotkey workflows, plugins, snippets, dictionary, searchable history, undo, and raw-transcript restore. Its repository is GPL-3.0. | Its feature breadth is a strong reference for workflow design. Reuse ideas, not GPL app code; keep HushKey’s license boundary and audit each new model/library license. |
| [MacWhisper](https://www.macwhisper.com/) | File and batch transcription, subtitles, speaker recognition, translation, meeting recording, watched folders, CLI/workflows, plus system-wide dictation and AI prompts. | File transcription and export are useful extensions once core dictation works; they should not crowd the first-run experience. |
| [Handy](https://github.com/cjpais/handy) | Free, open-source, offline cross-platform dictation; configurable hold/toggle shortcut; Whisper or Parakeet models and voice-activity detection. | “Local and private” alone is not a differentiator. HushKey needs a better Mac experience and a distinct reason to exist. |
| [VoiceInk](https://tryvoiceink.com/docs/introduction) | Modes and triggers for apps, websites, phrases, and shortcuts; local or provider-based engines; real-time transcription; local polish; dictionary auto-learning; context-aware enhancement; file transcription; searchable history and retry. | Offer model and privacy clarity, and make history useful for correction and recovery. Its docs distinguish local transcription from enhancement that may send text/context to a provider. |

The common expectation is now: a global shortcut; insertion at the cursor; useful correction of natural speech; vocabulary and snippets; sensible language handling; and a history users can search or recover from. Some products also add context, workflows, file transcription, and editing of selected text.

## HushKey today

The current app already has on-device Apple Speech recognition, configurable start/stop shortcuts, editable output, copy, guarded one-time insertion, local history, microphone/language controls, personal vocabulary and phrase snippets. Silent Lab remains a separate, evidence-gated experiment. It does **not** yet have downloadable speech models, AI rewriting, per-app writing styles, voice editing of selected text, file transcription, workflow automation, or undo/restore of an inserted transcript. See the [README](../README.md) and [product plan](PRODUCT_PLAN.md) for shipped behavior and limits.

## What HushKey could offer that matters

### 1. Make the existing path dependable first

Before adding features, finish the manual acceptance check already listed in `PROGRESS.md`: microphone and Speech permissions, voice and whisper capture, the global shortcut, edit/copy/insert in TextEdit and one other app, and local history. Fix any failures and make the app explain the next action when a permission, microphone, or insertion target is unavailable. This is the highest-value work because every feature depends on capture and insertion working predictably.

### 2. Build an excellent local dictation loop

- Keep a simple first-run path: choose a shortcut, confirm the mic, dictate one phrase, then edit or insert it.
- Show recording, processing, success, and failure clearly; preserve the draft after errors.
- Add **Undo last insertion** and **Restore raw transcript** so polishing never destroys the user's original words.
- Upgrade vocabulary/snippets with searchable entries, import/export, placeholders, and a clear way to undo a learned correction.

### 3. Add real local model choice

Keep Apple Speech as the zero-download option. Later, evaluate one compatible downloaded local engine (for example, a Whisper-family engine) with clear model size, language coverage, disk use, speed/quality tradeoff, and offline status. Do not promise “better accuracy” without a HushKey benchmark. Check app, runtime, and model licenses before shipping.

### 4. Add optional local polishing and voice editing

Start with deterministic cleanup for punctuation, spoken formatting, and phrase replacements. Then consider an opt-in on-device language model for “clean this up,” translate, or rewrite-selected-text actions. Show raw and revised text, let the user preview before insertion, and offer Undo. Never silently submit a message or run arbitrary system commands from dictated words.

### 5. Add small, understandable writing modes

Let a user choose **Natural**, **Message**, **Email**, or **Code** before dictation. Each mode should state what it changes. Per-app rules can come later and must be visible and user-configured. Do not inspect screenshots or app contents by default; if context is ever added, ask separately and expose a persistent status.

### 6. Expand from dictation into transcription when the core is stable

Add drag-and-drop audio/video files, a queue, editable transcripts, and text/SRT/VTT export. Keep it local by default. Meeting recording and automation are later choices, not launch requirements.

### 7. Keep the silent-mouthing experiment as HushKey’s distinctive lane

No competitor feature list removes the feasibility constraint: headphone motion is indirect, low-rate movement data, not an inward speech sensor. Keep Voice/Whisper useful on its own. For Silent Lab, start with a small user-trained vocabulary, show sample counts and holdout results, reject uncertain outputs, and report plainly when the signal does not beat baseline. This evidence-first design can be HushKey’s real differentiator; do not market it as unrestricted silent dictation.

## Recommended sequence

1. Complete and fix the voice-dictation acceptance check.
2. Add clear capture states, recovery, insertion undo, and raw-text restore.
3. Improve vocabulary/snippets and add a few explicit writing modes.
4. Evaluate a local speech-engine option and an opt-in local polishing model.
5. Add file transcription and subtitle export.
6. Continue Silent Lab research independently, with no unlock unless session-separated evaluation supports it.

Do not pursue meetings, cloud providers, cross-device sync, a plugin marketplace, or automatic screen context until the core has passed real-app acceptance. Those features add substantial surface area and do not solve HushKey’s current reliability gap.
