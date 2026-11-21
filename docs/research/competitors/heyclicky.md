# HeyClicky Mac feature scan

## Current HeyClicky Mac product

### Takeaway
HeyClicky is a cloud-connected Mac assistant that combines push-to-talk dictation with screen understanding, conversational help, visual annotations, and task-running agents. Its dictation ideas are relevant to Dictator; its computer-control and connected-service features require a broader privacy and safety design.

### Cited Findings
- The Mac app supports a held shortcut for spoken help/dictation and the vendor describes the assistant as able to see the screen only after the user invokes the hotkey. It can answer about the visible app, teach workflows, draw pointers, and run tasks. [Mac product page](https://www.heyclicky.com/for-mac)
- The current product describes microphone, Screen Recording, and Accessibility permissions for listening, screen viewing, and keyboard/mouse use. Keyboard/mouse task actions require user approval per the Terms. [Mac product page](https://www.heyclicky.com/for-mac); [Terms](https://www.heyclicky.com/terms)
- The vendor says it does not store screenshots on its servers, though AI providers may retain them briefly for processing/safety. It does retain text summaries/memory; its privacy policy says task, connected-app, agent-result, account, device, and usage information are processed. [Privacy policy](https://www.heyclicky.com/privacy-policy)
- The vendor says its assistant can use OpenAI, Anthropic, Google, Cerebras, Groq, and Deepgram; connected apps use Composio. This is a substantially different online-service boundary from Dictator's local-first approach. [Privacy policy](https://www.heyclicky.com/privacy-policy)
- Its agents can work in Chrome through an extension that reads page content/structure/screenshots, clicks and types, and can upload files with approval. Stopping an agent prevents new actions but does not undo completed ones. [Privacy policy](https://www.heyclicky.com/privacy-policy)

### Inferences
- The most transferable principles are explicit activation, visible state, fast feedback, language-aware dictation, correction learning, and resilient insertion/recovery.
- Screen capture, persistent remote memory, connected-app access, and computer-use agents are separate products/features, not safe defaults for a local dictation app.

### Gaps
- Vendor statements about retention and model training are self-reported and were not independently audited.
- The public materials do not provide a reproducible benchmark for speech accuracy or the claimed dictation latency.

## Latest releases and notable dictation changes

### Takeaway
The latest Mac changelog entry found is 1.1.5, dated November 16, 2026. Recent work shows a pattern of polishing the notch/chat interaction, improving agent reliability, and addressing real-world dictation edge cases—not just adding headline features.

### Cited Findings
- In Mac 1.1.5 (Nov 16), the UI became available in 18 languages; the notch adapts to the new MacBook Pro camera island; reply typing dots expand into response lines while chat scrolls smoothly; generated drawings remain in chat; agent errors retry with clearer handoff/page-opening behavior; and new plan, billing, and usage-reset controls were added. [Changelog](https://www.heyclicky.com/changelog)
- In Mac 1.1.3 (Nov 6), HeyClicky added persistent answer preferences, screen re-checks to avoid repeating completed steps, agent file uploads with approval, recurring jobs, the ability to stop/steer active agents, and captions that continue after the chat closes. [Changelog](https://www.heyclicky.com/changelog)
- Earlier Mac dictation features include hold-to-talk streaming (the vendor reports about 450 ms), double-tap hands-free mode, automatic detection across 50+ speech languages, and automatic addition of a word to the personal dictionary when a transcript edit is made within roughly 20 seconds. [Changelog](https://www.heyclicky.com/changelog)
- Its screen-aware writing command captures a screenshot after an explicit request and drafts a reply from the visible context. [Changelog](https://www.heyclicky.com/changelog)
- Dictation reliability changes include preserving long transcripts and work across calls/microphone changes; fixing direct insertion in Chromium and Electron apps; respecting keyboard layouts; safe clipboard restoration; avoiding clipboard-manager archival; removing unwanted trailing spaces for CJK text; and collapsing newlines when dictating into terminals. [Changelog](https://www.heyclicky.com/changelog)
- A prior release reduced Home's idle CPU use and moved sound playback off the main thread after reported high idle CPU/freeze issues. [Changelog](https://www.heyclicky.com/changelog)
- HeyClicky disabled proactive agents and deleted their local activity-tracking data after users expressed privacy concerns. [Changelog](https://www.heyclicky.com/changelog)

### Inferences
- Dictator's best direct improvements to evaluate are correction-to-vocabulary learning with user control, robust interruption recovery, exact-once insertion across Electron/browser fields, clipboard hygiene, language-aware spacing, and lower-cost transcript/UI updates.
- The smooth text reveal and saved drawings are interaction ideas; Dictator can adopt a restrained transcript reveal and polished state transitions without imitating HeyClicky's notch, character art, or cloud chat.
- The shutdown of proactive agents is evidence to avoid background app/screen monitoring as a default.

### Gaps
- The changelog's 450 ms latency and accuracy descriptions are vendor claims; there is no independently documented test method or public corpus result in the cited materials.
- No technical architecture is published for the insertion fallback, correction-learning data model, or agent execution sandbox.

## Dictator fit and implementation boundary

### Takeaway
The initial Dictator review did not port HeyClicky features. A follow-up implementation now adds a deliberately narrow local correction-learning offer; other latest HeyClicky features remain proposals rather than implemented behavior.

### Cited Findings
- Dictator's existing competitor note says focused-field hints are opt-in, limited to supported non-password controls, transient, and not saved; it explicitly excludes whole-screen capture, visual pointers, and agents pending separate permission/safety design. [Dictator competitor notes](https://github.com/ruddvz/dictator/blob/main/docs/COMPETITOR_RESEARCH.md)
- The Dictator progress record says the HeyClicky review clarified Speech Recognition permission and the privacy scope of nearby hints; it states that no HeyClicky code or assets were copied. [Dictator progress](https://github.com/ruddvz/dictator/blob/main/PROGRESS.md)
- Dictator's local code contains focused-field nearby-context extraction and custom correction/vocabulary processing; this is not the same as HeyClicky's specific auto-learn-from-edit-within-20-seconds behavior. [TextInsertionService.swift](https://github.com/ruddvz/dictator/blob/main/Dictator/Services/TextInsertionService.swift); [DictationCustomization.swift](https://github.com/ruddvz/dictator/blob/main/Dictator/TextProcessing/DictationCustomization.swift)
- Follow-up implementation: if a user edits a transcript by changing exactly one distinctive word, Dictator offers the recognized/corrected pair. Only **Add word** saves the corrected word to the local vocabulary; dismiss and undo are available. Multi-word edits and common words are excluded. This differs from HeyClicky's short-window automatic dictionary learning and has a unit test for the conservative matching rules. [AppModel.swift](https://github.com/ruddvz/dictator/blob/main/Dictator/App/AppModel.swift); [DictationView.swift](https://github.com/ruddvz/dictator/blob/main/Dictator/Views/Hub/DictationView.swift)

### Inferences
- The conservative explicit correction-learning candidate is now implemented; adding a per-language dictionary and durable per-suggestion disable preference remain separate follow-ups. Do not silently learn arbitrary edits.
- Candidate for reliability work: interruption-safe partial transcripts, visible recovery states, app-specific insertion verification/fallbacks, clipboard restoration, and keyboard-layout/CJK/terminal safety.
- Candidate for UI polish: low-motion, accessibility-aware progressive transcript rendering and smooth scroll that never moves the caret or loses the user's scroll position.
- Defer screen-aware drafting until a distinct Screen Recording consent, per-request capture preview, redaction/exclusion, retention controls, and clear cloud-routing disclosures exist. Defer agents, routines, connected apps, and visual clicking until explicit task confirmation, action review, stop/recovery, and safety boundaries exist.
- Do not copy HeyClicky's visual identity, text, code, or assets.

### Gaps
- A separate project audit must verify which candidate improvements already exist or are incomplete before implementation, and live-device acceptance is needed for microphone, caret insertion, interruption recovery, motion/scroll, and permission flows.
