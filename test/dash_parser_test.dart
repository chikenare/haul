import 'package:media_downloader/media_downloader.dart';
import 'package:test/test.dart';

void main() {
  final manifestUri = Uri.parse(
    'https://cdn.example.com/movie/manifest.mpd?sig=1',
  );

  test(
    'expands SegmentTemplate with \$Number\$ and inherits it from the set',
    () {
      const mpd = '''
<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT10S">
  <Period>
    <AdaptationSet contentType="video" mimeType="video/mp4">
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4" media="\$RepresentationID\$/seg-\$Number%03d\$.m4s"/>
      <Representation id="v1080" bandwidth="5000000" width="1920" height="1080" codecs="avc1.640028"/>
      <Representation id="v720" bandwidth="2000000" width="1280" height="720"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="es">
      <Label>Español</Label>
      <SegmentTemplate timescale="1000" duration="4000" initialization="a/init.mp4" media="a/\$Number\$.m4s"/>
      <Representation id="a1" bandwidth="128000"/>
    </AdaptationSet>
  </Period>
</MPD>''';
      final manifest = DashParser.parse(mpd, manifestUri);

      expect(manifest.duration, const Duration(seconds: 10));
      final video = manifest.ofType(DashContentType.video).first;
      expect(video.height, 1080);
      expect(video.resources.map((u) => u.toString()), [
        'https://cdn.example.com/movie/v1080/init.mp4',
        'https://cdn.example.com/movie/v1080/seg-001.m4s',
        'https://cdn.example.com/movie/v1080/seg-002.m4s',
        'https://cdn.example.com/movie/v1080/seg-003.m4s',
      ]);
      // El último dura lo que le queda al periodo.
      expect(video.segments.map((s) => s.seconds), [null, 4.0, 4.0, 2.0]);

      final audio = manifest.ofType(DashContentType.audio).single;
      expect(audio.language, 'es');
      expect(audio.label, 'Español');
      expect(audio.resources, hasLength(4));
    },
  );

  test('expands SegmentTimeline with \$Time\$ and repeats', () {
    const mpd = '''
<MPD type="static" mediaPresentationDuration="PT8S">
  <BaseURL>https://media.example.com/base/</BaseURL>
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="v" bandwidth="1000" height="480">
        <SegmentTemplate timescale="10" initialization="init-\$Bandwidth\$.mp4" media="t\$Time\$.m4s">
          <SegmentTimeline>
            <S t="0" d="20" r="2"/>
            <S d="20"/>
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
    final rep = DashParser.parse(mpd, manifestUri).representations.single;

    expect(rep.resources.map((u) => u.path.split('/').last), [
      'init-1000.mp4',
      't0.m4s',
      't20.m4s',
      't40.m4s',
      't60.m4s',
    ]);
    expect(rep.resources.first.host, 'media.example.com');
    expect(rep.segments.map((s) => s.seconds), [null, 2.0, 2.0, 2.0, 2.0]);
  });

  test('negative repeat fills up to the end of the period', () {
    const mpd = '''
<MPD type="static" mediaPresentationDuration="PT6S"><Period>
  <AdaptationSet mimeType="audio/mp4"><Representation id="a" bandwidth="1">
    <SegmentTemplate timescale="1" media="\$Number\$.m4s" startNumber="5">
      <SegmentTimeline><S t="0" d="2" r="-1"/></SegmentTimeline>
    </SegmentTemplate>
  </Representation></AdaptationSet>
</Period></MPD>''';
    final rep = DashParser.parse(mpd, manifestUri).representations.single;
    expect(rep.resources.map((u) => u.pathSegments.last), [
      '5.m4s',
      '6.m4s',
      '7.m4s',
    ]);
  });

  test(
    'SegmentBase is a single file and SegmentList ranges collapse to it',
    () {
      const mpd = '''
<MPD type="static" mediaPresentationDuration="PT60S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <Representation id="v" bandwidth="1"><BaseURL>video.mp4</BaseURL>
      <SegmentBase indexRange="0-100"/>
    </Representation>
  </AdaptationSet>
  <AdaptationSet mimeType="audio/mp4">
    <Representation id="a" bandwidth="1"><BaseURL>audio.mp4</BaseURL>
      <SegmentList><Initialization range="0-99"/>
        <SegmentURL mediaRange="100-199"/><SegmentURL mediaRange="200-299"/>
      </SegmentList>
    </Representation>
  </AdaptationSet>
  <AdaptationSet mimeType="text/vtt" lang="en">
    <Representation id="s" bandwidth="1"><BaseURL>subs/en.vtt</BaseURL></Representation>
  </AdaptationSet>
</Period></MPD>''';
      final manifest = DashParser.parse(mpd, manifestUri);

      for (final rep in manifest.representations) {
        expect(rep.resources, hasLength(1), reason: rep.id);
      }
      expect(
        manifest
            .ofType(DashContentType.text)
            .single
            .resources
            .single
            .toString(),
        'https://cdn.example.com/movie/subs/en.vtt',
      );
    },
  );

  test('flags ContentProtection and rejects live and multi-period', () {
    const protectedMpd = '''
<MPD type="static" mediaPresentationDuration="PT4S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc"/>
    <Representation id="v" bandwidth="1"><BaseURL>v.mp4</BaseURL></Representation>
  </AdaptationSet>
</Period></MPD>''';
    expect(
      DashParser.parse(
        protectedMpd,
        manifestUri,
      ).representations.single.isProtected,
      isTrue,
    );

    Matcher code(String code) =>
        throwsA(isA<SourceException>().having((e) => e.code, 'code', code));

    expect(
      () =>
          DashParser.parse('<MPD type="dynamic"><Period/></MPD>', manifestUri),
      code(SourceErrorCode.live),
    );
    expect(
      () => DashParser.parse('<MPD><Period/><Period/></MPD>', manifestUri),
      code(SourceErrorCode.unsupported),
    );
  });

  test('parses ISO 8601 durations', () {
    expect(
      DashParser.parseDuration('PT1H2M3.5S'),
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(
      DashParser.parseDuration('P0DT0H10M0S'),
      const Duration(minutes: 10),
    );
    expect(
      DashParser.parseDuration('PT0.04S'),
      const Duration(milliseconds: 40),
    );
    expect(
      DashParser.parseDuration('P0Y0M0DT0H3M30.5S'),
      const Duration(minutes: 3, seconds: 30, milliseconds: 500),
    );
    expect(DashParser.parseDuration('nope'), isNull);
  });

  test('r="-1" que no es el último S llega hasta el t del siguiente', () {
    const mpd = '''
<MPD type="static" mediaPresentationDuration="PT20S"><Period>
  <AdaptationSet mimeType="video/mp4"><Representation id="v" bandwidth="1">
    <SegmentTemplate timescale="1" media="s\$Time\$.m4s">
      <SegmentTimeline><S t="0" d="2" r="-1"/><S t="10" d="5" r="1"/></SegmentTimeline>
    </SegmentTemplate>
  </Representation></AdaptationSet>
</Period></MPD>''';
    final rep = DashParser.parse(mpd, manifestUri).representations.single;
    expect(rep.resources.map((u) => u.pathSegments.last), [
      's0.m4s',
      's2.m4s',
      's4.m4s',
      's6.m4s',
      's8.m4s',
      's10.m4s',
      's15.m4s',
    ]);
  });

  test(
    'un SegmentList en la representación gana a la plantilla del periodo',
    () {
      const mpd = '''
<MPD type="static" mediaPresentationDuration="PT4S"><Period>
  <SegmentTemplate timescale="1" duration="2" media="t\$Number\$.m4s"/>
  <AdaptationSet mimeType="video/mp4"><Representation id="v" bandwidth="1">
    <SegmentList><SegmentURL media="a.m4s"/><SegmentURL media="b.m4s"/></SegmentList>
  </Representation></AdaptationSet>
</Period></MPD>''';
      final rep = DashParser.parse(mpd, manifestUri).representations.single;
      expect(rep.resources.map((u) => u.pathSegments.last), ['a.m4s', 'b.m4s']);
    },
  );

  test('las AdaptationSet de avance rápido no son una calidad', () {
    const mpd = '''
<MPD type="static" mediaPresentationDuration="PT4S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <Representation id="v" bandwidth="1" height="720"><BaseURL>v.mp4</BaseURL></Representation>
  </AdaptationSet>
  <AdaptationSet mimeType="video/mp4">
    <EssentialProperty schemeIdUri="http://dashif.org/guidelines/trickmode" value="1"/>
    <Representation id="t" bandwidth="1" height="144"><BaseURL>t.mp4</BaseURL></Representation>
  </AdaptationSet>
</Period></MPD>''';
    expect(
      DashParser.parse(mpd, manifestUri).representations.map((r) => r.id),
      ['v'],
    );
  });
}
