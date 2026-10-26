## Unreleased

- Parents: `DownloadParent` and `imageUrl` on requests and records
  (optional, old records read the same); `engine.entries`, `watchEntries`,
  `parent`/`watchParent`, `childrenOf`/`watchChildren`, `pauseParent`,
  `resumeParent`, `deleteParent`, `parentProgress` (all with `where:`).
- ffmpeg inside: `FfmpegKitRunner` is the engine's default; `FrameGrabber`
  for thumbnails.
- Android plugin (`HaulAndroid`): SAF folders, `content://` files, battery
  saver.
- `HaulDestination` and `HaulOutputSink` (public, app only, picked folder).
- `package:haul/widgets.dart`: scope, settings, strings (en/es), theme,
  actions and default widgets, all replaceable.
- `updateDetails` and re-enqueueing give older downloads a parent;
  `HaulParentView` (headings and order from the app), `HaulParentTile`,
  `HaulParentActions`, `HaulParentDownloadButton`, `HaulParentProgressIcon`,
  `HaulParentProgressBuilder`, `HaulChildrenBuilder`.
- Thumbnails: without `imageUrl`, a frame of the finished download
  (`ThumbnailGrabber`, `engine.imageOf`).
- ffmpeg is exported from `package:haul/ffmpeg.dart`, not `haul.dart`.
- `example/` app, with an integration test that downloads for real.
- Pictures: a remote `imageUrl` is kept in the download's folder and shown
  from there offline (`ImageFetcher`, `HttpImageFetcher`; `images: null`
  turns it off); a new picture replaces the copy.
- Space: a download that will not fit fails as `noSpace` before fetching,
  and so does an export (`freeSpace`, `HaulAndroid.freeBytes` by default).
- `engine.playable(record, needsPath:)` → `PlayableDownload` (locator and
  subtitles; null once the file is gone). Replaces `playableLocator`.
- Menus: `HaulMenuItem` and `menuItems` on `HaulActionsMenu`,
  `HaulDownloadTile`, `HaulDownloadList`, `HaulParentView` and
  `HaulParentActions`. Exporting from the menu says how it went.
- `HaulFormatTile(confirm:)` and `confirmHaulFormatFile`.
- `HaulStrings.sourceError`, `exported`, `freeSpace` and the format
  confirmation texts.
- `HaulNotifications` (flutter_local_notifications): progress of downloads
  in pieces, failures, and `hooks` for whole files' tasks;
  `HaulNotificationTexts.forLocale`.
- `ConnectivityWifiMonitor` (connectivity_plus), the default with
  `wifiOnly`.
- `HaulPermissions` (notifications, shared storage up to Android 9) and
  `HaulAndroid.openNotificationSettings`.
- `HaulSettingsStore` (shared_preferences), optional.

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
