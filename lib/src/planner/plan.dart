import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan.freezed.dart';
part 'plan.g.dart';

/// What a download comes from. Decided by the content, not the URL: a signed
/// link rarely says what it is.
enum SourceKind { file, hls, dash }

enum TrackKind { video, audio, subtitle }

/// How the pieces of one track become something the player or ffmpeg reads.
enum TrackAssembly {
  /// One piece, which already is the file.
  single,

  /// An init plus fragments (DASH), in order and without repeats.
  concat,

  /// A local HLS playlist pointing at the fetched fragments and keys, read
  /// as if it were remote — the AES-128 is decrypted by whoever plays it.
  hlsPlaylist,

  /// WebVTT fragments of an HLS, merged into one `.vtt`.
  vttSegments,

  /// Byte ranges of one big file, joined back in order. Fetched apart so a
  /// pause, a kill or a dead link only loses the ranges in flight — the
  /// downloader's own pause is not reliable on every platform.
  ranges,
}

/// What to fetch and how to put it together. Decided once, when the
/// download starts, and kept on disk beside the pieces (`plan.json`) rather
/// than in the database: a long HLS is thousands of URLs, and every progress
/// write would rewrite them.
@freezed
abstract class DownloadPlan with _$DownloadPlan {
  const DownloadPlan._();

  const factory DownloadPlan({
    required List<PlannedTrack> tracks,

    /// Extension of the merged file, without the dot.
    required String extension,

    /// Estimated weight, `0` when unknown.
    @Default(0) int expectedBytes,
  }) = _DownloadPlan;

  factory DownloadPlan.fromJson(Map<String, Object?> json) =>
      _$DownloadPlanFromJson(json);

  /// A plain file with no external subtitles stays as it arrived; anything
  /// else goes through ffmpeg when it is merged.
  bool get needsMux =>
      tracks.length > 1 ||
      switch (tracks.single.assembly) {
        TrackAssembly.single || TrackAssembly.ranges => false,
        _ => true,
      };

  int get pieceCount => tracks.fold(0, (sum, t) => sum + t.pieces.length);

  /// With fragments, progress counts finished pieces: an HLS weight is only
  /// an estimate from its bitrate. With whole files, it counts bytes.
  bool get isSegmented => tracks.any((t) => t.pieces.length > 1);

  /// Whether [other] fetches the same files under the same local names —
  /// same tracks, from the same source ids, with the same pieces — so what
  /// this plan already has on disk counts for [other]. Only the URLs may
  /// differ: a fresh mint signs them again.
  bool linesUpWith(DownloadPlan other) {
    if (tracks.length != other.tracks.length) return false;
    for (final (i, track) in tracks.indexed) {
      final theirs = other.tracks[i];
      if (track.kind != theirs.kind ||
          track.sourceId != theirs.sourceId ||
          track.pieces.length != theirs.pieces.length) {
        return false;
      }
      for (final (j, piece) in track.pieces.indexed) {
        final other = theirs.pieces[j];
        if (piece.file != other.file ||
            piece.rangeStart != other.rangeStart ||
            piece.rangeEnd != other.rangeEnd) {
          return false;
        }
      }
    }
    return true;
  }
}

@freezed
abstract class PlannedTrack with _$PlannedTrack {
  const factory PlannedTrack({
    required TrackKind kind,
    required TrackAssembly assembly,
    required List<PlannedPiece> pieces,

    /// Only on [TrackAssembly.hlsPlaylist]: the media playlist with its URIs
    /// already swapped for the local names of [pieces].
    String? playlist,
    String? language,
    String? label,
    @Default(false) bool forced,

    /// The codecs the manifest declares (`avc1.640028,mp4a.40.2`), for the
    /// local package's master playlist.
    String? codecs,

    /// The manifest's id for what this track was planned from — the
    /// representation or rendition — so a fresh link can be planned again
    /// with the same choice.
    String? sourceId,

    /// Only on [TrackAssembly.ranges]: the file's strong ETag, sent as
    /// `If-Range` so a file that changed between two ranges answers whole
    /// and is caught by its size instead of being spliced.
    String? ifRange,

    /// Only on [TrackAssembly.ranges]: the joined file's extension, which
    /// ffmpeg reads the container from.
    String? fileExtension,
  }) = _PlannedTrack;

  factory PlannedTrack.fromJson(Map<String, Object?> json) =>
      _$PlannedTrackFromJson(json);
}

/// One file to fetch: a whole file, a fragment, an init or a key. [file] is
/// its name inside the track's folder.
@freezed
abstract class PlannedPiece with _$PlannedPiece {
  const factory PlannedPiece({
    required String url,
    required String file,

    /// Seconds of media, only on DASH fragments: the local package's
    /// playlist is written from them. Null on the init.
    double? duration,

    /// Inclusive byte range of the file, only on [TrackAssembly.ranges].
    int? rangeStart,
    int? rangeEnd,
  }) = _PlannedPiece;

  factory PlannedPiece.fromJson(Map<String, Object?> json) =>
      _$PlannedPieceFromJson(json);
}

extension PlannedPieceRange on PlannedPiece {
  /// What the `Range` request asks for, or null for the whole resource.
  String? get rangeHeader =>
      rangeStart == null ? null : 'bytes=$rangeStart-${rangeEnd ?? ''}';

  /// The size a fetched range must have; null when anything goes.
  int? get expectedBytes => rangeStart != null && rangeEnd != null
      ? rangeEnd! - rangeStart! + 1
      : null;
}
