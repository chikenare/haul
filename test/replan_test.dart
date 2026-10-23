import 'dart:convert';

import 'package:media_downloader/media_downloader.dart';
import 'package:test/test.dart';

/// A DASH like the ones a signed CDN mints: the token rides the query of
/// every segment, so a fresh mint changes every URL and nothing else.
String _mpd(String token) =>
    '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT8S">
  <Period>
    <AdaptationSet contentType="video" mimeType="video/mp4">
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="v1080" height="1080" bandwidth="4000000" codecs="av01.0.08M.08"/>
      <Representation id="v720" height="720" bandwidth="2000000" codecs="av01.0.05M.08"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="es-419">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="main"/>
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="a-lat" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en">
      <Role schemeIdUri="urn:mpeg:dash:role:2011" value="dub"/>
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
        initialization="\$RepresentationID\$/init.mp4?t=$token"
        media="\$RepresentationID\$/\$Number\$.m4s?t=$token"/>
      <Representation id="a-en" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
  </Period>
</MPD>''';

Future<DownloadPlan> _plan(String token, TrackCriteria criteria) async {
  final source = DashSource(
    const SourceRequest(url: 'https://cdn.example.com/v/manifest.mpd'),
    DashParser.parse(
      _mpd(token),
      Uri.parse('https://cdn.example.com/v/manifest.mpd'),
    ),
  );
  return source.plan(source.selectionFor(criteria));
}

void main() {
  const criteria = TrackCriteria(
    maxHeight: 720,
    audio: LanguageTracks(['es-419']),
  );

  test('every planned track names what it was planned from', () async {
    final plan = await _plan('a', criteria);

    expect(
      [for (final t in plan.tracks) (t.kind, t.sourceId)],
      [(TrackKind.video, 'v720'), (TrackKind.audio, 'a-lat')],
    );
  });

  test('a fresh mint plans the same files under new URLs', () async {
    final before = await _plan('expired', criteria);
    final after = await _plan('fresh', criteria);

    List<String> files(DownloadPlan plan) => [
      for (final t in plan.tracks)
        '${t.sourceId}: ${[for (final p in t.pieces) p.file].join(',')}',
    ];
    // Same tracks and the same local names: the pieces already on disk
    // still count, only the missing ones are fetched from the new links.
    expect(files(after), files(before));
    expect(after.tracks.first.pieces.first.url, contains('t=fresh'));
  });

  test('the plan survives a round trip through plan.json', () async {
    final plan = await _plan('a', criteria);
    final json = jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;

    expect(DownloadPlan.fromJson(json), plan);
  });

  test('an MP4 DASH plan is packaged as local HLS', () async {
    final plan = await _plan('a', criteria);

    expect(LocalPackager.supports(plan), isTrue);
    final video = plan.tracks.first;
    expect(video.hasSegmentPlaylist, isTrue);
    expect(video.segmentPlaylist, contains('#EXT-X-MAP:URI="0.mp4"'));
  });
}
