# HushKey personal data backup

Open **Settings → Data & privacy → Your files → Personal data backup** to export or import a versioned JSON backup.

The backup contains up to 50 recent dictations (including raw recognition when available), vocabulary, snippets, correction rules, and up to 12 custom writing styles. It contains no microphone audio. File transcripts, meeting notes, Silent Lab templates, and research session logs are separate local data and are not included in this backup.

## Import behavior

HushKey checks the whole file before showing an import choice. It rejects unknown formats or versions, files over 10 MiB, duplicate history IDs, invalid terms, malformed rules, and oversized entries. Nothing changes until you choose **Merge backup** or **Replace local data**.

- **Merge backup** keeps current dictations with matching IDs and current personalization rules with matching cues. For writing styles, it keeps local entries with a matching ID or case- and accent-insensitive name, then adds distinct imported styles. It adds missing dictations, terms, snippets, and corrections, then applies the normal 50-dictation limit. If the merged styles would exceed the 12-style limit, HushKey rejects the import without silently dropping styles.
- **Replace local data** uses the backup's dictations and personalization values. Version-2 backups replace custom writing styles too. Since version-1 backups did not contain styles, importing one preserves the styles already on this Mac. HushKey asks for confirmation first.
- If the current dictation archive is unreadable, HushKey tries to preserve its original bytes before an approved import replaces it.

The file is written only to the location selected in the save panel. HushKey does not upload backups or send them to a service.

## Format

Schema version 2 uses the format identifier `com.ruddvz.hushkey.personal-data`. Exported files are UTF-8 JSON with `format`, `version`, `exportedAt`, `dictationHistory`, `vocabulary`, `snippets`, `correctionRules`, and `writingStyles` fields. HushKey can still import version-1 files; their missing `writingStyles` field is treated as an empty list, with local styles preserved on Replace. Unsupported versions are rejected rather than partially applied.
