import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/planner.dart';
import 'package:path/path.dart' as p;

const _mb16 = 16 * 1024 * 1024;
const _url = 'https://cdn.example.com/dl/movie';

/// An MP4 head, as the resolver would have read it.
FileSource _file(
  int? length, {
  String? acceptRanges = 'bytes',
  String? etag = '"abc"',
  Map<String, String>? subtitles,
}) => FileSource(
  SourceRequest(url: _url, subtitles: subtitles),
  FetchedResponse(
    url: Uri.parse(_url),
    headers: {
      'content-type': 'video/mp4',
      'content-length': ?length?.toString(),
      'accept-ranges': ?acceptRanges,
      'etag': ?etag,
    },
    body: [0, 0, 0, 0x18, ...'ftypisom'.codeUnits],
    truncated: true,
  ),
);

Future<DownloadPlan> _plan(FileSource source) =>
    source.plan(source.defaultSelection);

void main() {
  group('FileSource.plan', () {
    test('exactly 16 MB is one request', () async {
      final plan = await _plan(_file(_mb16));
      final track = plan.tracks.single;

      expect(track.assembly, TrackAssembly.single);
      expect(track.pieces.single.file, '0.mp4');
      expect(track.pieces.single.rangeHeader, isNull);
      expect(track.ifRange, isNull);
      expect(track.fileExtension, isNull);
    });

    test('16 MB + 1 is two ranges, the last of one byte', () async {
      final plan = await _plan(_file(_mb16 + 1));
      final track = plan.tracks.single;

      expect(track.assembly, TrackAssembly.ranges);
      expect(
        [for (final piece in track.pieces) piece.file],
        ['0.part', '1.part'],
      );
      expect(track.pieces[0].rangeStart, 0);
      expect(track.pieces[0].rangeEnd, _mb16 - 1);
      expect(track.pieces[0].rangeHeader, 'bytes=0-${_mb16 - 1}');
      expect(track.pieces[0].expectedBytes, _mb16);
      expect(track.pieces[1].rangeHeader, 'bytes=$_mb16-$_mb16');
      expect(track.pieces[1].expectedBytes, 1);
      expect(track.pieces.every((piece) => piece.url == _url), isTrue);
      expect(track.fileExtension, 'mp4');
      expect(plan.extension, 'mp4');
      expect(plan.expectedBytes, _mb16 + 1);
    });

    test('the last range ends at the last byte and they add up', () async {
      const length = 40 * 1024 * 1024 + 5;
      final track = (await _plan(_file(length))).tracks.single;

      expect(track.pieces, hasLength(3));
      expect(track.pieces.last.rangeEnd, length - 1);
      expect(
        track.pieces.fold<int>(0, (sum, piece) => sum + piece.expectedBytes!),
        length,
      );
      for (var i = 1; i < track.pieces.length; i++) {
        expect(
          track.pieces[i].rangeStart,
          track.pieces[i - 1].rangeEnd! + 1,
          reason: 'ranges are contiguous',
        );
      }
    });

    test('without accept-ranges a big file is one request', () async {
      for (final header in [null, 'none']) {
        final track = (await _plan(
          _file(_mb16 * 4, acceptRanges: header),
        )).tracks.single;
        expect(track.assembly, TrackAssembly.single, reason: '$header');
        expect(track.ifRange, isNull);
      }
    });

    test('without a content-length it is one request', () async {
      final track = (await _plan(_file(null))).tracks.single;
      expect(track.assembly, TrackAssembly.single);
    });

    test('only a strong ETag becomes If-Range', () async {
      final strong = await _plan(_file(_mb16 * 2, etag: '"v1"'));
      expect(strong.tracks.single.ifRange, '"v1"');

      final weak = await _plan(_file(_mb16 * 2, etag: 'W/"v1"'));
      expect(weak.tracks.single.assembly, TrackAssembly.ranges);
      expect(weak.tracks.single.ifRange, isNull);

      final none = await _plan(_file(_mb16 * 2, etag: null));
      expect(none.tracks.single.ifRange, isNull);
    });

    test('a ranged plan survives plan.json', () async {
      final plan = await _plan(_file(_mb16 * 2 + 3));
      final back = DownloadPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>,
      );
      expect(back, plan);
    });
  });

  group('rangeHeader', () {
    test('open-ended when there is no end', () {
      const piece = PlannedPiece(url: _url, file: '0.part', rangeStart: 5);
      expect(piece.rangeHeader, 'bytes=5-');
      expect(piece.expectedBytes, isNull);
    });
  });

  group('DownloadPlan', () {
    test('a lone ranges track needs no mux; with subtitles it does', () async {
      expect((await _plan(_file(_mb16 * 2))).needsMux, isFalse);

      final withSubs = await _plan(
        _file(_mb16 * 2, subtitles: {'Español': 'https://x/es.vtt'}),
      );
      expect(withSubs.tracks.first.assembly, TrackAssembly.ranges);
      expect(withSubs.needsMux, isTrue);
      expect(withSubs.extension, 'mkv');
      expect(withSubs.tracks.first.fileExtension, 'mp4');
    });

    test('linesUpWith a fresh link of the same file', () async {
      final old = await _plan(_file(_mb16 * 2));
      final fresh = await FileSource(
        const SourceRequest(url: '$_url?sig=new'),
        _file(_mb16 * 2).response,
      ).plan(const SourceSelection());

      expect(old.linesUpWith(fresh), isTrue);
    });

    test('a changed size does not line up, even with as many ranges', () async {
      final old = await _plan(_file(_mb16 * 2));
      final grown = await _plan(_file(_mb16 * 2 + 1));
      final shrunk = await _plan(_file(_mb16 * 2 - 1));

      expect(
        old.tracks.single.pieces.length,
        shrunk.tracks.single.pieces.length,
      );
      expect(old.linesUpWith(grown), isFalse);
      expect(old.linesUpWith(shrunk), isFalse);
    });

    test('a changed ETag does not line up at the same size', () async {
      final old = await _plan(_file(_mb16 * 2, etag: '"v1"'));
      final changed = await _plan(_file(_mb16 * 2, etag: '"v2"'));
      final unknown = await _plan(_file(_mb16 * 2, etag: null));

      expect(old.linesUpWith(changed), isFalse);
      // Nothing to compare against: the size decides.
      expect(old.linesUpWith(unknown), isTrue);
    });

    test('a ranged plan cannot be a local package', () async {
      expect(LocalPackager.supports(await _plan(_file(_mb16 * 2))), isFalse);
    });
  });

  group('TrackAssembler ranges', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ranges_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    PlannedTrack track({String? fileExtension = 'mkv'}) => PlannedTrack(
      kind: TrackKind.video,
      assembly: TrackAssembly.ranges,
      fileExtension: fileExtension,
      pieces: const [
        PlannedPiece(url: _url, file: '0.part', rangeStart: 0, rangeEnd: 3),
        PlannedPiece(url: _url, file: '1.part', rangeStart: 4, rangeEnd: 5),
      ],
    );

    Future<void> write(String name, List<int> bytes) =>
        File(p.join(dir.path, name)).writeAsBytes(bytes);

    test('joins the ranges in order', () async {
      await write('0.part', [1, 2, 3, 4]);
      await write('1.part', [5, 6]);

      final input = await const TrackAssembler().assemble(track(), dir);

      expect(p.basename(input.path), 'track.mkv');
      expect(await File(input.path).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(input.kind, TrackKind.video);
      expect(input.isHlsPlaylist, isFalse);
    });

    test('without an extension the joined file is .bin', () async {
      await write('0.part', [1, 2, 3, 4]);
      await write('1.part', [5, 6]);

      final input = await const TrackAssembler().assemble(
        track(fileExtension: null),
        dir,
      );
      expect(p.basename(input.path), 'track.bin');
    });

    test('a range of the wrong size is missing pieces', () async {
      // A server that ignored the range and answered the whole file.
      await write('0.part', [1, 2, 3, 4, 5, 6]);
      await write('1.part', [5, 6]);

      await expectLater(
        const TrackAssembler().assemble(track(), dir),
        throwsA(
          isA<SourceException>()
              .having((e) => e.code, 'code', SourceErrorCode.missingPieces)
              .having((e) => e.detail, 'detail', endsWith('0.part')),
        ),
      );
      expect(File(p.join(dir.path, 'track.mkv')).existsSync(), isFalse);
    });

    test('a missing range is missing pieces', () async {
      await write('0.part', [1, 2, 3, 4]);

      await expectLater(
        const TrackAssembler().assemble(track(), dir),
        throwsA(
          isA<SourceException>().having(
            (e) => e.code,
            'code',
            SourceErrorCode.missingPieces,
          ),
        ),
      );
    });
  });
}
