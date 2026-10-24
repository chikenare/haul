import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

/// Through text, as `record.json` does: nested values come back as plain
/// maps and lists, not as the objects that went in.
DownloadRecord _roundTrip(DownloadRecord record) => DownloadRecord.fromJson(
  jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
);

DownloadRecord _record({
  TrackChoice tracks = const TrackChoice.policy(),
  OutputMode output = OutputMode.package,
}) => DownloadRecord(
  id: 'd1',
  key: 'episode:42',
  title: 'Loki S01E01',
  name: const OutputName(baseName: 'Loki S01E01', folders: ['Loki', 'S01']),
  status: DownloadStatus.queued,
  source: const SourceRequest(url: 'https://cdn.example.com/master.m3u8'),
  tracks: tracks,
  output: output,
  createdAt: DateTime.utc(2026, 10, 1, 12),
  updatedAt: DateTime.utc(2026, 10, 1, 12, 5),
);

void main() {
  group('DownloadRecord JSON', () {
    test('with every TrackChoice', () {
      final choices = <TrackChoice>[
        const TrackChoice.policy(),
        const TrackChoice.criteria(
          TrackCriteria(
            maxHeight: 720,
            audio: LanguageTracks(['es-419', 'en']),
            subtitles: NoTracks(),
          ),
        ),
        const TrackChoice.selection(
          SourceSelection(
            videoId: 'v1080',
            audioIds: {'a-es', 'a-en'},
            subtitleIds: {'s-es'},
          ),
          fallback: TrackCriteria(maxHeight: 1080),
        ),
        const TrackChoice.selection(SourceSelection()),
      ];

      for (final choice in choices) {
        final back = _roundTrip(_record(tracks: choice));
        expect(back.tracks, choice, reason: '$choice');
        expect(back, _record(tracks: choice));
      }
    });

    test('with each OutputMode', () {
      for (final output in [
        OutputMode.package,
        OutputMode.file,
        const OutputMode(kind: OutputKind.file, subtitleSidecars: true),
      ]) {
        expect(_roundTrip(_record(output: output)).output, output);
      }
    });

    test('with everything set', () {
      final record = _record().copyWith(
        status: DownloadStatus.failed,
        error: const DownloadError(
          code: DownloadErrorCode.http,
          message: 'Forbidden',
          httpStatus: 403,
        ),
        source: const SourceRequest(
          url: 'https://cdn.example.com/a.mp4',
          headers: {'Referer': 'https://example.com'},
          subtitles: {'Español': 'https://cdn.example.com/es.vtt'},
        ),
        metadata: {
          'season': 1,
          'tags': ['a', 'b'],
          'nested': {'x': null, 'y': 1.5},
        },
        expiresAt: DateTime.utc(2026, 10, 2),
        linkDead: true,
        outputLocator: '/storage/Loki S01E01.mkv',
        outputKind: OutputKind.file,
        stagedPath: 'work:output.mkv',
        progress: const DownloadProgress(
          donePieces: 3,
          totalPieces: 10,
          bytes: 100,
          totalBytes: 1000,
          segmented: true,
        ),
      );

      expect(_roundTrip(record), record);
    });

    test('with the nullable fields null', () {
      final back = _roundTrip(_record());
      expect(back.error, isNull);
      expect(back.expiresAt, isNull);
      expect(back.outputLocator, isNull);
      expect(back.outputKind, isNull);
      expect(back.stagedPath, isNull);
      expect(back.source.headers, isNull);
      expect(back.source.subtitles, isNull);
    });

    test('a local date stays a local date', () {
      final local = DateTime(2026, 10, 1, 9, 30, 15, 123);
      final back = _roundTrip(
        _record().copyWith(createdAt: local, expiresAt: local),
      );
      expect(back.createdAt, local);
      expect(back.expiresAt, local);
    });

    test('missing optional keys take their defaults', () {
      final json =
          jsonDecode(jsonEncode(_record().toJson())) as Map<String, Object?>
            ..remove('tracks')
            ..remove('output')
            ..remove('progress')
            ..remove('linkDead')
            ..remove('metadata');

      final back = DownloadRecord.fromJson(json);
      expect(back.tracks, const TrackChoice.policy());
      expect(back.output, OutputMode.package);
      expect(back.progress, const DownloadProgress());
      expect(back.linkDead, isFalse);
      expect(back.metadata, isEmpty);
    });
  });

  group('TrackChoice.fromJson', () {
    test('a selection without fallback takes the default one', () {
      final choice = TrackChoice.fromJson({
        'type': 'selection',
        'selection': {
          'videoId': 'v',
          'audioIds': ['a'],
        },
      });
      expect(
        choice,
        const TrackChoice.selection(
          SourceSelection(videoId: 'v', audioIds: {'a'}),
        ),
      );
    });

    test('an unknown type is the policy', () {
      expect(
        TrackChoice.fromJson({'type': 'future'}),
        const TrackChoice.policy(),
      );
    });

    test('no languages survive the trip', () {
      const choice = TrackChoice.criteria(
        TrackCriteria(audio: LanguageTracks([])),
      );
      expect(
        TrackChoice.fromJson(
          jsonDecode(jsonEncode(choice.toJson())) as Map<String, Object?>,
        ),
        choice,
      );
    });
  });

  group('SourceRequest', () {
    test('equal whatever the order of its maps', () {
      const a = SourceRequest(url: 'u', headers: {'a': '1', 'b': '2'});
      const b = SourceRequest(url: 'u', headers: {'b': '2', 'a': '1'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const SourceRequest(url: 'u', headers: {'a': '1'})));
      expect(a, isNot(const SourceRequest(url: 'u')));
    });

    test('leaves absent maps out of its JSON', () {
      expect(const SourceRequest(url: 'u').toJson(), {'url': 'u'});
    });
  });

  group('DownloadProgress.fraction', () {
    test('null before there is anything to measure', () {
      expect(const DownloadProgress().fraction, isNull);
      expect(const DownloadProgress(segmented: true).fraction, isNull);
      expect(
        const DownloadProgress(bytes: 5, segmented: true).fraction,
        isNull,
      );
    });

    test('by bytes for whole files', () {
      expect(
        const DownloadProgress(
          bytes: 25,
          totalBytes: 100,
          donePieces: 9,
          totalPieces: 10,
        ).fraction,
        0.25,
      );
    });

    test('by pieces for fragmented sources', () {
      expect(
        const DownloadProgress(
          donePieces: 3,
          totalPieces: 4,
          bytes: 1,
          totalBytes: 100,
          segmented: true,
        ).fraction,
        0.75,
      );
    });

    test('never past 1: an estimated weight is often short', () {
      expect(const DownloadProgress(bytes: 150, totalBytes: 100).fraction, 1.0);
    });
  });
}
