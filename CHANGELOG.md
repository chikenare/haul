## Unreleased

- Groups: `DownloadGroup`, `section`, `order` and `imageUrl` on requests and
  records (optional, old records read the same); `engine.entries`,
  `watchEntries`, `group`/`watchGroup`, `pauseGroup`, `resumeGroup`,
  `deleteGroup`.
- ffmpeg inside: `FfmpegKitRunner` is the engine's default; `FrameGrabber`
  for thumbnails.
- Android plugin (`HaulAndroid`): SAF folders, `content://` files, battery
  saver.
- `HaulDestination` and `HaulOutputSink` (public, app only, picked folder).
- `package:haul/widgets.dart`: scope, settings, strings (en/es), theme,
  actions and default widgets, all replaceable.
- `updateDetails` and re-enqueueing file older downloads in groups; group
  actions and `groupProgress` by section; `HaulGroupDownloadButton`,
  `HaulGroupProgressIcon`, `HaulGroupProgressBuilder`.
- Thumbnails: without `imageUrl`, a frame of the finished download
  (`ThumbnailGrabber`, `engine.imageOf`).
- ffmpeg is exported from `package:haul/ffmpeg.dart`, not `haul.dart`.
- `example/` app, with an integration test that downloads for real.

## 0.1.0

- First release of `haul`, which absorbs `media_planner` as its
  planner (`package:haul/planner.dart`).
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
  `EngineLogger`; test fakes in `package:haul/testing.dart`.
