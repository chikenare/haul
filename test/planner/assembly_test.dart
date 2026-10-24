import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_engine/planner.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MkvArgs.build', () {
    test('maps separate tracks first so their metadata lines up', () {
      final args = MkvArgs.build(
        outputPath: '/out/Movie.mkv',
        title: 'Movie "quoted"',
        inputs: const [
          MuxInput(
            path: '/w/t0/index.m3u8',
            kind: TrackKind.video,
            isHlsPlaylist: true,
          ),
          MuxInput(
            path: '/w/t1/index.m3u8',
            kind: TrackKind.audio,
            language: 'es-419',
            label: 'Español',
            isHlsPlaylist: true,
          ),
          MuxInput(
            path: '/w/t2/index.m3u8',
            kind: TrackKind.audio,
            language: 'en',
            isHlsPlaylist: true,
          ),
          MuxInput(
            path: '/w/t3/0.vtt',
            kind: TrackKind.subtitle,
            language: 'es',
            label: 'Forzados',
            forced: true,
          ),
        ],
      );

      final joined = args.join(' ');
      // Las opciones de la playlist van delante de cada `-i` que la abre.
      expect(
        joined,
        contains(
          '-allowed_extensions ALL -extension_picky 0 '
          '-protocol_whitelist file,crypto,data -i /w/t0/index.m3u8',
        ),
      );
      expect(
        joined,
        isNot(contains('-protocol_whitelist file,crypto,data -i /w/t3/0.vtt')),
      );

      final maps = [
        for (var i = 0; i < args.length; i++)
          if (args[i] == '-map') args[i + 1],
      ];
      expect(maps, ['0:v?', '1:a:0', '2:a:0', '0:a?', '3:s:0', '0:s?', '0:t?']);

      expect(joined, contains('-c copy'));
      expect(joined, contains('-c:s:0 srt'));
      expect(
        joined,
        contains('-metadata:s:a:0 language=spa -metadata:s:a:0 title=Español'),
      );
      expect(joined, contains('-metadata:s:a:1 language=eng'));
      expect(joined, contains('-disposition:a:0 default'));
      expect(joined, contains('-disposition:a:1 0'));
      expect(joined, contains('-disposition:v:0 default'));
      expect(joined, contains('-disposition:s:0 forced'));
      expect(args, contains('title=Movie "quoted"'));
      expect(args.last, '/out/Movie.mkv');
    });

    test('an MP4 source converts all subtitles: mov_text cannot go in MKV', () {
      final args = MkvArgs.build(
        outputPath: '/out/x.mkv',
        inputs: const [
          MuxInput(path: '/w/t0/0.mp4', kind: TrackKind.video),
          MuxInput(
            path: '/w/t1/0.srt',
            kind: TrackKind.subtitle,
            language: 'es',
          ),
        ],
      );
      final joined = args.join(' ');
      expect(joined, contains('-c copy -c:s srt'));
      expect(joined, isNot(contains('-c:s:0 srt')));

      final mkv = MkvArgs.build(
        outputPath: '/out/x.mkv',
        inputs: const [
          MuxInput(path: '/w/t0/0.mkv', kind: TrackKind.video),
          MuxInput(path: '/w/t1/0.srt', kind: TrackKind.subtitle),
        ],
      ).join(' ');
      expect(mkv, isNot(contains('-c:s srt')));
      expect(mkv, contains('-c:s:0 srt'));
    });

    test('maps ISO 639-2 codes', () {
      expect(iso6392('es-419'), 'spa');
      expect(iso6392('pt_BR'), 'por');
      expect(iso6392('spa'), 'spa');
      expect(iso6392('xx'), 'und');
      expect(iso6392('sk'), 'slk');
      expect(iso6392('ger'), 'deu');
    });
  });

  group('TrackAssembler.mergeVtt', () {
    test('joins segments relative to the first timestamp map', () {
      // Mismo mapa en todos: los tiempos ya son del video, no se tocan.
      const first =
          'WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:126000,LOCAL:00:00:00.000\n\n'
          '1\n00:00:01.000 --> 00:00:02.500\nHola\n';
      // Tiempo local reiniciado: este fragmento empieza 10 s después.
      const second =
          'WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:1026000\n\n'
          'NOTE nada\n\n00:01.000 --> 00:02.000 align:start\nAdiós\n';

      final merged = TrackAssembler.mergeVtt([first, second]);

      expect(merged, startsWith('WEBVTT\n\n'));
      expect(merged, contains('1\n00:00:01.000 --> 00:00:02.500\nHola'));
      expect(
        merged,
        contains('00:00:11.000 --> 00:00:12.000 align:start\nAdiós'),
      );
      expect(merged, isNot(contains('NOTE')));
      expect('WEBVTT'.allMatches(merged), hasLength(1));
    });

    test('keeps times as they are without a timestamp map', () {
      final merged = TrackAssembler.mergeVtt([
        'WEBVTT\n\n00:00:05.000 --> 00:00:06.000\nA\n',
      ]);
      expect(merged, contains('00:00:05.000 --> 00:00:06.000\nA'));
    });
  });

  group('TrackAssembler, casos reales', () {
    test('un cue repetido en dos fragmentos sale una vez', () {
      const cue = '00:00:05.000 --> 00:00:07.000\nCruza el corte';
      final merged = TrackAssembler.mergeVtt([
        'WEBVTT\n\n1\n$cue\n',
        'WEBVTT\n\n2\n$cue\n\n00:00:08.000 --> 00:00:09.000\nOtro\n',
      ]);
      expect('Cruza el corte'.allMatches(merged), hasLength(1));
      expect(merged, contains('Otro'));
    });

    test('el PTS que da la vuelta a los 33 bits no da tiempos negativos', () {
      const wrap = 1 << 33;
      final merged = TrackAssembler.mergeVtt([
        'WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:${wrap - 90000},LOCAL:00:00:00.000\n\n'
            '00:00:00.500 --> 00:00:00.900\nAntes\n',
        'WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:90000,LOCAL:00:00:00.000\n\n'
            '00:00:00.500 --> 00:00:00.900\nDespués\n',
      ]);
      // El segundo fragmento empieza 2 s después del primero.
      expect(merged, contains('00:00:02.500 --> 00:00:02.900\nDespués'));
      expect(merged, isNot(contains(RegExp(r'-\d'))));
    });

    test('un VTT en Latin-1 se lee igual', () {
      final bytes = [
        ...'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nNi'.codeUnits,
        0xF1,
        ...'o\n'.codeUnits,
      ];
      expect(TrackAssembler.decodeText(bytes), contains('Niño'));
    });
  });

  group('TrackAssembler, DASH', () {
    Future<Directory> withPieces(List<String> files) async {
      final dir = await Directory.systemTemp.createTemp('track');
      addTearDown(() => dir.delete(recursive: true));
      for (final f in files) {
        await File(p.join(dir.path, f)).writeAsString(f);
      }
      return dir;
    }

    test(
      'con duraciones se lee por playlist, sin pegar los fragmentos',
      () async {
        final dir = await withPieces(['0.mp4', '1.mp4', '2.mp4']);
        final input = await const TrackAssembler().assemble(
          const PlannedTrack(
            kind: TrackKind.video,
            assembly: TrackAssembly.concat,
            pieces: [
              PlannedPiece(url: 'u0', file: '0.mp4'),
              PlannedPiece(url: 'u1', file: '1.mp4', duration: 4),
              PlannedPiece(url: 'u2', file: '2.mp4', duration: 2),
            ],
          ),
          dir,
        );
        expect(input.isHlsPlaylist, isTrue);
        expect(p.basename(input.path), 'index.m3u8');
        expect(File(p.join(dir.path, 'track.mp4')).existsSync(), isFalse);
        expect(
          await File(input.path).readAsString(),
          contains('#EXT-X-MAP:URI="0.mp4"'),
        );
      },
    );

    test('en WebM se pegan como antes', () async {
      final dir = await withPieces(['0.webm', '1.webm']);
      final input = await const TrackAssembler().assemble(
        const PlannedTrack(
          kind: TrackKind.video,
          assembly: TrackAssembly.concat,
          pieces: [
            PlannedPiece(url: 'u0', file: '0.webm'),
            PlannedPiece(url: 'u1', file: '1.webm', duration: 4),
          ],
        ),
        dir,
      );
      expect(input.isHlsPlaylist, isFalse);
      expect(await File(input.path).readAsString(), '0.webm1.webm');
    });
  });
}
