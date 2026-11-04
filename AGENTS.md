# Working on HushKey (Codex, Claude, and any other agent)

## One copy, one branch: `main`

- **The only working copy is `~/Projects/HushKey`.** Don't create or use other clones (for example under `~/Documents/Codex/...` or `~/Documents/ChatGPT/...`). Work found in another copy should be moved here, then that copy deleted.
- **Branch:** work on `main` and push to `main`. Everything was merged there on 2026-11-04 (ruddvz/hushkey#3, ruddvz/hushkey#4), and the old branches are deleted. Don't create long-lived feature branches.
- Before starting: `git pull --ff-only`. Commit small, focused changes and push when done, so the other agent can pull them.
- If another agent may be editing at the same time, use a git worktree on its own branch (`git worktree add ../HushKey-<task> -b <you>/<task>`) then merge it back into `main`, push, and delete the branch and worktree when done. Never use bare `git stash` (the stash list is shared).
- Record what you finished and what's next in `PROGRESS.md`.

## Build and test

```bash
xcodegen generate
xcodebuild -project HushKey.xcodeproj -scheme HushKey -derivedDataPath .build CODE_SIGNING_ALLOWED=NO test
open .build/Build/Products/Debug/HushKey.app   # use open, not the raw binary, so mic/speech permission sticks
```

Only one HushKey should run at a time; quit `dist/HushKey.app` before testing a debug build.

## Design and product rules

- UI follows the Fog & sage tokens in `docs/DESIGN_SYSTEM.md` (`Theme.swift`): sage `signal` is the only accent, and there are no hard-coded colours.
- fn (Globe) is the default dictation key (`FunctionKeyMonitor`).
- Don't copy GPL code (TypeWhisper, VoiceInk). MIT code (FreeFlow, OpenWhispr, OpenTypeless, amirrsyed/hushkey) may be adapted with attribution in `NOTICE.md`.
- Unit tests aren't proof that microphone, insertion or permissions work; say what was checked live.
