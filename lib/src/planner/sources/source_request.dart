import 'package:meta/meta.dart';

/// What to download: a URL that may be a plain file (mp4, mkv…) or an
/// HLS/DASH manifest — which one is decided by the content (see
/// `SourceResolver`), never by the URL.
@immutable
class SourceRequest {
  const SourceRequest({required this.url, this.headers, this.subtitles});

  final String url;

  /// Sent on every request: the manifest, its media playlists and pieces.
  final Map<String, String>? headers;

  /// External subtitles, `label → url`, offered beside the source's own.
  final Map<String, String>? subtitles;
}
