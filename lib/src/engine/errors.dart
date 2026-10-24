import 'dart:async';
import 'dart:io';

import 'package:offline_engine/src/engine/model.dart';
import 'package:offline_engine/src/planner/errors.dart';

/// The codes a failed download carries, besides the app's own (from a
/// `RefreshException`).
abstract final class DownloadErrorCode {
  /// No network, a timeout, or a piece the downloader gave up on.
  static const network = 'network';

  /// The server answered an error to a piece; see `DownloadError.httpStatus`.
  static const http = 'http';

  /// The device ran out of room. The one failure the user can act on.
  static const noSpace = 'no_space';

  /// ffmpeg could not join the tracks.
  static const mux = 'mux_failed';

  /// DRM, a live stream, nothing in it, or a shape the reader does not
  /// handle: a retry would not help.
  static const unavailable = 'unavailable';

  /// A piece is not what was asked for: a range of the wrong size, a file
  /// that changed between two ranges, or a piece missing at assembly.
  static const corrupt = 'corrupt';

  /// The output sink could not take the finished file.
  static const publish = 'publish_failed';

  static const unknown = 'unknown';
}

/// The device is out of room: errno 28 (ENOSPC), 112 or 39 on Windows
/// (`ERROR_DISK_FULL`, `ERROR_HANDLE_DISK_FULL`), or the words the
/// platforms put it in when the errno is lost on the way.
bool isOutOfSpace(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112 || code == 39) return true;
  }
  final text = '$error'.toLowerCase();
  return text.contains('no space left') ||
      text.contains('enospc') ||
      text.contains('not enough space') ||
      text.contains('disk full') ||
      text.contains('sqlite_full');
}

/// [error] as what the record keeps.
DownloadError downloadErrorOf(Object error) {
  if (isOutOfSpace(error)) {
    return const DownloadError(code: DownloadErrorCode.noSpace);
  }
  if (error is SourceException) {
    return switch (error.code) {
      SourceErrorCode.drm ||
      SourceErrorCode.live ||
      SourceErrorCode.empty ||
      SourceErrorCode.unsupported => const DownloadError(
        code: DownloadErrorCode.unavailable,
      ),
      SourceErrorCode.network => const DownloadError(
        code: DownloadErrorCode.network,
      ),
      SourceErrorCode.missingPieces => const DownloadError(
        code: DownloadErrorCode.corrupt,
      ),
      final code => switch (SourceErrorCode.httpStatus(code)) {
        final status? => DownloadError(
          code: DownloadErrorCode.http,
          httpStatus: status,
        ),
        null => const DownloadError(code: DownloadErrorCode.unknown),
      },
    };
  }
  // What an app's refresher, or anything else talking to a server, throws
  // without going through `SourceFetcher`: a network failure all the same.
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException) {
    return const DownloadError(code: DownloadErrorCode.network);
  }
  return const DownloadError(code: DownloadErrorCode.unknown);
}
