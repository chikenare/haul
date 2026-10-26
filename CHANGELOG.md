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
- `package:haul/widgets.dart`: controller, settings, strings (en/es), theme,
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
- `HaulController` replaces `HaulScope`: each widget takes `controller:`,
  which the app keeps however it keeps its state; `ensureHaulSetup`,
  `confirmHaulDelete`, `confirmHaulFormatFile`, `pickHaulFolder` and
  `haulDestinationChoosable` take it too.
- The engine lets go of background_downloader on dispose
  (`TransferClient.unlisten`), and a retried init no longer gets every
  update twice: in a namespace the plugin chained each new callback after
  the old ones.
- haul does the work and takes values; screens, settings and permissions
  are the app's, as with background_downloader. Gone: `HaulSettings`,
  `HaulSettingsController`, `HaulSettingsStore`, the settings rows
  (`HaulFormatTile`, `HaulDestinationTile`, `HaulWifiOnlyTile`,
  `HaulBatteryTile`, `HaulBatteryBuilder`), `HaulSetupSheet`,
  `ensureHaulSetup`, `confirmHaulFormatFile`, `HaulFormatChoice`,
  `pickHaulFolder`, `haulDestinationChoosable`, the catalogue buttons
  (`HaulDownloadButton`, `HaulParentDownloadButton`, `HaulParentProgressIcon`,
  `HaulKeyBuilder`, `HaulRecordsBuilder`, `HaulProgressIcon`),
  `HaulController.settings`/`pickDirectory`/`requireSettings`,
  `HaulPermissions.enableNotifications`, and on Android picking folders
  with SAF, writing into them and the battery saver.
- `package:haul/widgets.dart` is the downloads list only: `HaulDownloadList`,
  `HaulMenuItem`, `HaulController`, `HaulTheme`, `HaulStrings`. Rows and
  menus are its own.
- `HaulDownloadList` opens a parent in place: its row shows the children
  below it, with `sectionOf`, `sort` and `sectionBuilder` for headings and
  order, and `parentMenuItems` for its menu (pause all, resume all, delete
  all). Gone: `HaulParentView`, `HaulParentActions`, `onOpenParent` and
  `parentBuilder`.
- A download's row has no button of its own: pause, resume, retry and play
  are in its menu (tapping a finished one still plays it). Under the title,
  only what it has (`1.2 GB / 3.0 GB`, no percent), its size once done, why
  it failed, or the state while there are no bytes (queued, waiting for
  Wi-Fi, preparing, finishing; paused before its bytes), and no bar while
  queued or preparing. `HaulStrings.inApp` is gone.
- A parent's menu offers pause all or resume all only when some child
  allows it (a finished series has neither), and acts on just those.
- `HaulOutputSink(folder:)`: the folder the app gives, as a path; null, the
  platform's default (MediaStore on Android, Downloads on desktop, Documents
  on iOS). Replaces `destination:`/`HaulDestination`/`HaulFolder` and
  `publicRoot:`. A folder that cannot be written falls back to the default.

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
