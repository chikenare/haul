import 'dart:math';

import 'package:media_planner/src/errors.dart';
import 'package:xml/xml.dart';

/// Reads a DASH MPD for downloading: every representation with the list of
/// resources to fetch, in order.
///
/// Covers `SegmentTemplate` (`$Number$` and `$Time$`, with or without a
/// `SegmentTimeline`), `SegmentList` and `SegmentBase`/a single file, with
/// `BaseURL` and templates inherited from the AdaptationSet. A multi-period
/// MPD (inserted ads, say) is not downloaded: the representations of each
/// period would have to be paired up.
abstract final class DashParser {
  static DashManifest parse(String text, Uri manifestUri) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(text);
    } on XmlException catch (e) {
      throw SourceException(SourceErrorCode.unsupported, e.message);
    }

    final mpd = document.rootElement;
    if (mpd.getAttribute('type') == 'dynamic') {
      throw const SourceException(SourceErrorCode.live);
    }

    final periods = _children(mpd, 'Period').toList();
    if (periods.isEmpty) {
      throw const SourceException(SourceErrorCode.empty);
    }
    if (periods.length > 1) {
      throw const SourceException(
        SourceErrorCode.unsupported,
        'multi-period MPD',
      );
    }
    final period = periods.single;

    final duration =
        parseDuration(period.getAttribute('duration')) ??
        parseDuration(mpd.getAttribute('mediaPresentationDuration')) ??
        Duration.zero;

    final periodBase = _base(_base(manifestUri, mpd), period);
    final representations = <DashRepresentation>[];

    for (final (index, set) in _children(period, 'AdaptationSet').indexed) {
      // Trick-mode sets (seek thumbnails) are not a quality.
      if (_isTrickMode(set)) continue;
      final setBase = _base(periodBase, set);
      final setProtected = _children(set, 'ContentProtection').isNotEmpty;
      final role = _children(set, 'Role').firstOrNull?.getAttribute('value');
      final label = _children(set, 'Label').firstOrNull?.innerText.trim();

      for (final rep in _children(set, 'Representation')) {
        final mimeType =
            rep.getAttribute('mimeType') ?? set.getAttribute('mimeType');
        final codecs = rep.getAttribute('codecs') ?? set.getAttribute('codecs');
        final type = _typeOf(set.getAttribute('contentType'), mimeType, codecs);
        if (type == null) continue;

        final id = rep.getAttribute('id') ?? '$index-${representations.length}';
        final bandwidth = int.tryParse(rep.getAttribute('bandwidth') ?? '');
        final base = _base(setBase, rep);

        representations.add(
          DashRepresentation(
            id: id,
            adaptationSet: index,
            type: type,
            mimeType: mimeType,
            codecs: codecs,
            bandwidth: bandwidth,
            width: _int(rep, set, 'width'),
            height: _int(rep, set, 'height'),
            language: _language(
              set.getAttribute('lang') ?? rep.getAttribute('lang'),
            ),
            label: (label?.isEmpty ?? true) ? rep.getAttribute('label') : label,
            forced: role == 'forced-subtitle',
            isMainAudio: role == null || role == 'main',
            isProtected:
                setProtected || _children(rep, 'ContentProtection').isNotEmpty,
            segments: _segments(
              rep: rep,
              set: set,
              period: period,
              base: base,
              id: id,
              bandwidth: bandwidth,
              duration: duration,
            ),
          ),
        );
      }
    }

    if (representations.isEmpty) {
      throw const SourceException(SourceErrorCode.empty);
    }

    return DashManifest(duration: duration, representations: representations);
  }

  static List<DashSegment> _segments({
    required XmlElement rep,
    required XmlElement set,
    required XmlElement period,
    required Uri base,
    required String id,
    required int? bandwidth,
    required Duration duration,
  }) {
    final out = <DashSegment>[];
    final seen = <Uri>{};
    void add(Uri uri, [double? seconds]) {
      if (seen.add(uri)) out.add(DashSegment(uri, seconds));
    }

    String fill(String template, {int? number, int? time}) => fillTemplate(
      template,
      id: id,
      bandwidth: bandwidth,
      number: number,
      time: time,
    );

    // The most specific wins: a SegmentList or SegmentBase on the
    // representation beats a SegmentTemplate inherited from the period.
    final scheme = [rep, set, period]
        .expand(
          (el) => el.childElements
              .map((c) => c.name.local)
              .where(_segmentInfo.contains),
        )
        .firstOrNull;

    final templates = [
      for (final el in [period, set, rep]) ..._children(el, 'SegmentTemplate'),
    ];
    if (scheme == 'SegmentTemplate') {
      // The most specific wins, attribute by attribute.
      String? attr(String name) => templates.reversed
          .map((t) => t.getAttribute(name))
          .nonNulls
          .firstOrNull;

      final media = attr('media');
      if (media == null) {
        throw const SourceException(SourceErrorCode.unsupported);
      }
      final timescale = int.tryParse(attr('timescale') ?? '') ?? 1;
      final startNumber = int.tryParse(attr('startNumber') ?? '') ?? 1;
      final offset = int.tryParse(attr('presentationTimeOffset') ?? '') ?? 0;

      if (attr('initialization') case final init?) {
        add(base.resolve(fill(init)));
      }

      final timeline = templates.reversed
          .expand((t) => _children(t, 'SegmentTimeline'))
          .firstOrNull;

      if (timeline != null) {
        final end = offset + duration.inMicroseconds * timescale ~/ 1000000;
        var time = 0;
        var number = startNumber;

        final entries = _children(timeline, 'S').toList();
        for (final (i, s) in entries.indexed) {
          time = int.tryParse(s.getAttribute('t') ?? '') ?? time;
          final d = int.tryParse(s.getAttribute('d') ?? '') ?? 0;
          if (d <= 0) continue;
          var repeat = int.tryParse(s.getAttribute('r') ?? '') ?? 0;
          if (repeat < 0) {
            // Up to the next S's `t` or, on the last one, to the end of the
            // period. In integers: with decimals a rounding would ask for one
            // fragment too many, which does not exist.
            final nextT = i + 1 < entries.length
                ? int.tryParse(entries[i + 1].getAttribute('t') ?? '')
                : null;
            repeat = ((nextT ?? end) - time + d - 1) ~/ d - 1;
          }

          for (var i = 0; i <= repeat; i++) {
            add(
              base.resolve(fill(media, number: number, time: time)),
              d / timescale,
            );
            time += d;
            number++;
          }
        }
      } else {
        final segmentDuration = int.tryParse(attr('duration') ?? '');
        if (segmentDuration == null || segmentDuration <= 0) {
          throw const SourceException(SourceErrorCode.unsupported);
        }
        final ticks = duration.inMicroseconds * timescale ~/ 1000000;
        final count = (ticks + segmentDuration - 1) ~/ segmentDuration;
        for (var i = 0; i < count; i++) {
          // The last one lasts whatever is left of the period.
          final length = min(segmentDuration, ticks - i * segmentDuration);
          add(
            base.resolve(
              fill(
                media,
                number: startNumber + i,
                time: offset + i * segmentDuration,
              ),
            ),
            length / timescale,
          );
        }
      }
      // Without a duration or a timeline no fragment comes out: an init on
      // its own is not a video.
      if (out.length <= (attr('initialization') == null ? 0 : 1)) {
        throw const SourceException(SourceErrorCode.empty);
      }
      return out;
    }

    final list = [
      for (final el in [rep, set, period]) ..._children(el, 'SegmentList'),
    ].firstOrNull;
    if (scheme == 'SegmentList' && list != null) {
      // Without `sourceURL`/`media` the resource is the BaseURL itself read
      // by ranges: it is fetched whole, once.
      final timescale = int.tryParse(list.getAttribute('timescale') ?? '') ?? 1;
      final length = int.tryParse(list.getAttribute('duration') ?? '');
      if (_children(list, 'Initialization').firstOrNull case final init?) {
        add(base.resolve(init.getAttribute('sourceURL') ?? ''));
      }
      for (final segment in _children(list, 'SegmentURL')) {
        add(
          base.resolve(segment.getAttribute('media') ?? ''),
          length == null ? null : length / timescale,
        );
      }
      return out;
    }

    // SegmentBase or nothing: the representation is a whole file.
    add(
      base,
      duration == Duration.zero ? null : duration.inMicroseconds / 1000000,
    );
    return out;
  }

  /// Fills a DASH template's identifiers, with the optional `%0Nd` width.
  static String fillTemplate(
    String template, {
    required String id,
    int? bandwidth,
    int? number,
    int? time,
  }) {
    return template.replaceAllMapped(_identifier, (m) {
      final value = switch (m.group(1)) {
        'RepresentationID' => id,
        'Number' => number?.toString(),
        'Bandwidth' => bandwidth?.toString(),
        'Time' => time?.toString(),
        _ => r'$',
      };
      if (value == null) return m.group(0)!;

      final width = int.tryParse(m.group(2) ?? '');
      return width == null ? value : value.padLeft(width, '0');
    });
  }

  static final _identifier = RegExp(
    r'\$(RepresentationID|Number|Bandwidth|Time|)(?:%0(\d+)d)?\$',
  );

  /// An MPD's ISO 8601 durations (`PT1H2M3.5S`, `P0DT...`).
  static Duration? parseDuration(String? value) {
    if (value == null) return null;
    final m = _isoDuration.firstMatch(value.trim());
    if (m == null) return null;

    double part(int group) => double.tryParse(m.group(group) ?? '') ?? 0;
    // Years and months have no fixed length; packagers write them as zero
    // (`P0Y0M0DT1H...`), so the approximation does not matter.
    final seconds =
        part(1) * 365 * 86400 +
        part(2) * 30 * 86400 +
        part(3) * 86400 +
        part(4) * 3600 +
        part(5) * 60 +
        part(6);
    return Duration(microseconds: (seconds * 1000000).round());
  }

  static final _isoDuration = RegExp(
    r'^P(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)D)?'
    r'(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  );

  static DashContentType? _typeOf(
    String? contentType,
    String? mimeType,
    String? codecs,
  ) {
    final kind = contentType ?? mimeType?.split('/').first;
    if (codecs != null &&
        (codecs.startsWith('wvtt') || codecs.startsWith('stpp'))) {
      return DashContentType.text;
    }
    return switch (kind) {
      'video' => DashContentType.video,
      'audio' => DashContentType.audio,
      'text' || 'application' => DashContentType.text,
      _ => null,
    };
  }

  static Uri _base(Uri parent, XmlElement element) {
    final url = _children(element, 'BaseURL').firstOrNull?.innerText.trim();
    return url == null || url.isEmpty ? parent : parent.resolve(url);
  }

  /// `und` is "no language": better none than a meaningless tag.
  static String? _language(String? lang) =>
      lang == null || lang.isEmpty || lang == 'und' ? null : lang;

  static int? _int(XmlElement rep, XmlElement set, String name) =>
      int.tryParse(rep.getAttribute(name) ?? set.getAttribute(name) ?? '');

  /// By local name: some MPDs carry a prefix (`mpd:Period`).
  static Iterable<XmlElement> _children(XmlElement element, String name) =>
      element.findElements(name, namespaceUri: '*');

  static const _segmentInfo = {'SegmentTemplate', 'SegmentList', 'SegmentBase'};

  static bool _isTrickMode(XmlElement set) => [
    ..._children(set, 'EssentialProperty'),
    ..._children(set, 'SupplementalProperty'),
  ].any((p) => p.getAttribute('schemeIdUri')?.contains('trickmode') ?? false);
}

