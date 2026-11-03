# Silent Use offline eval

Generated 2026-11-03T18:55:56Z by `Scripts/silent-eval.sh`.

Silent takes: 37 (32 clean; the rest are too short, too long, or include a head turn). Sessions: 2. Words: back 7, next 10, no 11, stop 5, yes 4.

Leave-one-out accuracy, majority-class chance, and a 300-label-permutation p-value. Held-out session accuracy appears once two sessions each hold every word.

| Variant | Takes | Accuracy | Chance | p | Held-out session |
|---|---:|---:|---:|---:|---:|
| Before: no smoothing, all takes | 37 | 38 % | 30 % | 0.030 | – |
| Before, clean takes only | 32 | 41 % | 34 % | 0.023 | – |
| Now: 3-sample smoothing, all takes | 37 | 43 % | 30 % | 0.007 | – |
| Now, clean takes only | 32 | 53 % | 34 % | 0.003 | – |
| Now, clean, rotation only | 32 | 25 % | 34 % | 0.495 | – |
| Now, clean, acceleration only | 32 | 41 % | 34 % | 0.023 | – |
| Now, clean, attitude only | 32 | 41 % | 34 % | 0.020 | – |
| Now, clean, rotation + acceleration | 32 | 47 % | 34 % | 0.013 | – |
| Drift removed (0.3 Hz), clean, all features | 32 | 38 % | 34 % | 0.053 | – |
| Drift removed (0.5 Hz), clean, all features | 32 | 31 % | 34 % | 0.203 | – |
| Head band removed (1.5 Hz), clean, rotation + acceleration | 32 | 38 % | 34 % | 0.053 | – |
