## 0.1.0

- First release of `offline_engine`, which absorbs `media_planner` as its
  planner (`package:offline_engine/planner.dart`).
- Planner: HLS, DASH and plain-file sources detected by content, track
  selection by BCP-47 language, download plans, local HLS packages and MKV
  arguments; re-planning a fresh link with the same choice
  (`selectionOf`, `linesUpWith`).
- Planner: big plain files (over 16 MB, with `Accept-Ranges: bytes`) are
  planned as 16 MB byte ranges validated with the strong ETag (`If-Range`),
  checked by size and joined at assembly.
- Engine: `DownloadEngine` — queue, pieces through `background_downloader`
  (whole queue on iOS, a window elsewhere), pause as cancel-and-keep, fresh
  links through `SourceRefresher`, local package or one file through an
  `OutputSink`, records as one atomic `record.json` per download folder.
- Extension points: `SourceRefresher`, `CriteriaProvider`, `OutputSink`
  (`PrivateSink`, `DirectorySink`), `FfmpegRunner`, `EngineHooks`,
  `EngineLogger`; test fakes in `package:offline_engine/testing.dart`.
