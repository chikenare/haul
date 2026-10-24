import 'dart:convert';

import 'package:haul/src/planner/errors.dart';
import 'package:haul/src/planner/manifest/dash_parser.dart';
import 'package:haul/src/planner/plan.dart';
import 'package:haul/src/planner/sources/dash_source.dart';
import 'package:haul/src/planner/sources/file_source.dart';
import 'package:haul/src/planner/sources/hls_source.dart';
import 'package:haul/src/planner/sources/resolved_source.dart';
import 'package:haul/src/planner/sources/source_fetcher.dart';
import 'package:haul/src/planner/sources/source_request.dart';

/// Works out what a source is and leaves it ready to pick what to fetch.
///
/// A declared type is not to be trusted: the content decides. The first
/// bytes are asked for and, when they are a manifest, it is read whole;
/// otherwise the same response gives the file's weight and name without
/// fetching it.
class SourceResolver {
  const SourceResolver({this.fetcher = const HttpSourceFetcher()});

  final SourceFetcher fetcher;

  /// Just enough to recognise a manifest by its head.
  static const _sniffBytes = 64 * 1024;

  Future<ResolvedSource> resolve(SourceRequest request) async {
    final url = Uri.tryParse(request.url);
    if (url == null || !url.hasScheme) {
      throw const SourceException(SourceErrorCode.unsupported);
    }

    final headers = request.headers ?? const {};
    var response = await fetcher.fetch(
      url,
      headers: headers,
      maxBytes: _sniffBytes,
    );
    final kind = _manifestKind(response);
    if (kind == null) return FileSource(request, response);

    if (response.truncated) {
      response = await fetcher.fetch(url, headers: headers);
    }
    final text = _decode(response.body);

    return switch (kind) {
      _Manifest.hls => HlsSource(
        request,
        fetcher: fetcher,
        url: response.url,
        text: text,
      ),
      _Manifest.dash => DashSource(
        request,
        DashParser.parse(text, response.url),
      ),
    };
  }

  /// Only what it is: HLS, DASH or a file. For playing a link whose URL does
  /// not say (a signed link with no extension): players on auto decide by
  /// the extension, not the content.
  Future<SourceKind> detectKind(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await fetcher.fetch(url, headers: headers, maxBytes: 4096);
    return switch (_manifestKind(response)) {
      _Manifest.hls => SourceKind.hls,
      _Manifest.dash => SourceKind.dash,
      null => SourceKind.file,
    };
  }

  static _Manifest? _manifestKind(FetchedResponse response) {
    final type = response.contentType?.toLowerCase() ?? '';
    if (type.contains('mpegurl')) return _Manifest.hls;
    if (type.contains('dash+xml')) return _Manifest.dash;

    // Whatever was read (up to 4 KB): a long XML comment can push the root
    // past the first KB.
    final head = _decode(response.body.take(4096).toList()).trimLeft();
    if (head.startsWith('#EXTM3U')) return _Manifest.hls;
    if (head.startsWith('<') && _mpdRoot.hasMatch(head)) return _Manifest.dash;
    return null;
  }

  /// `<MPD`, or with a namespace prefix (`<mpd:MPD`).
  static final _mpdRoot = RegExp(r'<(?:\w+:)?MPD[\s>]');

  /// Without the BOM: some servers put one before the `#EXTM3U`.
  static String _decode(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
}

enum _Manifest { hls, dash }
