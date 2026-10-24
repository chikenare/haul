import 'dart:convert';
import 'dart:io';

import 'package:offline_engine/src/planner/assembly/mux_input.dart';
import 'package:offline_engine/src/planner/assembly/segment_playlist.dart';
import 'package:offline_engine/src/planner/errors.dart';
import 'package:offline_engine/src/planner/plan.dart';
import 'package:path/path.dart' as p;

/// Turns a track's fetched pieces into something ffmpeg or a player opens
/// (see [TrackAssembly]).
class TrackAssembler {
  const TrackAssembler();

  Future<MuxInput> assemble(PlannedTrack track, Directory dir) async {
    final pieces = [
      for (final piece in track.pieces) File(p.join(dir.path, piece.file)),
    ];
    for (final piece in pieces) {
      if (!await piece.exists()) {
        throw SourceException(SourceErrorCode.missingPieces, piece.path);
      }
    }

    // MP4 DASH fragments are read through a playlist instead of joined:
    // joining them would be one more whole copy while merging.
    final asPlaylist =
        track.assembly == TrackAssembly.hlsPlaylist ||
        (track.assembly == TrackAssembly.concat && track.hasSegmentPlaylist);
    final path = switch (track.assembly) {
      TrackAssembly.single => pieces.single.path,
      TrackAssembly.concat when asPlaylist => await _playlist(
        track.segmentPlaylist,
        dir,
      ),
      TrackAssembly.concat => await _concat(pieces, dir),
      TrackAssembly.hlsPlaylist => await _playlist(track.playlist!, dir),
      TrackAssembly.vttSegments => await _mergeVtt(pieces, dir),
      TrackAssembly.ranges => await _join(pieces, dir, track),
    };

    return MuxInput(
      path: path,
      kind: track.kind,
      language: track.language,
      label: track.label,
      forced: track.forced,
      isHlsPlaylist: asPlaylist,
    );
  }

  /// A DASH init and its fragments one after another: the result is a valid
  /// fragmented MP4 (or WebM).
  Future<String> _concat(
    List<File> pieces,
    Directory dir, {
    String? name,
  }) async {
    final out = File(
      p.join(dir.path, name ?? 'track${p.extension(pieces.last.path)}'),
    );
    final sink = out.openWrite();
    try {
      for (final piece in pieces) {
        await sink.addStream(piece.openRead());
      }
    } finally {
      await sink.close();
    }
    return out.path;
  }

  /// The ranges of one file back into it. Each range is checked against
  /// the size it was asked for: a server that ignored the range, or a file
  /// that changed in between, would otherwise splice garbage.
  Future<String> _join(
    List<File> pieces,
    Directory dir,
    PlannedTrack track,
  ) async {
    for (final (i, piece) in pieces.indexed) {
      final expected = track.pieces[i].expectedBytes;
      if (expected != null && await piece.length() != expected) {
        throw SourceException(SourceErrorCode.missingPieces, piece.path);
      }
    }
    return _concat(pieces, dir, name: 'track.${track.fileExtension ?? 'bin'}');
  }

  Future<String> _playlist(String playlist, Directory dir) async {
    final file = File(p.join(dir.path, 'index.m3u8'));
    await file.writeAsString(playlist);
    return file.path;
  }

  Future<String> _mergeVtt(List<File> pieces, Directory dir) async {
    final texts = [
      for (final piece in pieces) decodeText(await piece.readAsBytes()),
    ];
    final file = File(p.join(dir.path, 'track.vtt'));
    await file.writeAsString(mergeVtt(texts));
    return file.path;
  }

