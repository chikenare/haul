## 0.2.0

- Every ISO 639-1 code, the withdrawn `iw`/`in`/`ji`/`mo`, and all twenty
  bibliographic ISO 639-2 codes (`mao` was missing).
- Chinese variants by script: `zh-Hant`/`zh-Hans`, from the tag, the
  country (`zh-TW` → Traditional) or the label (`繁體中文`).
- `ResolvedSource.selectionOf(plan)` and `DownloadPlan.linesUpWith(other)`:
  plan a fresh link with the same choice and reuse the pieces on disk.

## 0.1.0

- HLS, DASH and plain-file sources detected by content, track selection by
  BCP-47 language, download plans, local HLS packages and MKV arguments.
