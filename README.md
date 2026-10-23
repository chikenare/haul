# media_downloader

Shared download core for the Flutter apps that save HLS, DASH and direct files
for offline playback.

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

What it does **not** do: queueing, fetching the pieces, persistence or running
ffmpeg — those stay in each app.

Generated files (`*.g.dart`, `*.freezed.dart`) are committed: git dependencies
do not run `build_runner`.

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart analyze && dart test
```
