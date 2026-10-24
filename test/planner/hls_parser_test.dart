import 'package:flutter_test/flutter_test.dart';
import 'package:offline_engine/planner.dart';

void main() {
  final base = Uri.parse('https://cdn.example.com/show/master.m3u8?token=abc');

  group('parseMaster', () {
    const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",LANGUAGE="es",NAME="Español",DEFAULT=YES,URI="audio/es.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",LANGUAGE="en",NAME="English, original",URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="es",NAME="Español",FORCED=YES,URI="subs/es.m3u8"
#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",INSTREAM-ID="CC1",NAME="CC"
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud",SUBTITLES="subs"
video/1080.m3u8
#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,URI="iframe.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,AUDIO="aud"
https://other.example.com/720.m3u8
''';

    test('reads variants with resolution, codecs and groups', () {
      expect(HlsParser.isMaster(master), isTrue);
      final parsed = HlsParser.parseMaster(master, base);

      expect(parsed.variants, hasLength(2));
      final best = parsed.variants.first;
      expect(
        best.uri.toString(),
        'https://cdn.example.com/show/video/1080.m3u8',
      );
      expect(best.height, 1080);
      expect(best.width, 1920);
      expect(best.codecs, 'avc1.640028,mp4a.40.2');
      expect(best.audioGroup, 'aud');
      expect(best.subtitleGroup, 'subs');
      expect(
        parsed.variants.last.uri.toString(),
        'https://other.example.com/720.m3u8',
      );
    });

    test('reads audio and subtitle renditions, skipping captions', () {
      final parsed = HlsParser.parseMaster(master, base);
      final audios = parsed.renditionsOf(HlsRenditionType.audio, 'aud');

      expect(audios.map((r) => r.language), ['es', 'en']);
      expect(audios.first.isDefault, isTrue);
      expect(audios.last.name, 'English, original');

      final subs = parsed.renditionsOf(HlsRenditionType.subtitles, 'subs');
      expect(subs.single.forced, isTrue);
      expect(
        subs.single.uri.toString(),
        'https://cdn.example.com/show/subs/es.m3u8',
      );
    });
  });

  group('parseMedia', () {
    final mediaBase = Uri.parse('https://cdn.example.com/show/video/1080.m3u8');

    test('collects segments, init and keys once each, in order', () {
      const text = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-KEY:METHOD=AES-128,URI="https://keys.example.com/k1",IV=0x1
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6.0,
seg0.m4s
#EXT-X-BYTERANGE:1000@0
#EXTINF:4.5,
all.ts
#EXT-X-BYTERANGE:1000@1000
#EXTINF:4.5,
all.ts
#EXT-X-ENDLIST
''';
      final media = HlsParser.parseMedia(text, mediaBase);

      expect(media.resources.map((u) => u.toString()), [
        'https://keys.example.com/k1',
        'https://cdn.example.com/show/video/init.mp4',
        'https://cdn.example.com/show/video/seg0.m4s',
        'https://cdn.example.com/show/video/all.ts',
      ]);
      expect(media.duration, const Duration(seconds: 15));

      final local = media.localPlaylist({
        media.resources[0]: '0.bin',
        media.resources[1]: '1.mp4',
        media.resources[2]: '2.m4s',
        media.resources[3]: '3.ts',
      });
      expect(local, contains('#EXT-X-KEY:METHOD=AES-128,URI="0.bin",IV=0x1'));
      expect(local, contains('#EXT-X-MAP:URI="1.mp4"'));
      expect(local, contains('\n2.m4s\n'));
      expect('\n3.ts\n'.allMatches(local), hasLength(2));
      expect(local, contains('#EXT-X-BYTERANGE:1000@1000'));
      expect(local, isNot(contains('https://')));
    });

    test('an inline data: key stays in the playlist and is not downloaded', () {
      const text =
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="data:text/plain;base64,AAAAAAAAAAAAAAAAAAAAAA=="\n'
          '#EXTINF:4,\na.ts\n#EXT-X-ENDLIST\n';
      final media = HlsParser.parseMedia(text, mediaBase);
      expect(media.resources.single.path, endsWith('/a.ts'));
      expect(
        media.localPlaylist({media.resources.single: '0.ts'}),
        contains('URI="data:text/plain;base64,'),
      );
    });

    test('a live playlist cannot be downloaded', () {
      expect(
        () => HlsParser.parseMedia('#EXTM3U\n#EXTINF:6,\na.ts\n', mediaBase),
        throwsA(
          isA<SourceException>().having(
            (e) => e.code,
            'code',
            SourceErrorCode.live,
          ),
        ),
      );
    });

    test('VOD playlist type counts as finished', () {
      final media = HlsParser.parseMedia(
        '#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:6,\na.ts\n',
        mediaBase,
      );
      expect(media.resources, hasLength(1));
    });

    test('SAMPLE-AES and non-identity key formats are DRM', () {
      for (final key in [
        '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x"',
        '#EXT-X-KEY:METHOD=AES-128,URI="k",KEYFORMAT="com.apple.streamingkeydelivery"',
      ]) {
        expect(
          () => HlsParser.parseMedia(
            '#EXTM3U\n$key\n#EXTINF:6,\na.ts\n#EXT-X-ENDLIST\n',
            mediaBase,
          ),
          throwsA(
            isA<SourceException>().having(
              (e) => e.code,
              'code',
              SourceErrorCode.drm,
            ),
          ),
        );
      }
    });
  });
}