enum DashContentType { video, audio, text }

class DashManifest {
  const DashManifest({required this.duration, required this.representations});

  final Duration duration;
  final List<DashRepresentation> representations;

  Iterable<DashRepresentation> ofType(DashContentType type) =>
      representations.where((r) => r.type == type);
}

class DashRepresentation {
  const DashRepresentation({
    required this.id,
    required this.adaptationSet,
    required this.type,
    required this.segments,
    this.mimeType,
    this.codecs,
    this.bandwidth,
    this.width,
    this.height,
    this.language,
    this.label,
    this.forced = false,
    this.isMainAudio = true,
    this.isProtected = false,
  });

  final String id;

  /// Index of the AdaptationSet: the representations of one set are the same
  /// track in different qualities.
  final int adaptationSet;
  final DashContentType type;

  /// Init and fragments, in order and without repeats.
  final List<DashSegment> segments;

  List<Uri> get resources => [for (final s in segments) s.uri];
  final String? mimeType;
  final String? codecs;
  final int? bandwidth;
  final int? width;
  final int? height;
  final String? language;
  final String? label;
  final bool forced;
  final bool isMainAudio;
  final bool isProtected;
}

/// One resource of a representation: the init (no duration) or a fragment.
class DashSegment {
  const DashSegment(this.uri, [this.seconds]);

  final Uri uri;

  /// Null on the init, or when the MPD does not say.
  final double? seconds;
}
