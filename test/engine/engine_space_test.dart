import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

import 'engine_test_support.dart';

/// A download that does not fit fails straight away, before anything is
/// fetched or written.
void main() {
  late Env env;

  setUp(() => env = Env());

  test('a download that does not fit fails as no space, fetching '
      'nothing', () async {
    final engine = await env.engine(freeSpace: () async => 1);
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitForStatus(engine, id, DownloadStatus.failed);

    expect(engine.byId(id)!.error?.code, DownloadErrorCode.noSpace);
    expect(env.transfer.enqueued, isEmpty);
  });

  test('one file needs room for the pieces and the file', () async {
    // Room for the pieces only.
    late int pieces;
    final probe = await env.engine();
    final (id: probeId, outcome: _) = await probe.enqueue(request(key: 'p'));
    await waitForStatus(probe, probeId, DownloadStatus.downloading);
    pieces = probe.byId(probeId)!.progress.totalBytes;
    expect(pieces, greaterThan(0), reason: 'the fixture has a weight');
    await probe.delete(probeId);

    final engine = await env.engine(freeSpace: () async => pieces + 1);
    final package = await engine.enqueue(request(key: 'a'));
    await waitForStatus(engine, package.id, DownloadStatus.downloading);

    final file = await engine.enqueue(
      request(
        key: 'b',
        output: const OutputMode(kind: OutputKind.file),
      ),
    );
    await engine.pause(package.id);
    await waitForStatus(engine, file.id, DownloadStatus.failed);
    expect(engine.byId(file.id)!.error?.code, DownloadErrorCode.noSpace);
  });

  test('unknown free space is not checked', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitForStatus(engine, id, DownloadStatus.downloading);
  });

  test('an export that does not fit leaves the package as it was', () async {
    var free = 1 << 40;
    final engine = await env.engine(freeSpace: () async => free);
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);

    free = 1;
    final error = await engine.export(id);
    expect(error?.code, DownloadErrorCode.noSpace);
    final record = engine.byId(id)!;
    expect(record.status, DownloadStatus.done);
    expect(record.outputKind, OutputKind.package);
    expect(env.ffmpeg.runs, isEmpty);
  });
}
