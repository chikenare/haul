import 'package:flutter_test/flutter_test.dart';
import 'package:haul/ffmpeg.dart';
import 'package:haul/haul.dart';

void main() {
  const video = MuxInput(path: '/d/master.m3u8', kind: TrackKind.video);

  test('seeks only past the start and keeps one scaled frame', () {
    final later = FrameGrabber.buildArgs(
      video,
      '/d/thumb.jpg',
      const Duration(seconds: 60),
    );
    expect(later, containsAllInOrder(['-ss', '60', '-i', '/d/master.m3u8']));
    expect(later.last, '/d/thumb.jpg');
    expect(later, containsAllInOrder(['-frames:v', '1']));

    final start = FrameGrabber.buildArgs(video, '/d/thumb.jpg', Duration.zero);
    expect(start, isNot(contains('-ss')));
  });
}
