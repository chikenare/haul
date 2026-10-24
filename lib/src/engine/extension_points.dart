import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/planner/sources/source_request.dart';
import 'package:haul/src/planner/track_criteria.dart';

/// A fresh link for a download whose link ran out or was refused: the app
/// mints it again, resolves its host again, or has nothing to offer.
abstract interface class SourceRefresher {
  /// Throw [RefreshException] to fail the download with something the app
  /// can show (a spent allowance, a server message).
  Future<RefreshedSource> refresh(DownloadRecord record);
}

/// What a [SourceRefresher] answers.
class RefreshedSource {
  const RefreshedSource(this.source, {this.expiresAt, this.metadata});

  final SourceRequest source;
  final DateTime? expiresAt;

  /// Replaces the record's metadata when given (a link that changed).
  final Map<String, Object?>? metadata;
}

/// A refusal the download fails with: [code] is the app's own, for the app
/// to localize; [message] what the server said, already translated.
class RefreshException implements Exception {
  const RefreshException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() =>
      'RefreshException($code${message == null ? '' : ': $message'})';
}

/// The tracks a [TrackChoice.policy] download keeps, read when its turn
/// comes. Async: on a cold start the account may not have loaded yet.
typedef CriteriaProvider =
    Future<TrackCriteria> Function(DownloadRecord record);

/// Where a finished file goes. The engine writes it in the download's own
/// folder; the sink moves it wherever the app keeps files and answers how
/// it will find it again.
abstract interface class OutputSink {
  /// Moves [staged] to where [name] says, with [extension] (no dot), and
  /// answers its locator. Throwing leaves [staged] where it is, so a retry
  /// only publishes again.
  Future<String> publish(
    File staged,
    OutputName name,
    String extension,
    DownloadRecord record,
  );

  /// Removes what [publish] answered with; a locator already gone is fine.
  Future<void> remove(String locator);
}

/// An [OutputSink] that says where a file will go before moving it. The
/// engine saves that place first, so a kill in the middle of a publish —
/// after the move, before the record says done — is picked up from the
/// file already there, instead of fetching and merging it all again.
abstract interface class ReservingOutputSink implements OutputSink {
  /// The locator a publish of [name] would answer now; nothing is written.
  /// Null when the file would stay private (then [publish] is used).
  Future<String?> reserve(
    OutputName name,
    String extension,
    DownloadRecord record,
  );

  /// Moves [staged] to [locator], from [reserve], and answers where it
  /// ended up: another free name when [locator] was taken meanwhile.
  Future<String> publishTo(File staged, String locator, DownloadRecord record);

  /// Whether [locator] holds a published file.
  Future<bool> holds(String locator);
}

/// Runs ffmpeg with [args] (see `MkvArgs`). The engine does not depend on
/// an ffmpeg build: each app brings its own.
abstract interface class FfmpegRunner {
  /// Throws [FfmpegException] when ffmpeg fails.
  Future<void> run(List<String> args);
}

class FfmpegException implements Exception {
  const FfmpegException(this.log);

  /// What ffmpeg wrote; its last line usually says why.
  final String log;

  @override
  String toString() =>
      'FfmpegException(${log.length > 300 ? log.substring(log.length - 300) : log})';
}

/// What the engine reports and does not decide itself.
abstract interface class EngineLogger {
  void warn(String message);

  /// Something unexpected: worth an error report.
  void error(
    Object error,
    StackTrace? stackTrace, {
    Map<String, Object?>? context,
  });
}

/// To the debug console only.
class PrintLogger implements EngineLogger {
  const PrintLogger();

  @override
  void warn(String message) => debugPrint('[haul] $message');

  @override
  void error(
    Object error,
    StackTrace? stackTrace, {
    Map<String, Object?>? context,
  }) => debugPrint('[haul] $error ${context ?? ''}\n${stackTrace ?? ''}');
}

/// Optional hooks into the engine's work.
class EngineHooks {
  const EngineHooks({this.onWholeFileTask});

  /// Lets the app dress the task of a file fetched in one request (no
  /// byte ranges): a notification, which on Android is what keeps a long
  /// one running in the foreground.
  final DownloadTask Function(DownloadTask task, DownloadRecord record)?
  onWholeFileTask;
}
