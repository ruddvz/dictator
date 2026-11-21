# Dictator competitor landscape and product opportunities

**Reviewed:** 2026-11-01  
**Scope:** Mac voice dictation and transcription products, using current product pages, help centers, and source repositories, plus a read-only accessibility-tree inspection of Wispr Flow v1.6.1337 installed on this Mac. This is not a speech-quality benchmark or a full screenshot-backed usability audit. Features and availability change.

## What the market already offers

| Product | Notable offer | What Dictator should learn |
| --- | --- | --- |
| [Wispr Flow](https://wisprflow.ai/?hl=en-US) | Cross-app dictation; removes fillers and spoken revisions; automatic language detection; personal dictionary, reusable snippets, writing styles, searchable history, and a meeting notetaker. Its help center says desktop transcription requires an internet connection. | The baseline is a fast shortcut, polished text, useful personalization, and a clear review/history area. Dictator can distinguish itself with an explicit offline path and its measured silent-input experiment. |
| [Superwhisper](https://ai.superwhisper.com/voice-to-text-mac) | Local/offline transcription on Apple Silicon, configurable modes, context-aware formatting, system-wide typing, file transcription, and iOS sync. | Treat a “mode” as a simple preset for language, output style, and task. Offer model choice without making setup intimidating. |
| [Aqua Voice](https://aquavoice.com/mac) | Real-time dictation, custom dictionary/instructions, and [Edit Mode](https://aquavoice.com/edit-mode) to revise selected text by voice. Its optional [Deep Context](https://aquavoice.com/deep-context) reads a screenshot at dictation start to find on-screen terms; it is off by default. The changelog also describes a “Send it” voice command. | Voice should also help fix existing text. Any app-context access should be visibly optional, narrowly scoped, and off until chosen. |
| [Typeless](https://www.typeless.com/help/quickstart/dictate) | Turns rough, reordered thoughts and self-corrections into polished writing; offers Dictate, Translate, and Ask Anything experiences, with desktop and mobile apps. | A useful “clean up what I meant” action is more valuable than raw transcription alone. Keep literal transcript available beside any rewrite. |
| [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) | Many local and cloud speech engines, live previews, batch audio/video transcription, SRT/VTT export, per-app/site/hotkey workflows, plugins, snippets, dictionary, searchable history, undo, and raw-transcript restore. Its repository is GPL-3.0. | Its feature breadth is a strong reference for workflow design. Reuse ideas, not GPL app code; keep Dictator’s license boundary and audit each new model/library license. |
| [MacWhisper](https://www.macwhisper.com/) | File and batch transcription, subtitles, speaker recognition, translation, meeting recording, watched folders, CLI/workflows, plus system-wide dictation and AI prompts. | File transcription and export are useful extensions once core dictation works; they should not crowd the first-run experience. |
| [Handy](https://github.com/cjpais/handy) | Free, open-source, offline cross-platform dictation; configurable hold/toggle shortcut; Whisper or Parakeet models and voice-activity detection. | “Local and private” alone is not a differentiator. Dictator needs a better Mac experience and a distinct reason to exist. |
| [VoiceInk](https://tryvoiceink.com/docs/introduction) | Modes and triggers for apps, websites, phrases, and shortcuts; local or provider-based engines; real-time transcription; local polish; dictionary auto-learning; context-aware enhancement; file transcription; searchable history and retry. | Offer model and privacy clarity, and make history useful for correction and recovery. Its docs distinguish local transcription from enhancement that may send text/context to a provider. |

The common expectation is now: a global shortcut; insertion at the cursor; useful correction of natural speech; vocabulary and snippets; sensible language handling; and a history users can search or recover from. Some products also add context, workflows, file transcription, and editing of selected text.

## Dictator today

The current app has on-device Apple Speech recognition, configurable start/stop shortcuts, editable output, copy, guarded one-time insertion, local history, microphone/language controls, personal vocabulary and phrase snippets. The Dictation screen adds Natural, Message, Email, Code, and Automatic modes; app-identifier mapping; explicit spoken correction cues with raw-transcript restore; optional transient nearby-text hints; guarded one-step insertion undo; conservative optional filler cleanup; and snippet validation. Automatic app profiles can override writing mode, vocabulary, on-device language, snippets, corrections, filler cleanup and an optional Transform style; explicit modes use the global preferences. Version-3 personal backups include these profiles. **Transforms** offers review-first built-in drafts, up to 12 user-defined local writing styles, and deterministic filler cleanup on older supported macOS versions. Model-backed changes use Apple's on-device Foundation Model (macOS 26+ when available); styles are stored locally and remain drafts until reviewed. **Transcribe files** offers Apple on-device Speech or an explicitly downloaded WhisperKit model, editable TXT output, and SRT/WebVTT export. **Meeting notes** supports explicit microphone or system-audio capture, searchable local transcripts, editing/export/deletion, and optional on-device summaries/action items; it does not save audio or identify speakers. System-audio capture uses a private Core Audio tap and is subject to macOS 14.2+ System Audio Recording permission. Silent Lab remains a separate, evidence-gated experiment. Remaining gaps include workflow/plugin automation. Manual microphone/system-audio permission, meeting, second-app insertion, local model, and subtitle-alignment acceptance remains open; see the [testing protocol](TESTING_PROTOCOL.md), [local model evaluation](LOCAL_MODEL_EVALUATION.md), [README](../README.md), and [product plan](PRODUCT_PLAN.md).

## Installed Wispr Flow interface spot check

On 2026-11-01, the installed macOS app identified itself as v1.6.1337. A read-only accessibility-tree inspection exposed these product areas: Dictation/history, Notetaker, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad, and Settings. The Notetaker setup presented a guided tour, calendar connection, past-meeting import, and MCP setup; its notes area had Past notes, Shared with me, and Folders. Dictionary and snippets had search and add flows. Style separated personal, work, email, other, and Auto Cleanup; cleanup offered None, Light, and Medium and described restoring the original dictation. Transforms were opt-in, shortcut-driven, could run automatically after dictation, and included custom transforms. Settings grouped shortcut, microphone, languages, and data/privacy controls.

**What this means for Dictator:** the native sidebar and Dictation screen provide a clear start action, shortcut, on-device status, editable transcript, copy/insert, and local history. The **Snippets & Vocabulary** workspace makes personalization searchable; history searches saved entries and can restore processed or raw recognition; **Transforms** creates editable on-device drafts with explicit apply and undo. **Meeting notes** starts only on an explicit action, offers microphone or system-output capture, keeps transcripts local, and provides reviewable summaries and action items. System-output capture requires a separate macOS permission and still needs real call acceptance on the target Mac. Keep Dictator's own visual identity and local-first behavior rather than copying Flow branding or proprietary implementation.

This spot check did not start dictation or meeting capture, change a privacy setting, connect a calendar, or inspect any account data for the report. A valid Wispr screenshot could not be captured: the desktop capture showed Dictator in front of Wispr Flow, and the native UI pipe later closed when switching back to Dictator. Findings above are limited to the accessibility tree; they do not establish visual polish, feature behavior, or speech accuracy.

## App reconnaissance tools and limits

- The official [REA repository](https://github.com/morluto/rea) was used in read-only desktop-bundle inventory mode against `/Applications/Wispr Flow.app`. REA 6.8.0 examined 1,605 directory entries, probed 94 files, and read 16,396 bytes. It found an Electron `app.asar` packaging marker; that is a packaging candidate, not proof of which code is loaded at runtime. The scan did not inspect or extract the ASAR, decompile native code, or access user transcripts or account data. The local Evidence bundle is temporary and is not part of this repository.
- [ServiceNow/StarHarness](https://github.com/ServiceNow/StarHarness) is an MIT-licensed framework for evolving AI-agent prompts, tools, and loops against search, selection, and holdout task splits. It requires an external model endpoint and runs proposer-generated code with local user permissions. It does not inspect desktop-app UI or dictate audio, so it was reviewed but not run or added to Dictator. Its useful evaluation lesson is to keep acceptance examples separate from development examples and report a held-out result.
- These tools supplement the visible-interface inspection; they do not justify copying Wispr Flow's proprietary source, assets, or implementation. Dictator should implement equivalent user-facing workflows with its own native interface and local-first behavior.

## What Dictator could offer that matters

### 1. Make the existing path dependable first

Before adding features, finish the manual acceptance check already listed in `PROGRESS.md`: microphone and Speech permissions, voice and whisper capture, the global shortcut, edit/copy/insert in TextEdit and one other app, and local history. Fix any failures and make the app explain the next action when a permission, microphone, or insertion target is unavailable. This is the highest-value work because every feature depends on capture and insertion working predictably.

### 2. Build an excellent local dictation loop

- Keep a simple first-run path: choose a shortcut, confirm the mic, dictate one phrase, then edit or insert it.
- Show recording, processing, success, and failure clearly; preserve the draft after errors.
- Add **Undo last insertion** and **Restore raw transcript** so polishing never destroys the user's original words.
- Searchable vocabulary/snippets and raw-transcript recovery are implemented. Next, add import/export and placeholders after validating the current dictation and insertion flows.

### 3. Add real local model choice

Keep Apple Speech as the zero-download option. Later, evaluate one compatible downloaded local engine (for example, a Whisper-family engine) with clear model size, language coverage, disk use, speed/quality tradeoff, and offline status. Do not promise “better accuracy” without a Dictator benchmark. Check app, runtime, and model licenses before shipping.

### 4. Add optional local polishing and voice editing

The preview-first transform workspace now offers polish, concise, professional, bullets, action items, and deterministic filler removal using the on-device Apple Foundation Model when available. Generated results remain drafts until the user applies them, and the prior transcript can be restored. The next step is voice-driven selected-text editing, with explicit selection/focus checks and recovery before any replacement. Never silently submit a message or run arbitrary system commands from dictated words.

### 5. Add small, understandable writing modes

Let a user choose **Natural**, **Message**, **Email**, or **Code** before dictation. Each mode should state what it changes. Per-app rules can come later and must be visible and user-configured. Do not inspect screenshots or app contents by default; if context is ever added, ask separately and expose a persistent status.

### 6. Expand from dictation into transcription when the core is stable

The single-file Apple Speech and WhisperKit paths now exist. Meeting notes supports microphone, system-audio, or combined local capture, with searchable transcripts, export, and on-device generated notes. Next, finish manual acceptance of dictation, files, and all meeting sources. Combined capture requires both macOS audio permissions and remains unverified on live devices; keep captured audio transient by default.

### 7. Keep the silent-mouthing experiment as Dictator’s distinctive lane

No competitor feature list removes the feasibility constraint: headphone motion is indirect, low-rate movement data, not an inward speech sensor. Keep Voice/Whisper useful on its own. For Silent Lab, start with a small user-trained vocabulary, show sample counts and holdout results, reject uncertain outputs, and report plainly when the signal does not beat baseline. This evidence-first design can be Dictator’s real differentiator; do not market it as unrestricted silent dictation.

## Recommended sequence

1. Complete and fix the manual voice acceptance check, including actual app focus, Accessibility insertion and undo in TextEdit and a second app.
2. Compare Apple Speech with each downloadable WhisperKit model on consented sample audio on the target M1 Pro; record speed, memory, accuracy, and subtitle alignment before recommending a default.
3. Consider preview-first selected-text editing only if it can remain local and safely recover the original text.
4. Finish manual acceptance of microphone, system-audio, and combined Meeting Notes capture, including just-in-time permission, remote-call playback, and confirmation that audio is not persisted.
5. Continue Silent Lab research independently, with no unlock unless session-separated evaluation supports it.

Do not add cloud providers, cross-device sync, a plugin marketplace, or automatic screen context. They add substantial privacy and maintenance costs without improving Dictator's local-first path.

## Supplied Wispr Flow vs TypeWhisper report

The full dated source report is included at [docs/research/Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf](research/Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01.pdf). Its product and licensing claims are a point-in-time public-source scan; the installed-app spot check above is separate and limited to the visible accessibility tree. The [report index](research/README.md) separates the original report from Dictator's implementation notes.

## HeyClicky for Mac — checked 2026-11-20

HeyClicky is a third-party Mac app, not a macOS feature. Its current product combines push-to-talk dictation with on-demand screen understanding, spoken/typed chat, visual pointers, and agents that can act on the computer. Its changelog describes held-key streaming, a hands-free shortcut, correction learning, automatic language detection, and a screen-aware writing command that captures the screen only after the user asks. Its privacy page says screenshots are not retained, while text summaries can persist as context. See the [Mac product page](https://www.heyclicky.com/for-mac), [official changelog](https://www.heyclicky.com/changelog), and [terms](https://www.heyclicky.com/terms).

Dictator already offers on-device live dictation, app profiles, correction learning, and optional nearby-name hints read from the focused text field. The field context is opt-in, limited to supported non-password controls, used transiently, and not saved. This is the part of HeyClicky's context-aware workflow that fits Dictator's local-first boundary; whole-screen capture would need a separate Screen Recording permission and explicit control surface before it could be added safely. Visual pointer guidance and computer-use agents also need their own consent, action review, and safety model, so they remain outside dictation insertion.

The public [Clicky repository](https://github.com/farzaa/clicky) is MIT-licensed and documents the earlier open-source app; its maintainers state the current HeyClicky product is developed privately. No code or assets were copied. This research informed Dictator's current-context and recovery UX, while the app keeps its own implementation and visual identity.

### Official feature update — 2026-11-20

The current HeyClicky Mac changelog lists version 1.1.5 (Nov 16) as newest. It adds 18 UI languages, new plans and billing controls with paid usage resets; adapts the notch to the latest MacBook Pro camera island; animates reply text out of the typing indicator with smooth chat scrolling; keeps drawings in chat; retries transient agent outages; and improves the “your turn” handoff. Version 1.1.3 (Nov 6) added persistent answer-style preferences, screen re-checks to avoid repeating completed steps, approved agent file uploads, recurring jobs, stop/steer controls, and captions that continue while chat is closed. The broader Mac experience includes hold-to-talk streaming, double-tap hands-free dictation, 50+ auto-detected speech languages, correction learning from quick transcript edits, and explicit screen-aware drafting. [Official changelog](https://www.heyclicky.com/changelog)

The strongest direct Dictator improvements are interruption-safe transcript recovery, tested exact-once insertion in Electron/browser apps, clipboard/keyboard-layout/CJK/terminal safeguards, and smoother transcript rendering that preserves caret and scroll position. This follow-up implements a reversible local correction-learning offer: for a single distinctive word change, Dictator previews the recognized and corrected words, saves only after explicit action, and provides dismiss and undo. The prior review copied no HeyClicky code or assets. Screen capture and cloud context, persistent conversational memory, connected apps, routines, visual click/draw controls, and autonomous agents remain separate products that need distinct consent, data retention, safety, and recovery designs before consideration. HeyClicky's own policy says screenshots are not kept on its servers (providers may retain them briefly for processing/safety), but text memory and task context persist; it disabled proactive agents and associated local activity tracking after user privacy concerns. [Privacy policy](https://www.heyclicky.com/privacy-policy), [changelog](https://www.heyclicky.com/changelog), [terms](https://www.heyclicky.com/terms)

Detailed findings and source notes: [HeyClicky research](research/competitors/heyclicky.md).
