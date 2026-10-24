import 'package:collection/collection.dart';
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

  factory SourceRequest.fromJson(Map<String, Object?> json) => SourceRequest(
    url: json['url']! as String,
    headers: (json['headers'] as Map?)?.cast<String, String>(),
    subtitles: (json['subtitles'] as Map?)?.cast<String, String>(),
  );

  Map<String, Object?> toJson() => {
    'url': url,
    if (headers != null) 'headers': headers,
    if (subtitles != null) 'subtitles': subtitles,
  };

  @override
  bool operator ==(Object other) =>
      other is SourceRequest &&
      other.url == url &&
      _maps.equals(other.headers, headers) &&
      _maps.equals(other.subtitles, subtitles);

  static const _maps = MapEquality<String, String>();

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(
      headers?.entries.map((e) => '${e.key}=${e.value}') ?? const [],
    ),
    Object.hashAllUnordered(
      subtitles?.entries.map((e) => '${e.key}=${e.value}') ?? const [],
    ),
  );
}
