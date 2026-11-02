# HushKey personal data backup

Open **Settings → Data & privacy → Your files → Personal data backup** to export or import a versioned JSON backup.

The backup contains recent dictations (including raw recognition when available), vocabulary, snippets, and correction rules. It contains no microphone audio. File transcripts, meeting notes, Silent Lab templates, and research session logs are separate local data and are not included in this backup.

## Import behavior

HushKey checks the whole file before showing an import choice. It rejects unknown formats or versions, files over 10 MiB, duplicate history IDs, invalid terms, malformed rules, and oversized entries. Nothing changes until you choose **Merge backup** or **Replace local data**.

- **Merge backup** keeps current dictations with matching IDs and current personalization rules with matching cues. It adds missing dictations, terms, snippets, and corrections, then applies the normal 50-dictation limit.
- **Replace local data** uses the backup's dictations and personalization values. HushKey asks for confirmation first.
- If the current dictation archive is unreadable, HushKey tries to preserve its original bytes before an approved import replaces it.

The file is written only to the location selected in the save panel. HushKey does not upload backups or send them to a service.

## Format

Schema version 1 uses the format identifier `com.ruddvz.hushkey.personal-data`. Exported files are UTF-8 JSON with `format`, `version`, `exportedAt`, `dictationHistory`, `vocabulary`, `snippets`, and `correctionRules` fields. Future versions may add fields or require a newer HushKey release; unsupported versions are rejected rather than partially applied.
