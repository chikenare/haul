import 'package:haul/src/planner/errors.dart';

/// Reads HLS playlists (RFC 8216) for downloading: what qualities and tracks a
/// master offers, and what resources a media playlist needs fetched.
abstract final class HlsParser {
  static bool isMaster(String text) => text.contains('#EXT-X-STREAM-INF');

  static HlsMaster parseMaster(String text, Uri baseUri) {
    final variants = <HlsVariant>[];
    final renditions = <HlsRendition>[];
    Map<String, String>? pendingVariant;

    for (final line in _lines(text)) {
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pendingVariant = parseAttributes(line);
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        final attrs = parseAttributes(line);
        final type = attrs['TYPE'];
        if (type != 'AUDIO' && type != 'SUBTITLES') continue;

        final uri = attrs['URI'];
        renditions.add(
          HlsRendition(
            type: type == 'AUDIO'
                ? HlsRenditionType.audio
                : HlsRenditionType.subtitles,
            groupId: attrs['GROUP-ID'] ?? '',
            uri: uri == null ? null : baseUri.resolve(uri),
            language: attrs['LANGUAGE'],
            name: attrs['NAME'],
            channels: attrs['CHANNELS'],
            isDefault: attrs['DEFAULT'] == 'YES',
            forced: attrs['FORCED'] == 'YES',
          ),
        );
      } else if (pendingVariant != null && !line.startsWith('#')) {
        final resolution = pendingVariant['RESOLUTION']?.split('x');
        variants.add(
          HlsVariant(
            uri: baseUri.resolve(line),
            bandwidth:
                int.tryParse(pendingVariant['AVERAGE-BANDWIDTH'] ?? '') ??
                int.tryParse(pendingVariant['BANDWIDTH'] ?? '') ??
                0,
            width: int.tryParse(resolution?.first ?? ''),
            height: int.tryParse(resolution?.last ?? ''),
            codecs: pendingVariant['CODECS'],
            audioGroup: pendingVariant['AUDIO'],
            subtitleGroup: pendingVariant['SUBTITLES'],
          ),
        );
        pendingVariant = null;
      }
    }

    return HlsMaster(variants: variants, renditions: renditions);
  }

  /// A media playlist's resources, in order and without repeats: with
  /// `EXT-X-BYTERANGE` several fragments are slices of one file, fetched once
  /// while the local playlist keeps reading it by ranges.
  ///
  /// Throws [SourceException] on a live stream (no `EXT-X-ENDLIST`) or on any
  /// encryption other than AES-128 with an open key: SAMPLE-AES and the
  /// FairPlay/Widevine `KEYFORMAT`s are DRM.
  static HlsMedia parseMedia(String text, Uri baseUri) {
    final resources = <Uri>[];
    final seen = <Uri>{};
    var ended = false;
    var seconds = 0.0;

    void add(String uri) {
      // A `data:` key lives inside the playlist: there is nothing to fetch
      // and it is read as it is.
      if (uri.startsWith('data:')) return;
      final resolved = baseUri.resolve(uri);
      if (seen.add(resolved)) resources.add(resolved);
    }

    for (final line in _lines(text)) {
      if (line.startsWith('#EXTINF:')) {
        final value = line.substring(8).split(',').first;
        seconds += double.tryParse(value) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final attrs = parseAttributes(line);
        final method = attrs['METHOD'] ?? 'NONE';
        if (method == 'NONE') continue;

        final keyFormat = attrs['KEYFORMAT'] ?? 'identity';
        if (method != 'AES-128' || keyFormat != 'identity') {
          throw const SourceException(SourceErrorCode.drm);
        }
        if (attrs['URI'] case final uri?) add(uri);
      } else if (line.startsWith('#EXT-X-MAP:')) {
        if (parseAttributes(line)['URI'] case final uri?) add(uri);
      } else if (line == '#EXT-X-ENDLIST' ||
          line == '#EXT-X-PLAYLIST-TYPE:VOD') {
        ended = true;
      } else if (!line.startsWith('#')) {
        add(line);
      }
    }

    if (!ended) throw const SourceException(SourceErrorCode.live);
    if (resources.isEmpty) {
      throw const SourceException(SourceErrorCode.empty);
    }

    return HlsMedia(
      text: text,
      baseUri: baseUri,
      resources: resources,
      duration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  /// A tag's `KEY=VALUE,KEY="VALUE, with commas"`.
  static Map<String, String> parseAttributes(String line) {
    final start = line.indexOf(':');
    final body = start < 0 ? '' : line.substring(start + 1);

    return {
      for (final match in _attribute.allMatches(body))
        match.group(1)!: _unquote(match.group(2)!),
    };
  }

  static final _attribute = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
      ? value.substring(1, value.length - 1)
      : value;

  static Iterable<String> _lines(String text) => text
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty);
}

class HlsMaster {
  const HlsMaster({required this.variants, required this.renditions});

  final List<HlsVariant> variants;
  final List<HlsRendition> renditions;

  /// The alternative tracks of [group] that can be fetched on their own. The
  /// ones without a URI travel inside the variant itself.
  List<HlsRendition> renditionsOf(HlsRenditionType type, String? group) => [
    for (final r in renditions)
      if (r.type == type && r.groupId == group && r.uri != null) r,
  ];
}

class HlsVariant {
  const HlsVariant({
    required this.uri,
    required this.bandwidth,
    this.width,
    this.height,
    this.codecs,
    this.audioGroup,
    this.subtitleGroup,
  });

  final Uri uri;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final String? audioGroup;
  final String? subtitleGroup;
}

enum HlsRenditionType { audio, subtitles }

class HlsRendition {
  const HlsRendition({
    required this.type,
    required this.groupId,
    this.uri,
    this.language,
    this.name,
    this.channels,
    this.isDefault = false,
    this.forced = false,
  });

  final HlsRenditionType type;
  final String groupId;
  final Uri? uri;
  final String? language;
  final String? name;
  final String? channels;
  final bool isDefault;
  final bool forced;

  /// Unique within a master: one language can repeat across groups (one per
  /// quality).
  String get id => '$groupId/${name ?? language ?? uri}';
}

class HlsMedia {
  const HlsMedia({
    required this.text,
    required this.baseUri,
    required this.resources,
    required this.duration,
  });

  final String text;
  final Uri baseUri;

  /// Fragments, inits (`EXT-X-MAP`) and keys, in order of appearance.
  final List<Uri> resources;
  final Duration duration;

  /// The same playlist with every URI swapped for the local name [names]
  /// gives it, resolved relative to the folder it is written to.
  String localPlaylist(Map<Uri, String> names) {
    String local(String uri) => names[baseUri.resolve(uri)] ?? uri;

    final out = <String>[];
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-KEY:') || line.startsWith('#EXT-X-MAP:')) {
        out.add(
          line.replaceAllMapped(
            _uriAttribute,
            (m) => 'URI="${local(m.group(1)!)}"',
          ),
        );
      } else if (line.startsWith('#')) {
        out.add(line);
      } else {
        out.add(local(line));
      }
    }
    return '${out.join('\n')}\n';
  }

  static final _uriAttribute = RegExp(r'URI="([^"]*)"');
}
