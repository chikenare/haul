import 'package:haul/src/planner/media_options.dart';
import 'package:haul/src/planner/plan.dart';
import 'package:haul/src/planner/sources/resolved_source.dart';
import 'package:haul/src/planner/sources/source_fetcher.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// A whole file (mp4, mkv, webm…). Fetched as it is — in byte ranges when
/// it is big and the server allows it — and it only goes through ffmpeg
/// when there are external subtitles to put in, and then it comes out as
/// MKV.
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
    final length = response.contentLength;
    final ranged = length != null && length > rangeSize && acceptsRanges;
    final video = PlannedTrack(
      kind: TrackKind.video,
      assembly: ranged ? TrackAssembly.ranges : TrackAssembly.single,
      pieces: ranged
          ? [
              for (
                var start = 0, i = 0;
                start < length;
                start += rangeSize, i++
              )
                PlannedPiece(
                  url: request.url,
                  file: '$i.part',
                  rangeStart: start,
                  rangeEnd:
                      (start + rangeSize < length
                          ? start + rangeSize
                          : length) -
                      1,
                ),
            ]
          : [
              PlannedPiece(
                url: request.url,
                file: '0.$extension',
                size: _identityLength,
              ),
            ],
      sourceId: 'file',
      ifRange: ranged ? _strongEtag : null,
      fileExtension: ranged ? extension : null,
      estimatedBytes: response.contentLength,
    );

    return DownloadPlan(
      tracks: [video, ...subtitles],
      extension: subtitles.isEmpty ? extension : 'mkv',
      expectedBytes: response.contentLength ?? 0,
    );
  }

  /// The size of each range of a big file: small enough that a pause or a
  /// kill loses little, big enough that a 4 GB movie stays a few hundred
  /// requests.
  static const rangeSize = 16 * 1024 * 1024;

  /// Whether the server said it serves byte ranges. Without it the file
  /// comes down in one request, which a pause starts over.
  bool get acceptsRanges =>
      response.headers['accept-ranges']?.toLowerCase().contains('bytes') ??
      false;

  /// The size the file arrives with: only when the server sends it as is
  /// — a compressed body's length is not the file's.
  int? get _identityLength {
    final encoding = response.headers['content-encoding']?.toLowerCase();
    if (encoding != null && encoding != 'identity') return null;
    return response.contentLength;
  }

  /// A weak ETag (`W/"…"`) cannot validate a range.
  String? get _strongEtag {
    final etag = response.headers['etag']?.trim();
    return etag == null || etag.startsWith('W/') ? null : etag;
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
