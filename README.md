# media_planner

Plans downloads of HLS, DASH and direct files for offline playback — it does
not fetch anything itself.

- **Sources** — `SourceResolver` tells HLS, DASH and plain files apart by
  content (not URL), parses the manifest and exposes its qualities, audios and
  subtitles.
- **Selection** — `ResolvedSource.selectionFor(TrackCriteria)` picks the video
  under a height and the tracks closest to the wanted BCP-47 languages
  (`es-419` beats any Spanish; every American Spanish counts as `es-419`).
- **Plan** — `DownloadPlan`: every piece to fetch (init, fragment, key, file)
  with its local name, serialisable to `plan.json`.
- **Assembly** — `LocalPackager` writes a local HLS package (DASH fMP4 included,
  via `EXT-X-MAP`) the player opens directly; `TrackAssembler` +
  `MkvArgs.build` prepare an ffmpeg stream-copy into MKV.

## Usage

```dart
import 'package:media_planner/media_planner.dart';

// 1. What is it? Decided by the content, never the URL.
final source = await const SourceResolver().resolve(
  SourceRequest(url: manifestUrl, headers: {'Referer': '…'}),
);

// 2. Pick quality and tracks — from the user's settings, or show a sheet
//    when `source.needsChoice(criteria)` says the audio is ambiguous.
const criteria = TrackCriteria(
  maxHeight: 1080,
  audio: LanguageTracks(['es-419', 'en-US']),
  subtitles: LanguageTracks(['es-419']),
);
final plan = await source.plan(source.selectionFor(criteria));

// 3. Fetch every `plan.tracks[t].pieces[i]` into `<work>/t<t>/<piece.file>`
//    with your own downloader, and keep `plan.toJson()` beside them.

// 4a. Keep it as a local HLS package the player opens…
if (LocalPackager.supports(plan)) {
  final package = await const LocalPackager().package(plan, workDir);
  play(package.masterPath, subtitles: await LocalPackager.subtitlesOf(package.masterPath));
}

// 4b. …or merge it into one file with your ffmpeg.
final inputs = [
  for (final (t, track) in plan.tracks.indexed)
    await const TrackAssembler().assemble(track, Directory('${workDir.path}/t$t')),
];
await runFfmpeg(MkvArgs.build(inputs: inputs, outputPath: 'Movie.${plan.extension}'));
```

**A link that expires mid-download.** Resolve the fresh link and plan it
with the choice the pieces were made with, not today's settings:

```dart
final selection = fresh.selectionOf(oldPlan);
final newPlan = selection == null ? null : await fresh.plan(selection);
if (newPlan != null && newPlan.linesUpWith(oldPlan)) {
  // Same files under the same names: fetch only what is missing.
}
```

**Languages.** BCP-47 everywhere (`es-419`, `pt-BR`, `zh-Hant`). Every
ISO 639-1 code maps to the ISO 639-2/T form Matroska tags with (checked
against the Library of Congress list); any Spanish of the Americas counts as
`es-419`, and Chinese is told apart by script (`zh-TW` writes `zh-Hant`).
A track with no language tag is read from its label (`Español (Latino)`).

What it does **not** do: queueing, fetching the pieces, persistence or running
ffmpeg — those stay in each app.

Generated files (`*.g.dart`, `*.freezed.dart`) are committed: git dependencies
do not run `build_runner`.

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze && dart test
```
