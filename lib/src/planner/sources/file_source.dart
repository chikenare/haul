import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:offline_engine/src/planner/media_options.dart';
import 'package:offline_engine/src/planner/plan.dart';
import 'package:offline_engine/src/planner/sources/resolved_source.dart';
import 'package:offline_engine/src/planner/sources/source_fetcher.dart';
import 'package:path/path.dart' as p;

/// A whole file (mp4, mkv, webm…). Fetched as it is; it only goes through
/// ffmpeg when there are external subtitles to put in, and then it comes out
/// as MKV.
class FileSource extends ResolvedSource {
  FileSource(super.request, this.response)
    : extension = _extensionFor(response);

  /// The head that was read to tell what the source is.
  final FetchedResponse response;

  final String extension;

  @override
  SourceKind get kind => SourceKind.file;

  @override
  int? estimatedBytes(SourceSelection selection) => response.contentLength;

  @override
  Future<DownloadPlan> plan(SourceSelection selection) async {
    final subtitles = externalSubtitleTracks(selection);
    final video = PlannedTrack(
      kind: TrackKind.video,
      assembly: TrackAssembly.single,
      pieces: [PlannedPiece(url: request.url, file: '0.$extension')],
      sourceId: 'file',
    );

    return DownloadPlan(
      tracks: [video, ...subtitles],
      extension: subtitles.isEmpty ? extension : 'mkv',
      expectedBytes: response.contentLength ?? 0,
    );
  }

  static const _videoExtensions = {
    'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'ts', 'flv', 'wmv', '3gp', //
    'mpg', 'mpeg', 'ogv', 'mp3', 'm4a', 'aac', 'flac', 'opus', 'ogg', 'wav',
  };

  /// First the name the server gives, then the URL, then the
  /// `Content-Type`: signed links rarely carry an extension. None overrides
  /// the content: an MKV served as `.mp4` would come out with the wrong
  /// extension, and ffmpeg would treat its subtitles as an MP4's (see
  /// `MkvArgs`).
  static String _extensionFor(FetchedResponse response) {
    final sniffed = sniffContainer(response.body);
    bool fits(String ext) =>
        _videoExtensions.contains(ext) &&
        (sniffed == null || sniffed.contains(ext));

    for (final name in [response.suggestedFilename, response.url.path]) {
      if (name == null) continue;
      final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
      if (fits(ext)) return ext;
    }

    final mime = response.contentType?.split(';').first.trim();
    final fromMime = mime == null ? null : extensionFromMime(mime);
    if (fromMime != null && fits(fromMime)) return fromMime;

    return sniffed?.first ?? 'mp4';
  }

  /// The extensions that fit the first bytes, the usual one first; null when
  /// the container is not recognised.
  @visibleForTesting
  static List<String>? sniffContainer(List<int> head) {
    bool ascii(int offset, String text) {
      if (head.length < offset + text.length) return false;
      for (var i = 0; i < text.length; i++) {
        if (head[offset + i] != text.codeUnitAt(i)) return false;
      }
      return true;
    }

    // EBML: Matroska or WebM by the DocType, early in the header.
    if (ascii(0, '\x1A\x45\xDF\xA3')) {
      return String.fromCharCodes(head.take(64)).contains('webm')
          ? const ['webm', 'mkv']
          : const ['mkv', 'webm'];
    }
    if (ascii(4, 'ftyp')) {
      return ascii(8, 'qt  ')
          ? const ['mov', 'mp4']
          : const ['mp4', 'm4v', 'm4a', 'mov', '3gp'];
    }
    // Transport stream: a sync byte every 188.
    if (head.length > 188 && head[0] == 0x47 && head[188] == 0x47) {
      return const ['ts'];
    }
    if (ascii(0, 'RIFF') && ascii(8, 'AVI ')) return const ['avi'];
    if (ascii(0, 'RIFF') && ascii(8, 'WAVE')) return const ['wav'];
    if (ascii(0, 'FLV')) return const ['flv'];
    if (ascii(0, 'OggS')) return const ['ogg', 'ogv', 'opus'];
    if (ascii(0, 'fLaC')) return const ['flac'];
    if (ascii(0, 'ID3')) return const ['mp3', 'aac'];
    return null;
  }
}
