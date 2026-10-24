# offline_engine

Offline downloads of HLS, DASH and plain-file video for Flutter apps. Two
layers in one package:

- **Planner** (`package:offline_engine/planner.dart`, pure Dart) — reads a
  source, tells HLS, DASH and plain files apart by content (never the URL),
  picks quality and tracks by BCP-47 language, and writes a `DownloadPlan`:
  every piece to fetch with its local name. It also assembles what was
  fetched: a local HLS package the player opens as is (DASH fMP4 included),
  or the inputs and arguments for an ffmpeg stream-copy into MKV.
- **Engine** (`package:offline_engine/offline_engine.dart`, which also
  exports the planner) — the queue on top: one `DownloadRecord` per title,
  every piece fetched through `background_downloader`, progress,
  pause/resume/retry, fresh links when one runs out, and the finished package
  or file handed to wherever the app keeps it.

## What each app plugs in

Nothing here knows about an app's API, account or ffmpeg build. The engine
takes:

| Piece | What it answers |
| --- | --- |
| `SourceRefresher` | A fresh link (`RefreshedSource`) for a record whose link is about to expire (`expiresAt` within `EngineConfig.linkMargin`) or was refused. Throw `RefreshException(code, message)` to fail the download with the app's own code. |
| `CriteriaProvider` | The `TrackCriteria` of a `TrackChoice.policy()` download, read when its turn comes — a queued season follows the settings of that moment. |
| `OutputSink` | Where a finished file goes. `PrivateSink` (default) keeps it in the download's folder; `DirectorySink` moves it into a user folder under `OutputName.folders`, never over another file (`Name (2).ext`). Packages always stay private. |
| `FfmpegRunner` | Runs `MkvArgs` with the app's own ffmpeg. Only needed when a download becomes one file from several tracks. |
| `EngineHooks` | `onWholeFileTask`: dress the task of a file fetched in one request (a notification, which on Android keeps a long one in the foreground). |
| `EngineLogger` | Warnings and unexpected errors, for the app's crash reporting. `PrintLogger` by default. |

`package:offline_engine/testing.dart` has fakes (`FakeTransferClient` and
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
- **Errors are codes.** `DownloadError.code` is a `DownloadErrorCode`
  (`network`, `http` with `httpStatus`, `no_space`, `mux_failed`,
  `unavailable`, `corrupt`, `publish_failed`, `unknown`) or the app's own from
  a `RefreshException`. The app localizes it.

## Usage

```dart
import 'package:offline_engine/offline_engine.dart';

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
    play(engine.outputPath(record)!); // master.m3u8 or the file
  }
});

await engine.pause(id);
await engine.resume(id);
await engine.retry(id); // after a failure
await engine.delete(id); // its folder and what it published
```

To let the user pick the tracks first, resolve and plan with the planner and
hand both over: `DownloadRequest(…, tracks: TrackChoice.selection(selection),
plan: plan)`.

### The planner alone

```dart
import 'package:offline_engine/planner.dart';

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
