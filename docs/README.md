# Dictator documentation

The root [README](../README.md) is the product overview and first-run guide. This index gathers the deeper project material by task.

## Using Dictator

- [Personal data and backups](PERSONAL_DATA_BACKUP.md) — where Dictator stores transcripts and how to back them up or clear them.
- [Testing protocol](TESTING_PROTOCOL.md) — checks for dictation, permissions, insertion, files, and meeting capture.

## Understanding the project

- [Product plan](PRODUCT_PLAN.md) — current product scope and direction.
- [Design system](DESIGN_SYSTEM.md) — interface tokens, components, and visual behavior.
- [Local model evaluation](LOCAL_MODEL_EVALUATION.md) — speech model choices, licenses, and evaluation notes.
- [Documentation and research](research/README.md) — competitor analysis, model research, audits, and source material.
- [Third-party notices](../NOTICE.md) — licenses and attribution for bundled or adapted dependencies.

## Repository layout

| Path | Contents |
| --- | --- |
| `Dictator/` | Native macOS app source, grouped by feature and system service. |
| `Packages/` | Local speech-recognition and text-cleanup integrations. |
| `DictatorTests/` | Unit and integration tests. |
| `Fixtures/eval/` | Evaluation inputs and scoring guidance. |
| `Scripts/` | Xcode project generation, local signing, packaging, and developer utilities. |
| `docs/assets/` | README artwork and product screenshots. |
| `docs/research/` | Public product, competitor, and model research. |
