// Shared fixtures for the engine tests: a temp application-support folder,
// the fakes of `package:haul/testing.dart`, small DASH / HLS /
// plain-file sources, and polling helpers. The engine runs for real against
// them — only the platform edges (plugin, network, ffmpeg) are stubbed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

const cdn = 'https://cdn.example/vid-1';

/// A DASH as a provider packages it: one 720p video, a Latin American and an
/// English audio; every link signed with [token], 4-second fragments — two
/// per track at 8 s, so 3 pieces per track with the init.
String dashManifest(String token, {int seconds = 8, String video = 'v720'}) =>
    '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT${seconds}S">
  <Period>
    <AdaptationSet contentType="video" mimeType="video/mp4">
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="$video" height="720" bandwidth="2000000" codecs="avc1.64001f"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="es-419">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="main"/>
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="a-lat" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="dub"/>
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="a-en" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
  </Period>
</MPD>''';

String dashUrl([String token = 'first']) => '$cdn/manifest.mpd?t=$token';

/// Another encode of the same title, three fragments per track: a plan of
/// it never lines up with one of [dashManifest].
String longDashUrl([String token = 'long']) =>
    '$cdn/long/manifest.mpd?t=$token';

const hlsUrl = '$cdn/master.m3u8';

const hlsMaster = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",LANGUAGE="es",NAME="Español",DEFAULT=YES,URI="audio/es.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",AUDIO="aud"
video/720.m3u8
''';

String hlsMedia(String prefix) =>
    '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:4.0,
