import 'dart:convert';
import 'dart:io';

import 'package:haul/src/planner/assembly/mux_input.dart';
import 'package:haul/src/planner/assembly/segment_playlist.dart';
import 'package:haul/src/planner/assembly/track_assembler.dart';
import 'package:haul/src/planner/plan.dart';
import 'package:path/path.dart' as p;

/// A download saved without merging, ready to play.
class LocalPackage {
  const LocalPackage({
    required this.masterPath,
    required this.video,
    required this.bytes,
  });

  /// The local HLS the player opens.
  final String masterPath;

  /// The video track, for grabbing a thumbnail.
  final MuxInput video;

  /// What it takes on disk.
  final int bytes;
}

/// A subtitle of the package. They live outside the HLS and are attached on
/// opening: their times then count from the start of the video, as in the
/// MKV, without depending on the transport stream's clock.
class PackagedSubtitle {
  const PackagedSubtitle({
    required this.path,
    this.label,
    this.language,
    this.forced = false,
  });

  final String path;
  final String? label;
  final String? language;
  final bool forced;
}

/// Saves a download without merging: the pieces stay as they were fetched
/// and a local HLS is written beside them (a master and one media playlist
/// per track) that the player opens like any other. No ffmpeg, no copy, and
/// not the double space merging needs.
///
/// Works the same for HLS (its playlists already point at the pieces) and
/// for MP4 DASH (its fragments fit an HLS with `EXT-X-MAP`). What is lost is
/// the file: the package lives in the app's private folder, and to have it
/// as one it is merged afterwards.
class LocalPackager {
  const LocalPackager([this._assembler = const TrackAssembler()]);

  final TrackAssembler _assembler;

  static const _master = 'master.m3u8';
  static const _media = 'index.m3u8';
  static const _subtitles = 'subtitles.json';
  static const _audioGroup = 'audio';

  /// Whether [plan] can be saved this way: a fragmented video and, in DASH,
  /// MP4 with every fragment's duration (WebM does not fit in an HLS). A
  /// plain file gains nothing: it already is one.
  static bool supports(DownloadPlan plan) {
    final media = plan.tracks.where((t) => t.kind != TrackKind.subtitle);
    return media.any(
          (t) =>
              t.kind == TrackKind.video &&
              (t.assembly == TrackAssembly.hlsPlaylist ||
                  t.assembly == TrackAssembly.concat),
        ) &&
        media.every(_playable);
  }

  static bool _playable(PlannedTrack track) => switch (track.assembly) {
    TrackAssembly.hlsPlaylist => true,
    TrackAssembly.concat || TrackAssembly.single => track.hasSegmentPlaylist,
    TrackAssembly.vttSegments || TrackAssembly.ranges => false,
  };

  /// Writes the playlists into [dir], the download's work folder, with the
  /// tracks in `t<n>/`.
  Future<LocalPackage> package(DownloadPlan plan, Directory dir) async {
    MuxInput? video;
    final audios = <(String, PlannedTrack)>[];
    final subtitles = <PackagedSubtitle>[];
    var seconds = 0.0;

    for (final (t, track) in plan.tracks.indexed) {
      final trackDir = Directory(p.join(dir.path, 't$t'));
      if (track.kind == TrackKind.subtitle) {
        final input = await _assembler.assemble(track, trackDir);
        subtitles.add(
          PackagedSubtitle(
            path: p.relative(input.path, from: dir.path),
            label: track.label,
            language: track.language,
            forced: track.forced,
          ),
        );
        continue;
      }

      final playlist = track.assembly == TrackAssembly.hlsPlaylist
          ? track.playlist!
          : track.segmentPlaylist;
      final file = File(p.join(trackDir.path, _media));
      await file.writeAsString(playlist);
      final uri = 't$t/$_media';

      if (track.kind == TrackKind.video) {
        // A plan carries one video.
        seconds = playlistSeconds(playlist);
        video = MuxInput(
          path: file.path,
          kind: TrackKind.video,
          isHlsPlaylist: true,
        );
      } else {
        audios.add((uri, track));
      }
    }
    if (video == null) {
      throw StateError('A local package needs a video track');
    }

    final videoTrack = plan.tracks.firstWhere((t) => t.kind == TrackKind.video);
    final master = File(p.join(dir.path, _master));
    await master.writeAsString(
      masterPlaylist(
        video: p.relative(video.path, from: dir.path),
        videoTrack: videoTrack,
        audios: audios,
        bandwidth: seconds > 0 && plan.expectedBytes > 0
            ? (plan.expectedBytes * 8 / seconds).round()
            : null,
      ),
    );
    await writeSubtitles(dir, subtitles);

    return LocalPackage(
      masterPath: master.path,
      video: video,
      bytes: await _sizeOf(dir),
    );
  }