  /// UTF-8, which is what WebVTT asks for; failing that, Latin-1, which is
  /// how many hand-made Spanish subtitles arrive.
  static String decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Merges an HLS's WebVTT fragments into one.
  ///
  /// Every fragment may carry `X-TIMESTAMP-MAP`, saying which transport
  /// stream instant its local time maps to. Playback starts every input at
  /// zero, so the video loses the TS's initial offset and the first fragment
  /// is already aligned with it; only how far each fragment drifts from that
  /// first one is corrected (packagers that restart local time in each).
  ///
  /// A cue crossing a fragment boundary comes repeated in both (that is how
  /// Apple and Shaka package): one is kept.
  static String mergeVtt(List<String> segments) {
    final cues = <String>[];
    final seen = <String>{};
    _TimestampMap? base;

    for (final text in segments) {
      final blocks = text
          .replaceAll('\r\n', '\n')
          .replaceFirst('﻿', '')
          .split(RegExp(r'\n{2,}'));
      if (blocks.isEmpty) continue;

      final map = _timestampMap(blocks.first);
      base ??= map;
      final offset = map.offsetFrom(base);
      for (final block in blocks.skip(1)) {
        final trimmed = block.trim();
        if (trimmed.isEmpty || !trimmed.contains('-->')) continue;
        final cue = offset == Duration.zero ? trimmed : _shift(trimmed, offset);
        if (seen.add(_withoutIdentifier(cue))) cues.add(cue);
      }
    }

    return 'WEBVTT\n\n${cues.join('\n\n')}\n';
  }

  /// A cue's optional identifier (the line before the timing) changes
  /// between fragments even when the cue is the same.
  static String _withoutIdentifier(String cue) {
    final lines = cue.split('\n');
    final timing = lines.indexWhere((l) => l.contains('-->'));
    return lines.skip(timing).join('\n');
  }

  static _TimestampMap _timestampMap(String header) {
    final match = _timestampMapPattern.firstMatch(header);
    if (match == null) return const _TimestampMap(0, Duration.zero);

    return _TimestampMap(
      int.tryParse(match.group(1) ?? match.group(4) ?? '') ?? 0,
      _parseTime(match.group(2) ?? match.group(3) ?? '') ?? Duration.zero,
    );
  }

  static final _timestampMapPattern = RegExp(
    r'X-TIMESTAMP-MAP=(?:MPEGTS:(\d+),LOCAL:([\d:.]+)|LOCAL:([\d:.]+),MPEGTS:(\d+))',
  );

  static String _shift(String cue, Duration offset) {
    return cue.replaceAllMapped(_timing, (m) {
      final start = _parseTime(m.group(1)!)! + offset;
      final end = _parseTime(m.group(2)!)! + offset;
      return '${_formatTime(start)} --> ${_formatTime(end)}';
    });
  }

  static final _timing = RegExp(
    r'((?:\d+:)?\d{2}:\d{2}\.\d{3})\s+-->\s+((?:\d+:)?\d{2}:\d{2}\.\d{3})',
  );

  static Duration? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final seconds = double.tryParse(parts.last);
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length > 2 ? int.tryParse(parts.first) : 0;
    if (seconds == null || minutes == null || hours == null) return null;

    return Duration(
      hours: hours,
      minutes: minutes,
      microseconds: (seconds * 1000000).round(),
    );
  }

  static String _formatTime(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = value.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '${two(value.inHours)}:${two(value.inMinutes.remainder(60))}:'
        '${two(value.inSeconds.remainder(60))}.$ms';
  }
}

/// `X-TIMESTAMP-MAP`: which transport stream instant (in 90 kHz ticks) a
/// fragment's local time maps to.
class _TimestampMap {
  const _TimestampMap(this.mpegts, this.local);

  final int mpegts;
  final Duration local;

  /// The TS PTS is 33 bits and wraps at ~26.5 h: the difference is taken
  /// modulo 2^33 so it does not go negative across the wrap.
  static const _wrap = 1 << 33;

  Duration offsetFrom(_TimestampMap base) {
    final ticks = (mpegts - base.mpegts) % _wrap;
    return Duration(microseconds: ticks * 1000000 ~/ 90000) -
        (local - base.local);
  }
}
