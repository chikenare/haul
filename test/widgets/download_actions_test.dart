import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/src/widgets/download_actions.dart';
import 'package:haul/widgets.dart';

DownloadRecord _record(
  DownloadStatus status, {
  DownloadError? error,
  OutputKind? outputKind,
  String? outputLocator,
  DownloadProgress progress = const DownloadProgress(),
}) => DownloadRecord(
  id: 'd1',
  key: 'k',
  title: 'Loki',
  name: const OutputName(baseName: 'Loki'),
  status: status,
  error: error,
  outputKind: outputKind,
  outputLocator: outputLocator,
  progress: progress,
  source: const SourceRequest(url: 'https://cdn.example/a.mpd'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('sourceError: each code of the planner, the rest generic', () {
    const en = HaulStrings();
    const es = HaulStringsEs();
    expect(
      en.sourceError(const SourceException(SourceErrorCode.drm)),
      contains('protected'),
    );
    expect(
      es.sourceError(SourceException(SourceErrorCode.http(404))),
      contains('404'),
    );
    for (final code in [
      SourceErrorCode.drm,
      SourceErrorCode.live,
      SourceErrorCode.empty,
      SourceErrorCode.unsupported,
      SourceErrorCode.network,
      SourceErrorCode.missingPieces,
    ]) {
      expect(
        es.sourceError(SourceException(code)),
        isNot(es.sourceError(StateError('x'))),
        reason: code,
      );
    }
    expect(en.sourceError(StateError('x')), 'Something went wrong.');
  });

  group('DownloadActions', () {
    test('the primary action follows the status', () {
      HaulAction? primary(DownloadStatus s) =>
          DownloadActions.of(_record(s)).primary;

      expect(primary(DownloadStatus.queued), HaulAction.pause);
      expect(primary(DownloadStatus.resolving), HaulAction.pause);
      expect(primary(DownloadStatus.downloading), HaulAction.pause);
      expect(primary(DownloadStatus.paused), HaulAction.resume);
      expect(primary(DownloadStatus.failed), HaulAction.retry);
      expect(primary(DownloadStatus.done), HaulAction.play);
      expect(primary(DownloadStatus.assembling), isNull);
    });

    test('no retry for an error the app says a retry would not change', () {
      final actions = DownloadActions.of(
        _record(
          DownloadStatus.failed,
          error: const DownloadError(code: 'quota'),
        ),
        canRetry: (e) => e.code != 'quota',
      );
      expect(actions.primary, isNull);
      expect(actions.menu, [HaulAction.delete]);
    });

    test('a finished package can become a file', () {
      final actions = DownloadActions.of(
        _record(
          DownloadStatus.done,
          outputKind: OutputKind.package,
          outputLocator: 'work:master.m3u8',
        ),
      );
      expect(actions.menu, [
        HaulAction.play,
        HaulAction.export,
        HaulAction.delete,
      ]);
    });

    test('a published file can leave the list and stay', () {
      final actions = DownloadActions.of(
        _record(
          DownloadStatus.done,
          outputKind: OutputKind.file,
          outputLocator: 'content://media/1',
        ),
      );
      expect(actions.menu, [
        HaulAction.play,
        HaulAction.removeKeepFile,
        HaulAction.delete,
      ]);
    });
  });

  group('downloadSummary', () {
    const en = HaulStrings();

    const half = DownloadProgress(bytes: 1200000000, totalBytes: 3000000000);

    test('only the bytes while it downloads, no state or percent', () {
      expect(
        downloadSummary(
          _record(DownloadStatus.downloading, progress: half),
          en,
        ),
        '1.2 GB / 3.0 GB',
      );
    });

    test('a paused one says so before its bytes', () {
      expect(
        downloadSummary(_record(DownloadStatus.paused, progress: half), en),
        'Paused · 1.2 GB / 3.0 GB',
      );
    });

    test('the state while there are no bytes to show', () {
      expect(
        downloadSummary(_record(DownloadStatus.resolving), en),
        'Preparing',
      );
      expect(
        downloadSummary(_record(DownloadStatus.assembling, progress: half), en),
        'Finishing',
      );
    });

    test('queued, or waiting for Wi-Fi', () {
      expect(downloadSummary(_record(DownloadStatus.queued), en), 'Queued');
      expect(
        downloadSummary(
          _record(DownloadStatus.queued),
          en,
          waitingForWifi: true,
        ),
        'Waiting for Wi-Fi',
      );
    });

    test('a failed one says why', () {
      expect(
        downloadSummary(
          _record(
            DownloadStatus.failed,
            error: const DownloadError(code: 'quota'),
          ),
          const _AppStrings(),
        ),
        'Sin cupo',
      );
    });

    test('a finished one, only its size', () {
      expect(
        downloadSummary(
          _record(
            DownloadStatus.done,
            outputKind: OutputKind.package,
            progress: const DownloadProgress(totalBytes: 500000000),
          ),
          en,
        ),
        '500 MB',
      );
    });
  });

  group('HaulStrings', () {
    test('Spanish for es, English otherwise', () {
      expect(
        HaulStrings.forLocale(const Locale('es', 'AR')),
        isA<HaulStringsEs>(),
      );
      expect(HaulStrings.forLocale(const Locale('fr')).pause, 'Pause');
    });

    test('an app overrides what it wants, app codes included', () {
      const strings = _AppStrings();
      expect(strings.delete, 'Borrar');
      expect(strings.pause, 'Pausar');
      expect(strings.error(const DownloadError(code: 'quota')), 'Sin cupo');
      expect(
        strings.error(const DownloadError(code: DownloadErrorCode.noSpace)),
        'No queda espacio en el dispositivo.',
      );
    });
  });
}

class _AppStrings extends HaulStringsEs {
  const _AppStrings();

  @override
  String get delete => 'Borrar';

  @override
  String error(DownloadError error) =>
      error.code == 'quota' ? 'Sin cupo' : super.error(error);
}
