# haul

Offline downloads of HLS, DASH and plain-file video for Flutter apps, from
the engine to the widgets. Layers in one package, each usable on its own:

- **Planner** (`package:haul/planner.dart`, pure Dart) — reads a
  source, tells HLS, DASH and plain files apart by content (never the URL),
  picks quality and tracks by BCP-47 language, and writes a `DownloadPlan`:
  every piece to fetch with its local name. It also assembles what was
  fetched: a local HLS package the player opens as is (DASH fMP4 included),
  or the inputs and arguments for an ffmpeg stream-copy into MKV.
- **Engine** (`package:haul/haul.dart`, which also
  exports the planner) — the queue on top: one `DownloadRecord` per title,
  every piece fetched through `background_downloader`, progress,
  pause/resume/retry, fresh links when one runs out, and the finished package
  or file handed to wherever the app keeps it. A download can belong to a
  parent (a show) and be listed inside it. It brings its own ffmpeg (ffmpeg-kit, minimal build)
  and its own Android side: folders picked with SAF, the public Downloads
  through MediaStore, and the battery saver.
- **Widgets** (`package:haul/widgets.dart`) — rows, buttons, a list with parents,
  the first-download sheet and settings rows, following the app's theme and
  replaceable piece by piece (see [Widgets](#widgets)).

## What each app plugs in

Nothing here knows about an app's API or account. The engine takes:

| Piece | What it answers |
| --- | --- |
| `SourceRefresher` | A fresh link (`RefreshedSource`) for a record whose link is about to expire (`expiresAt` within `EngineConfig.linkMargin`) or was refused. Throw `RefreshException(code, message)` to fail the download with the app's own code. |
| `CriteriaProvider` | The `TrackCriteria` of a `TrackChoice.policy()` download, read when its turn comes — a queued season follows the settings of that moment. |
| `OutputSink` | Where a finished file goes. `HaulOutputSink` follows a `HaulDestination` the user picks — the public Downloads (MediaStore on Android), only in the app, or a folder of theirs (SAF on Android) — read at each publish, and falls back to public and then private when a folder can no longer be written. `PrivateSink` (default) keeps it in the download's folder; `DirectorySink` moves it into a folder by path, never over another file (`Name (2).ext`). Packages always stay private. |
| `FfmpegRunner` | Runs `MkvArgs`. `FfmpegKitRunner` (`package:haul/ffmpeg.dart`) by default; pass another for another build. |
| `EngineHooks` | `onWholeFileTask`: dress the task of a file fetched in one request (a notification, which on Android keeps a long one in the foreground). |
| `wifiOnly` | A `ValueListenable<bool>`: the user's "only on Wi-Fi", followed while it changes. Null: never. |
| `WifiMonitor` | Whether the device is on Wi-Fi now, and when that changes. Tells a Wi-Fi drop from a network error, and when to go on. `ConnectivityWifiMonitor` (connectivity_plus) by default when there is `wifiOnly`. |
| `ImageFetcher` | Keeps a copy of a remote `imageUrl` in the download's folder, so it shows offline (`engine.imageOf`). `HttpImageFetcher` by default; null shows it from the network. |
| `freeSpace` | Bytes free, to fail a download that will not fit — or an export — as `noSpace` before anything is fetched or written. `HaulAndroid.freeBytes` by default; unknown checks nothing. |
| `EngineLogger` | Warnings and unexpected errors, for the app's crash reporting. `PrintLogger` by default. |

`package:haul/testing.dart` has fakes (`FakeTransferClient` and
friends) for driving the engine in tests without platform channels, network
or ffmpeg.

## How it behaves

- **The disk is the state.** A piece is done once its file exists with the
  right size, so starting, resuming, retrying and picking up after a kill are
  the same thing: asking for what is missing. Titles go through the queue one
  at a time; the pieces of one run in parallel (`EngineConfig.maxConcurrent`).
- **Pause = cancel, keep the files.** A pause cancels the pieces in flight and
  keeps what is on disk; resume asks only for what is missing. The
  downloader's own pause is not reliable on every platform.
- **Byte ranges for big files.** A plain file over 16 MB served with
  `Accept-Ranges: bytes` and a `Content-Length` is fetched in 16 MB ranges,
  with its strong ETag as `If-Range`, so a pause or a kill only loses the
  ranges in flight. Each range is checked against its size before they are
  joined: a server that ignored the range, or a file that changed in between,
  fails the download as `corrupt` instead of splicing two files.
- **iOS hands the whole queue at once; elsewhere, a window.** On iOS every
  piece is given to the system up front: it schedules best what it gets while
  the app is in front, and what starts from the background is throttled. On
  Android and desktop, `4 × maxConcurrent` pieces at a time go to the
  plugin's holding queue and are refilled as they finish — thousands of
  queued tasks are slow there and lost with the queue on a kill.
  `EngineConfig.window` overrides both.
- **Records as JSON files.** Each download is a folder under application
  support (`EngineConfig.rootFolder`) holding its `record.json`, its
  `plan.json` and its pieces, so a record and its files never disagree about
  whether it exists. Writes are atomic (temporary file + rename) and ordered
  per download; a folder whose record cannot be read is removed at the next
  start. Any `RecordStore` can replace it.
- **Fresh links reuse the pieces.** A refreshed link is planned again with the
  choice the pieces were made with (`ResolvedSource.selectionOf`), and what is
  on disk is kept only when the new plan lines up with the old one
  (`DownloadPlan.linesUpWith`: same tracks, pieces, ranges and ETag).
- **Every attempt is a run.** Task ids carry the record's run
  (`ode-<id>-<run>-<track>-<piece>`): an update of a task from an earlier
  attempt — still being cancelled after a pause, or left by a kill — never
  counts for the current one. After a kill, only the tasks of the record's
  last run are followed (paused ones resumed); the rest are cancelled.
- **Kills while publishing.** The one file is written as `output.<ext>` in
  the download's folder before it goes to the sink, so a kill or a failed
  publish after that only publishes again. A `ReservingOutputSink` (such as
  `DirectorySink`) says where the file will go before moving it, and the
  engine saves that first: a kill after the move finds the file there.
- **Only on Wi-Fi.** With `wifiOnly` on, every piece is handed over with
  `requiresWiFi`, so the platform never fetches it on mobile data, even
  while the app sleeps. Off Wi-Fi nothing starts — reading a source is
  network too — and a download in flight goes back to the queue with its
  files; `engine.waitingForWifi` says so (`watchAll` emits when it
  changes), and it goes on by itself when Wi-Fi returns. A piece failing
  off Wi-Fi is that, not an error. Changing the setting asks for the pieces
  in flight again under the new one. Without a `WifiMonitor`, a drop that
  outlasts the platform's retries fails as `network`.
- **The notification's buttons are the user's.** A piece cancelled from
  outside the engine, or a whole file paused and left paused, pauses the
  download: `resume` goes on from what is on disk. Android also pauses a
  whole file at its background time limit and runs it again a second
  later; a pause followed by `running` within
  `EngineConfig.platformPauseGrace` is that, and nothing happens.
- **A package can become a file later.** `engine.export(id, name: …)`
  merges a finished package with ffmpeg and hands it to the sink, as
  `OutputMode.file` would have; the package goes once the file is written.
  It answers null or the `DownloadError`: a failed merge leaves the package
  whole and done, a failed publish fails the download and `retry` only
  publishes again. It holds the queue while it runs, and a kill in the
  middle is finished at the next start without fetching anything.
- **Errors are codes.** `DownloadError.code` is a `DownloadErrorCode`
  (`network`, `http` with `httpStatus`, `no_space`, `mux_failed`,
  `unavailable`, `corrupt`, `publish_failed`, `unknown`) or the app's own from
  a `RefreshException`. The app localizes it.

- **Parents.** A request's `parent` (`DownloadParent(id, title, imageUrl)`)
  says what the download belongs to — a show — and that is all: there are
  no seasons or positions in the engine. `engine.entries` lists loose
  downloads and parents newest first, a parent as one row whose children
  (`childrenOf`) go by title in natural order (`S01E02` before `S01E10`).
  The list keeps its identity while only progress changes, so a list built
  on `watchEntries()` rebuilds when a download comes, goes or moves, and
  each row follows its own record. `pauseParent`, `resumeParent`,
  `deleteParent` and `parentProgress` act on all the children, or on those
  that pass `where:` (one season, read from the app's `metadata`).
  Downloads asked for before the app gave them a parent get one with
  `updateDetails(id, parent:)`, and asking again for one files it as the
  request says.
- **Pictures.** A request's `imageUrl` is what the download is shown by.
  Without one, the engine takes a frame of the finished download
  (`ThumbnailGrabber`, `FrameGrabber` by default; `thumbnails: null` turns
  it off). `engine.imageOf(record)` answers either.

### Android

haul is a plugin with an Android side (`HaulAndroid`, channel
`haul/android`): picked folders through SAF (`pickFolder`, `saveToFolder`,
with subfolders), checking and deleting `content://` files, the path behind
a URI, free space, and the battery saver. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
is not declared by the plugin — Google Play restricts it. An app that ships
outside Play adds it to its manifest and gets the system's yes/no dialog;
without it, asking opens the battery settings list.

### Known limits

- `DirectorySink` answers absolute paths as locators. On iOS the app's
  container path changes between installs (and some updates), so a locator
  saved before can stop resolving; keep files private (`PrivateSink`, whose
  `work:` locators are relative) there, or map the path again in the app.
- On desktop the downloader may copy a finished file into place rather than
  move it. A whole file of known size, and a range, are checked by size; a
  fragment (no size known up front) found on disk after a kill is trusted.

## Usage

```dart
import 'package:haul/haul.dart';

final engine = DownloadEngine(
  refresher: MyRefresher(), // implements SourceRefresher
  criteria: (record) async => const TrackCriteria(
    maxHeight: 1080,
    audio: LanguageTracks(['es-419', 'en']),
    subtitles: LanguageTracks(['es-419']),
  ),
  sink: DirectorySink(() async => downloadsFolder), // null: stays private
  ffmpeg: MyFfmpeg(), // implements FfmpegRunner
);

// At app start, not when a screen opens: it picks up what a kill left.
await engine.init();

final (:id, :outcome) = await engine.enqueue(
  DownloadRequest(
    key: 'episode:42', // the app's identity for the title
    title: 'Loki S01E01',
    name: const OutputName(
      baseName: 'Loki S01E01',
      folders: ['Loki', 'Season 01'],
    ),
    source: SourceRequest(url: signedUrl, headers: {'Referer': '…'}),
    expiresAt: DateTime.now().add(const Duration(hours: 6)),
    output: OutputMode.file, // OutputMode.package by default
  ),
);

engine.watch(id).listen((record) {
  if (record == null) return; // deleted
  print('${record.status} ${record.progress.fraction}');
  if (record.status == DownloadStatus.done) {
    // master.m3u8 or the file (a path or a content:// URI), with its
    // subtitles; null once the user deleted the file.
    engine.playable(record).then((p) => p == null ? null : play(p.locator));
  }
});

await engine.pause(id);
await engine.resume(id);
await engine.retry(id); // after a failure
await engine.delete(id); // its folder and what it published
await engine.delete(id, keepOutput: true); // off the list, the file stays
final error = await engine.export(id); // a finished package → one file
```

Around the engine, all optional:

```dart
// Progress in the notification shade, on Android (whole files keep the
// plugin's own, which runs a big one in the foreground).
final notifications = HaulNotifications(icon: 'ic_stat_download');
final engine = DownloadEngine(hooks: notifications.hooks, …);
await engine.init();
await notifications.follow(engine);

// At the first download: notifications unless allowed already, and the
// shared folders up to Android 9.
await HaulPermissions.forDownload();
```

To let the user pick the tracks first, resolve and plan with the planner and
hand both over: `DownloadRequest(…, tracks: TrackChoice.selection(selection),
plan: plan)`.

## Widgets

```dart
import 'package:haul/widgets.dart';

// In shared_preferences — or anywhere: HaulSettingsController(value, onChanged).
const store = HaulSettingsStore();
final settings = store.controller();
await store.loadInto(settings);
final engine = DownloadEngine(
  sink: HaulOutputSink(
    destination: () async => settings.value.destination,
    subfolder: 'MyApp/Videos',
  ),
  wifiOnly: settings.wifiOnly,
  …
);

// One, at start, kept however the app keeps its state (a Riverpod
// provider, a service locator…).
final haul = HaulController(
  engine: engine,
  settings: settings,
  strings: const MyStrings(), // optional; en/es built in
  canRetry: (e) => e.code != 'quota', // the app's codes a retry won't fix
  pickDirectory: myDesktopPicker, // desktop only; Android uses SAF
);

// Handed to each widget where it shows.
HaulDownloadList(controller: haul, onPlay: play);
HaulDestinationTile(controller: haul);
```

- **Default widgets**: `HaulDownloadList` (parents as one row,
  `onOpenParent`), `HaulParentView` for a parent's children — headings and
  order are the app's, from each child's `metadata`: `sectionOf: (r) =>
  'Season ${r.metadata['season']}'`, `sort:` — and `HaulParentActions`;
  `HaulParentDownloadButton(parentId, where:, onDownload:)` for a show or a
  season (download what is missing, pause all, resume all) with
  `HaulParentProgressIcon` / `HaulParentProgressBuilder`;
  `HaulDownloadTile`, `HaulDownloadButton(downloadKey, onDownload)`,
  `HaulProgressIcon`, `HaulActionsMenu`, `HaulThumbnail`;
  `ensureHaulSetup(context, haul)` before the first download; `HaulFormatTile`
  (`confirm: true` asks before one file), `HaulDestinationTile`,
  `HaulWifiOnlyTile`, `HaulBatteryTile` for a settings page.
- **The app's own actions**: `menuItems: (context, record) => [HaulMenuItem(
  icon:, label:, onSelected:)]` on `HaulDownloadTile`, `HaulDownloadList`
  and `HaulParentView` (and `HaulParentActions` for a parent) — after
  haul's actions, before the ones that remove.
- **Replacing parts**: every row takes builders (`itemBuilder`,
  `parentBuilder`, `sectionBuilder`, `leading`, `title`, `subtitle`,
  `trailing`, `builder` on the buttons).
- **Texts**: extend `HaulStrings` (or `HaulStringsEs`) and override what
  differs — `error(DownloadError)` for the app's own codes,
  `sourceError(e)` for why a source could not be read.
- **Look**: `ThemeData.extensions: [HaulTheme(...)]`; colours and text come
  from the app's `ColorScheme` and `TextTheme` otherwise.
- **Drawing one's own**: `HaulRecordBuilder` / `HaulKeyBuilder` /
  `HaulRecordsBuilder` / `HaulChildrenBuilder` follow records; `DownloadActions.of(record)` says what
  can be done and `runHaulAction` does it; `downloadSummary` writes the state
  line; `engine.playable(record)` is what a player opens.

`example/` is an app with public test streams (HLS, DASH, a ranged MP4, a
"show" as a parent with two seasons) that uses all of it.

### The planner alone

```dart
import 'package:haul/planner.dart';

final source = await const SourceResolver().resolve(
  SourceRequest(url: manifestUrl),
);
final plan = await source.plan(source.selectionFor(criteria));

// Fetch every plan.tracks[t].pieces[i] — sending its rangeHeader, if any —
// into <work>/t<t>/<piece.file>, then:
if (LocalPackager.supports(plan)) {
  final package = await const LocalPackager().package(plan, workDir);
  // package.masterPath plays as is.
} else {
  final inputs = [
    for (final (t, track) in plan.tracks.indexed)
      await const TrackAssembler().assemble(
        track,
        Directory('${workDir.path}/t$t'),
      ),
  ];
  // plan.needsMux: run MkvArgs.build(inputs: inputs, outputPath: …) with
  // ffmpeg; otherwise inputs.single.path already is the file.
}
```

**Languages.** BCP-47 everywhere (`es-419`, `pt-BR`, `zh-Hant`). Every
ISO 639-1 code maps to the ISO 639-2/T form Matroska tags with; any Spanish of
the Americas counts as `es-419`, and Chinese is told apart by script. A track
with no language tag is read from its label (`Español (Latino)`).

## Development

Generated files (`*.g.dart`, `*.freezed.dart`) are committed: git
dependencies do not run `build_runner`.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format lib test
flutter analyze --fatal-infos
flutter test
```
