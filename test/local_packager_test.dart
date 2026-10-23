import 'dart:io';

import 'package:media_downloader/media_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  PlannedPiece piece(String file, [double? duration]) =>
      PlannedPiece(url: 'https://cdn/$file', file: file, duration: duration);

  final dashVideo = PlannedTrack(
    kind: TrackKind.video,
    assembly: TrackAssembly.concat,
    codecs: 'avc1.640028',
    pieces: [piece('0.mp4'), piece('1.mp4', 4), piece('2.mp4', 1.5)],
  );
  final dashAudio = PlannedTrack(
    kind: TrackKind.audio,
    assembly: TrackAssembly.concat,
    language: 'es-419',
    label: 'Español "Latino"',
    codecs: 'mp4a.40.2',
    pieces: [piece('0.mp4'), piece('1.mp4', 4), piece('2.mp4', 1.5)],
  );

  group('supports', () {
    test('HLS y DASH en MP4 con duraciones', () {
      expect(
        LocalPackager.supports(
          DownloadPlan(extension: 'mkv', tracks: [dashVideo, dashAudio]),
        ),
        isTrue,
      );
      expect(
        LocalPackager.supports(
          const DownloadPlan(
            extension: 'mkv',
            tracks: [
              PlannedTrack(
                kind: TrackKind.video,
                assembly: TrackAssembly.hlsPlaylist,
                pieces: [],
                playlist: '#EXTM3U',
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('ni WebM, ni DASH sin duraciones, ni un archivo directo', () {
      final webm = dashVideo.copyWith(
        pieces: [piece('0.webm'), piece('1.webm', 4)],
      );
      final untimed = dashVideo.copyWith(
        pieces: [piece('0.mp4'), piece('1.mp4'), piece('2.mp4')],
      );
      final file = PlannedTrack(
        kind: TrackKind.video,
        assembly: TrackAssembly.single,
        pieces: [piece('0.mp4')],
      );
      for (final video in [webm, untimed, file]) {
        expect(
          LocalPackager.supports(
            DownloadPlan(extension: 'mkv', tracks: [video]),
          ),
          isFalse,
        );
      }
    });
  });

  test('la playlist de DASH usa la inicialización como EXT-X-MAP', () {
    final playlist = dashVideo.segmentPlaylist;
    expect(playlist, contains('#EXT-X-TARGETDURATION:4\n'));
    expect(playlist, contains('#EXT-X-MAP:URI="0.mp4"\n'));
    expect(playlist, contains('#EXTINF:4.000,\n1.mp4\n#EXTINF:1.500,\n2.mp4'));
    expect(playlist, endsWith('#EXT-X-ENDLIST\n'));
    expect(LocalPackager.playlistSeconds(playlist), 5.5);
  });

  test('un archivo DASH entero es un solo fragmento, sin EXT-X-MAP', () {
    final playlist = dashVideo
        .copyWith(
          assembly: TrackAssembly.single,
          pieces: [piece('0.mp4', 7200)],
        )
        .segmentPlaylist;
    expect(playlist, isNot(contains('EXT-X-MAP')));
    expect(playlist, contains('#EXTINF:7200.000,\n0.mp4'));
  });

  test('la master une video y audios', () {
    final master = LocalPackager.masterPlaylist(
      video: 't0/index.m3u8',
      videoTrack: dashVideo.copyWith(codecs: 'avc1.640028,wvtt'),
      audios: [
        ('t1/index.m3u8', dashAudio),
        ('t2/index.m3u8', dashAudio.copyWith(label: null, language: null)),
      ],
      bandwidth: 2500000,
    );
    expect(
      master,
      contains(
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Español \'Latino\'",'
        'LANGUAGE="es-419",DEFAULT=YES,AUTOSELECT=YES,URI="t1/index.m3u8"',
      ),
    );
    expect(master, contains('NAME="Audio 2",DEFAULT=NO'));
    expect(
      master,
      contains(
        '#EXT-X-STREAM-INF:BANDWIDTH=2500000,'
        'CODECS="avc1.640028,mp4a.40.2",AUDIO="audio"\nt0/index.m3u8',
      ),
    );
  });

  test('escribe el paquete y guarda los subtítulos aparte', () async {
    final dir = await Directory.systemTemp.createTemp('package');
    addTearDown(() => dir.delete(recursive: true));
    for (final (t, files) in [
      (0, ['0.mp4', '1.mp4', '2.mp4']),
      (1, ['0.mp4', '1.mp4', '2.mp4']),
      (2, ['0.vtt']),
    ]) {
      for (final f in files) {
        await File(p.join(dir.path, 't$t', f)).create(recursive: true);
      }
    }
    await File(
      p.join(dir.path, 't2', '0.vtt'),
    ).writeAsString('WEBVTT\n\n00:00.000 --> 00:01.000\nHola\n');

    final package = await const LocalPackager().package(
      DownloadPlan(
        extension: 'mkv',
        expectedBytes: 1000,
        tracks: [
          dashVideo,
          dashAudio,
          PlannedTrack(
            kind: TrackKind.subtitle,
            assembly: TrackAssembly.single,
            pieces: [piece('0.vtt')],
            language: 'es',
            label: 'Español',
          ),
        ],
      ),
      dir,
    );

    expect(package.masterPath, p.join(dir.path, 'master.m3u8'));
    expect(package.video.path, p.join(dir.path, 't0', 'index.m3u8'));
    expect(package.video.isHlsPlaylist, isTrue);
    expect(
      await File(package.masterPath).readAsString(),
      isNot(contains('SUBTITLES')),
    );
    expect(File(p.join(dir.path, 't1', 'index.m3u8')).existsSync(), isTrue);

    final subtitles = await LocalPackager.subtitlesOf(package.masterPath);
    expect(subtitles.single.path, p.join(dir.path, 't2', '0.vtt'));
    expect(subtitles.single.label, 'Español');
    expect(subtitles.single.language, 'es');
  });
}