  /// Lists [subtitles] (paths relative to [dir]) in the `subtitles.json` of
  /// [dir], what [subtitlesOf] reads — also for sidecars kept beside a
  /// merged file.
  static Future<void> writeSubtitles(
    Directory dir,
    List<PackagedSubtitle> subtitles,
  ) => File(p.join(dir.path, _subtitles)).writeAsString(
    jsonEncode([
      for (final s in subtitles)
        {
          'path': s.path,
          'label': s.label,
          'language': s.language,
          'forced': s.forced,
        },
    ]),
  );

  /// The subtitles of the package whose master is [masterPath], with absolute
  /// paths. Empty when there are none or they cannot be read.
  static Future<List<PackagedSubtitle>> subtitlesOf(String masterPath) async {
    final dir = p.dirname(masterPath);
    try {
      final json = jsonDecode(
        await File(p.join(dir, _subtitles)).readAsString(),
      );
      return [
        for (final item in (json as List).cast<Map<String, Object?>>())
          PackagedSubtitle(
            path: p.join(dir, item['path']! as String),
            label: item['label'] as String?,
            language: item['language'] as String?,
            forced: item['forced'] as bool? ?? false,
          ),
      ];
    } on Object {
      return const [];
    }
  }

  static String masterPlaylist({
    required String video,
    required PlannedTrack videoTrack,
    required List<(String, PlannedTrack)> audios,
    int? bandwidth,
  }) {
    final codecs = _codecs([videoTrack, for (final (_, a) in audios) a]);
    final attributes = [
      // Required; with a single variant it decides nothing.
      'BANDWIDTH=${bandwidth ?? 1000000}',
      if (codecs != null) 'CODECS="$codecs"',
      if (audios.isNotEmpty) 'AUDIO="$_audioGroup"',
    ];

    return [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      for (final (i, (uri, track)) in audios.indexed)
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="$_audioGroup",'
            'NAME="${_quoted(track.label ?? track.language ?? 'Audio ${i + 1}')}",'
            '${track.language == null ? '' : 'LANGUAGE="${_quoted(track.language!)}",'}'
            'DEFAULT=${i == 0 ? 'YES' : 'NO'},AUTOSELECT=YES,URI="$uri"',
      '#EXT-X-STREAM-INF:${attributes.join(',')}',
      video,
      '',
    ].join('\n');
  }

  /// Every track's codecs without repeats, or null when the video does not
  /// declare its own: better none than half a list, which would get tracks
  /// ignored. Subtitle codecs are left out — they are not in the master.
  static String? _codecs(List<PlannedTrack> tracks) {
    if (tracks.first.codecs == null) return null;
    final all = <String>{
      for (final track in tracks)
        for (final codec in (track.codecs ?? '').split(','))
          if (codec.trim() case final c
              when c.isNotEmpty &&
                  !c.startsWith('wvtt') &&
                  !c.startsWith('stpp'))
            c,
    };
    return all.join(',');
  }

  /// A quote would close the attribute.
  static String _quoted(String value) => value.replaceAll('"', "'");

  /// How long a media playlist lasts, adding up its `EXTINF`s.
  static double playlistSeconds(String playlist) => _extinf
      .allMatches(playlist)
      .map((m) => double.tryParse(m.group(1)!) ?? 0)
      .fold(0.0, (a, b) => a + b);

  static final _extinf = RegExp(r'#EXTINF:\s*([\d.]+)');

  static Future<int> _sizeOf(Directory dir) async {
    var bytes = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }
}
