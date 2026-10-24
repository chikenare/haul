import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:haul/src/planner/errors.dart';

/// An HTTP response already read, whole or up to a cap.
class FetchedResponse {
  const FetchedResponse({
    required this.url,
    required this.headers,
    required this.body,
    this.truncated = false,
  });

  /// The final URL, after redirects: a manifest's relative paths resolve
  /// against it, not against the one asked for.
  final Uri url;

  /// Lower-cased headers.
  final Map<String, String> headers;
  final List<int> body;

  /// The body was cut at the requested cap.
  final bool truncated;

  String? get contentType => headers['content-type'];

  int? get contentLength => int.tryParse(headers['content-length'] ?? '');

  /// The name the server suggests in `Content-Disposition`.
  String? get suggestedFilename {
    final disposition = headers['content-disposition'];
    if (disposition == null) return null;
    final match = _filename.firstMatch(disposition);
    // Only `filename*` is encoded (RFC 5987); a plain `filename` can carry a
    // literal `%` ("100% Movie.mp4").
    if (match?.group(1) case final encoded?) {
      try {
        return Uri.decodeComponent(encoded.trim());
      } on ArgumentError {
        return encoded.trim();
      }
    }
    return match?.group(2)?.trim();
  }

  static final _filename = RegExp(
    r"""filename\*=(?:UTF-8'')?([^;]+)|filename="?([^";]+)"?""",
    caseSensitive: false,
  );
}

/// The requests of the resolving phase (manifests and a plain file's head).
/// The pieces themselves are fetched by the app's downloader.
abstract class SourceFetcher {
  const SourceFetcher();

  /// Throws [SourceException] on an HTTP error or without network. With
  /// [maxBytes] it stops reading at the cap and drops the connection: to see
  /// what a file is without fetching all of it.
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  });
}

class HttpSourceFetcher extends SourceFetcher {
  const HttpSourceFetcher();

  static const _timeout = Duration(seconds: 30);

  /// A DASH of several hours with a SegmentList is a few MB.
  static const _maxManifestBytes = 32 * 1024 * 1024;

  @override
  Future<FetchedResponse> fetch(
    Uri url, {
    Map<String, String> headers = const {},
    int? maxBytes,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.getUrl(url).timeout(_timeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(_timeout);

      if (response.statusCode >= 400) {
        throw SourceException(SourceErrorCode.http(response.statusCode));
      }

      final body = BytesBuilder(copy: false);
      var truncated = false;
      await for (final chunk in response.timeout(_timeout)) {
        body.add(chunk);
        if (maxBytes != null && body.length >= maxBytes) {
          truncated = true;
          break; // Cancels the subscription, and with it the transfer.
        }
        // Without a cap only manifests are read: something this big is not
        // one (a file served with an HLS `Content-Type`, say).
        if (maxBytes == null && body.length > _maxManifestBytes) {
          throw const SourceException(SourceErrorCode.unsupported);
        }
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (name, values) =>
            responseHeaders[name.toLowerCase()] = values.join(','),
      );

      return FetchedResponse(
        url: response.redirects.fold(
          url,
          (current, redirect) => current.resolveUri(redirect.location),
        ),
        headers: responseHeaders,
        body: body.takeBytes(),
        truncated: truncated,
      );
    } on SourceException {
      rethrow;
    } on Object catch (e) {
      throw SourceException(SourceErrorCode.network, '$e');
    } finally {
      client.close(force: true);
    }
  }
}
