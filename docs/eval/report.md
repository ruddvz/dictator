# Dictator dictation eval

Generated 2026-11-02T23:37:09Z on macOS 27.0.1 by `Scripts/eval.sh`. Machine-readable results: [report.json](report.json).

Tune against **dev**. Treat **holdout** as a fair check: read only its aggregate numbers while changing the processor.

## Processor checks (deterministic, gated in CI)

| Split | Passed | Known gaps | Regressions | Known gaps now passing |
|---|---|---|---|---|
| dev | 20/25 | 5 | 0 | 0 |
| holdout | 12/18 | 6 | 0 | 0 |

| Category | dev | holdout |
|---|---|---|
| code | 5/8 | 2/6 |
| line-breaks | 3/4 | 3/4 |
| corrections | 6/6 | 3/4 |
| snippets | 3/3 | 2/2 |
| fillers | 3/4 | 2/2 |

Dev failures:

- `code-underscore-dot` (Code) known gap: expected `user_id = user.id`, got `user_id = user. id`
- `code-call-no-space` (Code) known gap: expected `print(name)`, got `print (name)`
- `code-quoted-string` (Code) known gap: expected `"hello"`, got `" hello "`
- `message-punctuated-command` (Message) known gap: expected `Thanks.⏎Bye.`, got `Thanks.⏎. Bye.`
- `filler-basic` (Natural) known gap: expected `Could you send it?`, got `could you send it?`

## Audio pipeline (reported, not gated)

WER compares raw recognition with the spoken reference (case and punctuation ignored; line breaks and code symbols the recognizer inserted itself count as their spoken words). Format TER compares a mode's processed output with the processor applied to the reference, over the clips that target that mode. Checks are per-mode `contains`/`absent` assertions from the fixtures.

### apple-speech (en-US, on-device)

| Split | Clips | Sources | WER | Real-time factor | Clip errors |
|---|---|---|---|---|---|
| dev | 8 | 8 synthetic | 9.0% | 0.06× | 0 |
| holdout | 6 | 6 synthetic | 7.8% | 0.06× | 0 |

| Mode | dev checks | dev format TER | holdout checks | holdout format TER |
|---|---|---|---|---|
| Natural | 10/13 | 17.0% | 4/6 | 10.0% |
| Message | 2/2 | 28.6% | 2/2 | 0.0% |
| Email | 2/2 | 0.0% | 4/4 | 0.0% |
| Code | 4/4 | 12.5% | 2/4 | 75.0% |

Dev clips:

| Clip | WER | Recognized | Failed checks |
|---|---|---|---|
| `d01-plain` | 10.0% | Can you send a quarterly report to Priya before Friday? | — |
| `d02-code-tokens` | 10.0% | Let's user_ID equals (value) | — |
| `d03-message-line` | 25.0% | Hey team⏎The builders green | Natural: missing "new line" |
| `d04-email-paragraph` | 0.0% | Hi Sam,⏎⏎Thanks for the update | — |
| `d05-correction` | 0.0% | Send it to Alice actually Bob | Natural: contains "Alice"; Natural: contains "actually" |
| `d06-snippet` | 0.0% | Please reply to my email address | — |
| `d07-fillers` | 22.2% | Oh, I think we should ship it today | — |
| `d08-plain-names` | 0.0% | Please schedule a review with the design team next week | — |

### parakeet-v2 (on-device)

| Split | Clips | Sources | WER | Real-time factor | Clip errors |
|---|---|---|---|---|---|
| dev | 8 | 8 synthetic | 0.0% | 0.03× | 0 |
| holdout | 6 | 6 synthetic | 11.8% | 0.02× | 0 |

| Mode | dev checks | dev format TER | holdout checks | holdout format TER |
|---|---|---|---|---|
| Natural | 13/13 | 0.0% | 6/6 | 0.0% |
| Message | 2/2 | 0.0% | 1/2 | 33.3% |
| Email | 2/2 | 0.0% | 4/4 | 18.2% |
| Code | 4/4 | 0.0% | 2/4 | 50.0% |

Dev clips:

| Clip | WER | Recognized | Failed checks |
|---|---|---|---|
| `d01-plain` | 0.0% | Can you send the quarterly report to Priya before Friday | — |
| `d02-code-tokens` | 0.0% | Let user underscore id equals open parenthesis value close parenthesis | — |
| `d03-message-line` | 0.0% | Hey team new line the build is green | — |
| `d04-email-paragraph` | 0.0% | Hi Sam new paragraph thanks for the update | — |
| `d05-correction` | 0.0% | Send it to Alice, actually, Bob | — |
| `d06-snippet` | 0.0% | Please reply to my email address | — |
| `d07-fillers` | 0.0% | Um I think we should uh ship it today | — |
| `d08-plain-names` | 0.0% | Please schedule a review with the design team next week | — |

### whisperkit

Skipped: No WhisperKit model is downloaded in Dictator. Download one in Transcribe Files to include it; the harness never downloads models.

## Comparisons (paired bootstrap, 2000 resamples)

Clips are paired by id. Δ is candidate WER minus baseline WER; negative is better. A gain counts only when the whole 95% interval is below zero.

| Comparison | Split | Clips | Baseline WER | Candidate WER | Δ | 95% interval | p | Verdict |
|---|---|---|---|---|---|---|---|---|
| parakeet-v2 (on-device) vs apple-speech (en-US, on-device) | dev | 8 | 9.0% | 0.0% | -9.0 pts | -15.3 pts to -3.0 pts | 0.005 | candidate better |
| parakeet-v2 (on-device) vs apple-speech (en-US, on-device) | holdout | 6 | 7.8% | 11.8% | +3.9 pts | -4.1 pts to +12.1 pts | 0.860 | no clear difference |
| apple-speech (en-US, on-device): this run vs previous report | dev | 8 | 9.0% | 9.0% | +0.0 pts | +0.0 pts to +0.0 pts | 1.000 | no clear difference |
| apple-speech (en-US, on-device): this run vs previous report | holdout | 6 | 7.8% | 7.8% | +0.0 pts | +0.0 pts to +0.0 pts | 1.000 | no clear difference |
| parakeet-v2 (on-device): this run vs previous report | dev | 8 | 0.0% | 0.0% | +0.0 pts | +0.0 pts to +0.0 pts | 1.000 | no clear difference |
| parakeet-v2 (on-device): this run vs previous report | holdout | 6 | 11.8% | 11.8% | +0.0 pts | +0.0 pts to +0.0 pts | 1.000 | no clear difference |

