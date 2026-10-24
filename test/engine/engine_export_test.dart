import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';
import 'package:haul/testing.dart';
import 'package:path/path.dart' as p;

import 'engine_test_support.dart';

void main() {
  late Env env;
  late Directory out;

  setUp(() {
    env = Env();
    out = Directory(p.join(env.dir.path, 'Movies'));
  });

  /// A finished package of the fixture's DASH.
  Future<String> package(DownloadEngine engine) async {
    final (:id, outcome: _) = await engine.enqueue(request());
    await waitUntil(() => env.transfer.enqueued.length == 6);
    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
    return id;
  }

  test('a package becomes one file in the sink, under the name asked for, '
      'and its pieces go', () async {
    final sink = RecordingSink(DirectorySink(() async => out.path));
    final engine = await env.engine(sink: sink);
    final id = await package(engine);

    final error = await engine.export(
      id,
      name: const OutputName(baseName: 'Exportada', folders: ['Cine']),
    );

    expect(error, isNull);
    final record = engine.byId(id)!;
    final expected = p.join(out.path, 'Cine', 'Exportada.mkv');
    expect(record.status, DownloadStatus.done);
    expect(record.outputKind, OutputKind.file);
    expect(record.outputLocator, expected);
    expect(record.name.baseName, 'Exportada');
    expect(File(expected).existsSync(), isTrue);
    expect(record.progress.bytes, File(expected).lengthSync());
    expect(env.ffmpeg.runs, hasLength(1));
    expect(env.transfer.enqueued, hasLength(6), reason: 'nothing fetched');
    expect(Directory(p.join(env.work(id), 't0')).existsSync(), isFalse);
    expect(File(p.join(env.work(id), 'master.m3u8')).existsSync(), isFalse);
  });

  test('without a name, the record\'s', () async {
    final engine = await env.engine(sink: DirectorySink(() async => out.path));
    final id = await package(engine);

    await engine.export(id);
    expect(
      engine.byId(id)!.outputLocator,
      p.join(out.path, 'La Película (2026).mkv'),
    );
  });

  test('a failed merge leaves the package whole, done, and playing', () async {
    final engine = await env.engine(
      ffmpeg: FakeFfmpeg(error: const FfmpegException('Invalid data')),
    );
    final id = await package(engine);
    final before = engine.byId(id)!;

    final error = await engine.export(
      id,
      name: const OutputName(baseName: 'Otra'),
    );

    expect(error?.code, DownloadErrorCode.mux);
    final record = engine.byId(id)!;
    expect(record.status, DownloadStatus.done);
    expect(record.outputKind, OutputKind.package);
    expect(record.outputLocator, before.outputLocator);
    expect(record.output, OutputMode.package);
    expect(record.name, before.name);
    expect(File(engine.outputPath(record)!).existsSync(), isTrue);
    expect(Directory(p.join(env.work(id), 't0')).existsSync(), isTrue);
  });

  test(
    'a failed publish fails the download, and a retry only publishes',
    () async {
      final sink = RecordingSink(
        DirectorySink(() async => out.path),
        failures: 1,
      );
      final engine = await env.engine(sink: sink);
      final id = await package(engine);

      final error = await engine.export(id);
      expect(error?.code, DownloadErrorCode.publish);
      expect(engine.byId(id)!.status, DownloadStatus.failed);

      await engine.retry(id);
      final record = await waitForStatus(engine, id, DownloadStatus.done);
      expect(record.outputKind, OutputKind.file);
      expect(env.ffmpeg.runs, hasLength(1));
      expect(env.transfer.enqueued, hasLength(6));
    },
  );

  test('only a finished package', () async {
    final engine = await env.engine();
    final (:id, outcome: _) = await engine.enqueue(
      request(output: OutputMode.file),
    );
    await waitUntil(() => env.transfer.enqueued.length == 6);
    expect(() => engine.export(id), throwsStateError, reason: 'downloading');

    await env.transfer.completeAll();
    await waitForStatus(engine, id, DownloadStatus.done);
    expect(() => engine.export(id), throwsStateError, reason: 'a file');
    expect(() => engine.export('nope'), throwsStateError);
  });

  test('holds the queue: the next download waits for it', () async {
    final ffmpeg = _GatedFfmpeg();
    final engine = await env.engine(ffmpeg: ffmpeg);
    final id = await package(engine);

    final exporting = engine.export(id);
    await waitUntil(() => ffmpeg.started);
    final next = await engine.enqueue(request(key: 'movie-2', url: hlsUrl));
    await settle();
    expect(engine.byId(id)!.status, DownloadStatus.assembling);
    expect(engine.byId(next.id)!.status, DownloadStatus.queued);

    ffmpeg.release();
    expect(await exporting, isNull);
    await waitForStatus(engine, next.id, DownloadStatus.downloading);
  });

  test('cancelPending leaves a title being exported alone', () async {
    final ffmpeg = _GatedFfmpeg();
    final engine = await env.engine(ffmpeg: ffmpeg);
    final id = await package(engine);
    final other = await engine.enqueue(request(key: 'movie-2', url: hlsUrl));

    final exporting = engine.export(id);
    await waitUntil(() => ffmpeg.started);
    expect(await engine.cancelPending(), 1);
    expect(engine.byId(other.id), isNull);

    ffmpeg.release();
    expect(await exporting, isNull);
    expect(engine.byId(id)!.outputKind, OutputKind.file);
  });

  test('a kill in the middle merges again at the next start, without '
      'fetching anything', () async {
    final store = MemoryRecordStore();
    final a = await env.engine(store: store, ffmpeg: _GatedFfmpeg());
    final id = await package(a);
    unawaited(a.export(id));
    await waitUntil(
      () => store.records[id]?.status == DownloadStatus.assembling,
    );
    await a.dispose();

    final b = await env.engine(
      store: store,
      sink: DirectorySink(() async => out.path),
    );
    final record = await waitForStatus(b, id, DownloadStatus.done);
    expect(record.outputKind, OutputKind.file);
    expect(File(record.outputLocator!).existsSync(), isTrue);
    expect(env.transfer.enqueued, hasLength(6));
  });
}

/// ffmpeg that runs until [release]d.
class _GatedFfmpeg implements FfmpegRunner {
  final _gate = Completer<void>();
  bool started = false;

  void release() => _gate.complete();

  @override
  Future<void> run(List<String> args) async {
    started = true;
    await _gate.future;
    final output = File(args.last);
    await output.parent.create(recursive: true);
    await output.writeAsString('mkv');
  }
}
