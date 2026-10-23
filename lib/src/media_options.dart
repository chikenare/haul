import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A video quality an HLS/DASH manifest offers.
@immutable
class VideoOption {
  const VideoOption({
    required this.id,
    this.width,
    this.height,
    this.bandwidth,
    this.codecs,
  });

  final String id;
  final int? width;
  final int? height;

  /// Bits per second, as the manifest declares it.
  final int? bandwidth;
  final String? codecs;

  /// `1080p`, `1080p · HEVC` when it is not H.264, or the bitrate when the
  /// manifest declares no resolution.
  String get label {
    final codec = codecName;
    if (height case final h?) return codec == null ? '${h}p' : '${h}p · $codec';
    if (bandwidth case final b?) return '${(b / 1000).round()} kbps';
    return id;
  }

  /// Only for what is not H.264, which is taken for granted.
  String? get codecName {
    final value = codecs?.toLowerCase() ?? '';
    if (value.contains('hvc1') || value.contains('hev1')) return 'HEVC';
    if (value.contains('av01')) return 'AV1';
    if (value.contains('vp09') || value.contains('vp9')) return 'VP9';
    return null;
  }
}

/// An alternative audio track of a manifest.
@immutable
class AudioOption {
  const AudioOption({
    required this.id,
    this.language,
    this.name,
    this.channels,
    this.bandwidth,
    this.isDefault = false,
  });

  final String id;
  final String? language;
  final String? name;
  final String? channels;
  final int? bandwidth;
  final bool isDefault;

  /// Null when the manifest gives it neither a name nor a language.
  String? get label => name ?? language;
}

/// A subtitle track of a manifest, or one handed in from outside.
@immutable
class SubtitleOption {
  const SubtitleOption({
    required this.id,
    this.language,
    this.name,
    this.forced = false,
  });

  final String id;
  final String? language;
  final String? name;
  final bool forced;

  /// Null when the manifest gives it neither a name nor a language.
  String? get label => name ?? language;
}

/// What gets downloaded from a source, by the ids its options carry.
@immutable
class SourceSelection {
  const SourceSelection({
    this.videoId,
    this.audioIds = const {},
    this.subtitleIds = const {},
  });

  final String? videoId;
  final Set<String> audioIds;
  final Set<String> subtitleIds;

  SourceSelection copyWith({
    String? videoId,
    Set<String>? audioIds,
    Set<String>? subtitleIds,
  }) {
    return SourceSelection(
      videoId: videoId ?? this.videoId,
      audioIds: audioIds ?? this.audioIds,
      subtitleIds: subtitleIds ?? this.subtitleIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceSelection &&
      other.videoId == videoId &&
      _sets.equals(other.audioIds, audioIds) &&
      _sets.equals(other.subtitleIds, subtitleIds);

  static const _sets = SetEquality<String>();

  @override
  int get hashCode => Object.hash(
    videoId,
    Object.hashAllUnordered(audioIds),
    Object.hashAllUnordered(subtitleIds),
  );
}
