/// Why a source cannot be downloaded, as a code: it is stored on the row and
/// the screen translates it, so nothing here is user-facing prose.
abstract final class SourceErrorCode {
  /// Protected content (Widevine, FairPlay, SAMPLE-AES, CENC).
  static const drm = 'drm';

  /// A live stream: there is no end to download.
  static const live = 'live';

  /// The manifest holds nothing downloadable.
  static const empty = 'empty';

  /// A manifest this reader does not handle (multi-period DASH, broken XML).
  static const unsupported = 'unsupported';

  /// The source did not answer.
  static const network = 'network';

  /// A piece the plan lists is not on disk when the track is assembled.
  static const missingPieces = 'missing_pieces';

  /// An HTTP error from the source, stored as `http_<status>`.
  static String http(int status) => 'http_$status';

  static int? httpStatus(String code) =>
      code.startsWith('http_') ? int.tryParse(code.substring(5)) : null;
}

/// A source that cannot be read or fetched. [code] is one of
/// [SourceErrorCode]; [detail] is what the source said, for the log only.
class SourceException implements Exception {
  const SourceException(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() =>
      'SourceException($code${detail == null ? '' : ': $detail'})';
}
