import 'package:flutter_test/flutter_test.dart';
import 'package:haul/planner.dart';

/// Los manifiestos casi nunca traen URLs completas: se resuelven contra la
/// URL del propio manifiesto (la final, tras redirecciones).
void main() {
  final base = Uri.parse(
    'https://cdn.example.com/vod/movie/master.m3u8?token=abc',
  );

  test('HLS: relative, root-relative and protocol-relative paths', () {
    const master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="es",URI="/audio/es/index.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360,AUDIO="a"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1280x720,AUDIO="a"
//other-cdn.example.com/720/index.m3u8
''';
    final parsed = HlsParser.parseMaster(master, base);
    expect(parsed.variants.map((v) => v.uri.toString()), [
      'https://cdn.example.com/vod/movie/360/index.m3u8',
      'https://other-cdn.example.com/720/index.m3u8',
    ]);
    expect(
      parsed.renditions.single.uri.toString(),
      'https://cdn.example.com/audio/es/index.m3u8',
    );

    final media = HlsParser.parseMedia(
      '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="../keys/k.bin"\n'
      '#EXTINF:4,\nseg-0.ts\n#EXTINF:4,\n/abs/seg-1.ts\n#EXT-X-ENDLIST\n',
      Uri.parse('https://cdn.example.com/vod/movie/360/index.m3u8'),
    );
    expect(media.resources.map((u) => u.toString()), [
      'https://cdn.example.com/vod/movie/keys/k.bin',
      'https://cdn.example.com/vod/movie/360/seg-0.ts',
      'https://cdn.example.com/abs/seg-1.ts',
    ]);
  });

  test('DASH: segments with no BaseURL, or a relative/root BaseURL', () {
    const mpd = '''<MPD type="static" mediaPresentationDuration="PT4S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <SegmentTemplate timescale="1" duration="4" initialization="v/init.mp4" media="v/\$Number\$.m4s"/>
    <Representation id="v" bandwidth="1"/>
  </AdaptationSet>
  <AdaptationSet mimeType="audio/mp4"><BaseURL>/shared/audio/</BaseURL>
    <SegmentTemplate timescale="1" duration="4" initialization="init.mp4" media="\$Number\$.m4s"/>
    <Representation id="a" bandwidth="1"/>
  </AdaptationSet>
</Period></MPD>''';
    final manifest = DashParser.parse(
      mpd,
      Uri.parse('https://cdn.example.com/vod/movie/manifest.mpd'),
    );
    expect(manifest.representations.first.resources.map((u) => u.toString()), [
      'https://cdn.example.com/vod/movie/v/init.mp4',
      'https://cdn.example.com/vod/movie/v/1.m4s',
    ]);
    expect(manifest.representations.last.resources.map((u) => u.toString()), [
      'https://cdn.example.com/shared/audio/init.mp4',
      'https://cdn.example.com/shared/audio/1.m4s',
    ]);
  });
}
