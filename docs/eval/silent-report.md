# Silent Use offline eval

Generated 2026-11-02T23:26:48Z by `Scripts/silent-eval.sh`.

Silent takes: 37 (33 clean; the rest are too short, too long, or include a head turn). Sessions: 2. Words: back 7, next 10, no 11, stop 5, yes 4.

Leave-one-out accuracy, majority-class chance, and a 500-label-permutation p-value. Held-out session accuracy appears once two sessions each hold every word.

| Variant | Takes | Accuracy | Chance | p | Held-out session |
|---|---:|---:|---:|---:|---:|
| Before: no smoothing, all takes | 37 | 38 % | 30 % | 0.026 | – |
| Before, clean takes only | 33 | 33 % | 33 % | 0.142 | – |
| Now: 3-sample smoothing, all takes | 37 | 43 % | 30 % | 0.002 | – |
| Now, clean takes only | 33 | 48 % | 33 % | 0.004 | – |
| Now, clean, rotation only | 33 | 21 % | 33 % | 0.673 | – |
| Now, clean, acceleration only | 33 | 39 % | 33 % | 0.048 | – |
| Now, clean, attitude only | 33 | 36 % | 33 % | 0.078 | – |
| Now, clean, rotation + acceleration | 33 | 45 % | 33 % | 0.004 | – |