$prefix-0.ts
#EXTINF:4.0,
$prefix-1.ts
#EXT-X-ENDLIST
''';

const fileUrl = '$cdn/movie.mp4';
const rangedUrl = '$cdn/big.mp4';
const subtitleUrl = '$cdn/es.vtt';

/// Just over one range: two ranges, the second of [rangedTail] bytes.
const rangedTail = 100;
const rangedLength = FileSource.rangeSize + rangedTail;
const etag = '"abc123"';

/// The first bytes of an MP4.
final mp4Head = [0, 0, 0, 0x18, ...ascii.encode('ftypisom')];

FetchedResponse Function(Uri) _text(String type, String Function(Uri) body) =>
    (url) => FetchedResponse(
      url: url,
      headers: {'content-type': type},
      body: utf8.encode(body(url)),
    );

FetchedResponse Function(Uri) fileResponse({
  required int length,
  bool ranges = false,
  String? etag,
}) =>
    (url) => FetchedResponse(
      url: url,
      headers: {
        'content-type': 'video/mp4',
        'content-length': '$length',
        if (ranges) 'accept-ranges': 'bytes',
        'etag': ?etag,
      },
      body: mp4Head,
    );

/// Every source the tests use, by URL without its query.
Map<String, FetchedResponse Function(Uri)> defaultRoutes() => {
  '$cdn/manifest.mpd': _text(
    'application/dash+xml',
    (url) => dashManifest(url.queryParameters['t'] ?? 'none'),
  ),
  '$cdn/long/manifest.mpd': _text(
    'application/dash+xml',
    (url) => dashManifest(url.queryParameters['t'] ?? 'none', seconds: 12),
  ),
  hlsUrl: _text('application/vnd.apple.mpegurl', (_) => hlsMaster),
  '$cdn/video/720.m3u8': _text(
    'application/vnd.apple.mpegurl',
    (_) => hlsMedia('v'),
  ),
  '$cdn/audio/es.m3u8': _text(
    'application/vnd.apple.mpegurl',
    (_) => hlsMedia('a'),
  ),
  fileUrl: fileResponse(length: 10),
  rangedUrl: fileResponse(length: rangedLength, ranges: true, etag: etag),
};

/// Spanish audio, no subtitles, at most 720p: what the fixture's account
/// asks for.
const latinCriteria = TrackCriteria(
  maxHeight: 720,
  audio: LanguageTracks(['es-419']),
  subtitles: NoTracks(),
);

const englishCriteria = TrackCriteria(
  audio: LanguageTracks(['en']),
  subtitles: NoTracks(),
);

/// A temp application-support folder, the fakes, and engines built on them.
class Env {
  Env._(this.dir) : transfer = FakeTransferClient(appSupport: dir);

  factory Env() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('offline-engine-test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return Env._(dir);
  }

  final Directory dir;
  final FakeTransferClient transfer;
  final routes = defaultRoutes();
  late final fetcher = FakeFetcher(routes);
  final ffmpeg = FakeFfmpeg();
  final logger = RecordingLogger();

  /// Built and initialised. [json] uses the engine's default store on [dir]
  /// instead of a [MemoryRecordStore].
  Future<DownloadEngine> engine({
    bool json = false,
    RecordStore? store,
    EngineConfig config = const EngineConfig(),
    SourceRefresher? refresher,
    CriteriaProvider? criteria,
    OutputSink sink = const PrivateSink(),
    FfmpegRunner? ffmpeg,
    EngineHooks hooks = const EngineHooks(),
    ValueListenable<bool>? wifiOnly,
    WifiMonitor? wifi,
    SourceFetcher? fetcher,
    bool init = true,
  }) async {
    final engine = DownloadEngine(
      appSupport: () async => dir,
      transfer: transfer,
      resolver: SourceResolver(fetcher: fetcher ?? this.fetcher),
      store: json ? null : (store ?? MemoryRecordStore()),
      ffmpeg: ffmpeg ?? this.ffmpeg,
      logger: logger,
      config: config,
      refresher: refresher,
      criteria: criteria ?? (_) async => latinCriteria,
      sink: sink,
      hooks: hooks,
      wifiOnly: wifiOnly,
      wifi: wifi,
    );
    addTearDown(engine.dispose);
    if (init) await engine.init();
    return engine;
  }

  String work(String id) => p.join(dir.path, 'haul', id);

  File planFile(String id) => File(p.join(work(id), 'plan.json'));

  DownloadPlan plan(String id) => DownloadPlan.fromJson(
    jsonDecode(planFile(id).readAsStringSync()) as Map<String, Object?>,
  );

  /// The tasks of [id] the fake still holds.
  List<DownloadTask> inFlightOf(String id) => [
    for (final task in transfer.inFlight.values)
      if (task.taskId.startsWith('ode-$id-')) task,
  ];
}

DownloadRequest request({
  String key = 'movie-1',
  String url = '',
  String title = 'La Película',
  OutputName name = const OutputName(baseName: 'La Película (2026)'),
  OutputMode output = OutputMode.package,
  TrackChoice tracks = const TrackChoice.policy(),
  DateTime? expiresAt,
  Map<String, String>? headers,
  Map<String, String>? subtitles,
  DownloadPlan? plan,
  Map<String, Object?> metadata = const {},
}) => DownloadRequest(
  key: key,
  title: title,
  name: name,
  source: SourceRequest(
    url: url.isEmpty ? dashUrl() : url,
    headers: headers,
    subtitles: subtitles,
  ),
  expiresAt: expiresAt,
  tracks: tracks,
  plan: plan,
  output: output,
  metadata: metadata,
);

/// Answers a fixed source, counts the calls, or throws [error].
class FakeRefresher implements SourceRefresher {
  FakeRefresher(this.source, {this.error, this.expiresAt, this.metadata});

  SourceRequest source;
  final Object? error;
  final DateTime? expiresAt;
  final Map<String, Object?>? metadata;
  final calls = <DownloadRecord>[];

  @override
  Future<RefreshedSource> refresh(DownloadRecord record) async {
    calls.add(record);
    final error = this.error;
    if (error != null) throw error;
    return RefreshedSource(source, expiresAt: expiresAt, metadata: metadata);
  }
}

/// Never answers: a download stays reading its source.
class SilentFetcher extends SourceFetcher {
  final requested = <Uri>[];

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) {
    requested.add(url);
    return Completer<FetchedResponse>().future;
  }
}

/// Remembers what it was asked to remove; [failures] publishes throw first.
class RecordingSink implements OutputSink {
  RecordingSink(this.inner, {this.failures = 0});

  final OutputSink inner;
  int failures;
  final published = <(String, OutputName, String)>[];
  final removed = <String>[];

  @override
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  ) async {
    if (failures > 0) {
      failures--;
      throw const FileSystemException('sink refused');
    }
    final locator = await inner.publish(staged, name, extension, record);
    published.add((locator, name, extension));
    return locator;
  }

  @override
  Future<void> remove(String locator) async {
    removed.add(locator);
    await inner.remove(locator);
  }
}

/// Polls [condition] until it holds; the engine's pipeline is a chain of
/// unawaited futures, so tests wait on observable state instead.
Future<void> waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String Function()? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'condition not met within $timeout${reason == null ? '' : ': ${reason()}'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<DownloadRecord> waitForStatus(
  DownloadEngine engine,
  String id,
  DownloadStatus status,
) async {
  await waitUntil(
    () => engine.byId(id)?.status == status,
    reason: () =>
        'status $status, is ${engine.byId(id)?.status} '
        '(${engine.byId(id)?.error})',
  );
  return engine.byId(id)!;
}

/// Completes [transfer]'s tasks as they come until [id] is done: unlike
/// `completeAll`, never gives up while the engine is slow to refill (a
/// loaded machine can take longer than its idle window).
Future<DownloadRecord> finish(
  FakeTransferClient transfer,
  DownloadEngine engine,
  String id,
) async {
  await waitUntil(() async {
    if (transfer.inFlight.isNotEmpty) {
      await transfer.complete(transfer.inFlight.values.first);
    }
    return engine.byId(id)?.status == DownloadStatus.done;
  }, reason: () => 'done, is ${engine.byId(id)?.status}');
  return engine.byId(id)!;
}

/// Lets every microtask and zero-length timer in flight settle.
Future<void> settle([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
