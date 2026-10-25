import 'package:haul/haul.dart';

/// Something the example can download.
class SampleItem {
  const SampleItem({
    required this.key,
    required this.title,
    required this.url,
    this.kind = '',
    this.imageUrl,
    this.group,
    this.section,
    this.order,
  });

  final String key;
  final String title;
  final String url;

  /// What it exercises: `HLS`, `DASH`, `MP4 in ranges`…
  final String kind;
  final String? imageUrl;
  final DownloadGroup? group;
  final String? section;
  final num? order;

  OutputName get name => OutputName(
    baseName: group == null
        ? title
        : '${group!.title} S${section ?? '0'}E${order ?? 0} - $title',
    folders: [
      if (group != null) ...[group!.title, 'Season ${section ?? '0'}'],
    ],
  );

  DownloadRequest request(OutputMode output) => DownloadRequest(
    key: key,
    title: title,
    name: name,
    source: SourceRequest(url: url),
    output: output,
    group: group,
    section: section,
    order: order,
    imageUrl: imageUrl,
  );
}

const _poster =
    'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg';

/// No picture of its own: its rows show a frame of each episode.
const clips = DownloadGroup(id: 'clips', title: 'Test clips');

/// Public test streams, free to download.
const movies = [
  SampleItem(
    key: 'bbb-hls',
    title: 'Big Buck Bunny',
    kind: 'HLS (TS), several qualities',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    imageUrl: _poster,
  ),
  SampleItem(
    key: 'angel-one-dash',
    title: 'Angel One',
    kind: 'DASH, several audios and subtitles',
    url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
  ),
  SampleItem(
    key: 'bbb-720-mp4',
    title: 'Big Buck Bunny 720p',
    kind: 'MP4 of 30 MB, fetched in 16 MB ranges',
    url: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_30MB.mp4',
    imageUrl: _poster,
  ),
];

/// One "show" in two seasons, to see grouping.
const episodes = [
  SampleItem(
    key: 'clip-bbb',
    title: 'Bunny',
    kind: 'MP4',
    url: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
    group: clips,
    section: '1',
    order: 1,
  ),
  SampleItem(
    key: 'clip-jellyfish',
    title: 'Jellyfish',
    kind: 'MP4',
    url: 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/360/Jellyfish_360_10s_1MB.mp4',
    group: clips,
    section: '1',
    order: 2,
  ),
  SampleItem(
    key: 'clip-sintel',
    title: 'Sintel',
    kind: 'MP4',
    url: 'https://test-videos.co.uk/vids/sintel/mp4/h264/360/Sintel_360_10s_1MB.mp4',
    group: clips,
    section: '1',
    order: 3,
  ),
  SampleItem(
    key: 'clip-bipbop',
    title: 'Bipbop',
    kind: 'HLS fMP4, audios and subtitles',
    url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    group: clips,
    section: '2',
    order: 1,
  ),
  SampleItem(
    key: 'clip-angel-hls',
    title: 'Angel One',
    kind: 'HLS',
    url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8',
    group: clips,
    section: '2',
    order: 2,
  ),
];
