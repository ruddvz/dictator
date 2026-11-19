# Dictator personal data backup

Open **Settings → Data & privacy → Your files → Personal data backup** to export or import a versioned JSON backup.

The backup contains up to 50 recent dictations (including raw recognition when available), vocabulary, snippets, correction rules, up to 12 custom writing styles, and up to 100 Automatic app profiles. Profiles include app name and bundle identifier, mode, vocabulary, optional language/snippet/correction/cleanup overrides, and an optional writing-style reference. They contain no app text. The backup contains no microphone audio. File transcripts, meeting notes, Silent Lab templates, and research session logs are separate local data and are not included in this backup.

## Import behavior

Dictator checks the whole file before showing an import choice. It rejects unknown formats or versions, files over 10 MiB, duplicate history IDs, invalid terms, malformed rules, and oversized entries. Nothing changes until you choose **Merge backup** or **Replace local data**.

- **Merge backup** keeps current dictations with matching IDs and current personalization rules with matching cues. For writing styles, it keeps local entries with a matching ID or case- and accent-insensitive name, then adds distinct imported styles. For app profiles, it keeps the current profile for a matching bundle identifier and adds profiles for other apps. If a profile's imported style matches a local style by name, the profile is linked to that local style. If the merged styles or profiles exceed their limits, Dictator rejects the import without silently dropping entries.
- **Replace local data** uses the backup's dictations and personalization values. Version-2 backups replace custom writing styles; version-1 backups preserve local styles. Version-3 backups replace both styles and app profiles. Version-1 and version-2 backups preserve local app profiles. Dictator asks for confirmation first.
- If the current dictation archive is unreadable, Dictator tries to preserve its original bytes before an approved import replaces it.

The file is written only to the location selected in the save panel. Dictator does not upload backups or send them to a service.

## Format

Schema version 3 uses the format identifier `com.ruddvz.dictator.personal-data`. Exported files are UTF-8 JSON with `format`, `version`, `exportedAt`, `dictationHistory`, `vocabulary`, `snippets`, `correctionRules`, `writingStyles`, and `appProfiles` fields. Dictator imports version-1 and version-2 files; version 1 preserves local styles and profiles on Replace, while version 2 replaces styles and preserves local profiles. Unsupported versions are rejected rather than partially applied.
