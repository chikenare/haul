// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DownloadPlan _$DownloadPlanFromJson(Map<String, dynamic> json) =>
    _DownloadPlan(
      tracks: (json['tracks'] as List<dynamic>)
          .map((e) => PlannedTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
      extension: json['extension'] as String,
      expectedBytes: (json['expectedBytes'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$DownloadPlanToJson(_DownloadPlan instance) =>
    <String, dynamic>{
      'tracks': instance.tracks.map((e) => e.toJson()).toList(),
      'extension': instance.extension,
      'expectedBytes': instance.expectedBytes,
    };

_PlannedTrack _$PlannedTrackFromJson(Map<String, dynamic> json) =>
    _PlannedTrack(
      kind: $enumDecode(_$TrackKindEnumMap, json['kind']),
      assembly: $enumDecode(_$TrackAssemblyEnumMap, json['assembly']),
      pieces: (json['pieces'] as List<dynamic>)
          .map((e) => PlannedPiece.fromJson(e as Map<String, dynamic>))
          .toList(),
      playlist: json['playlist'] as String?,
      language: json['language'] as String?,
      label: json['label'] as String?,
      forced: json['forced'] as bool? ?? false,
      codecs: json['codecs'] as String?,
      sourceId: json['sourceId'] as String?,
      ifRange: json['ifRange'] as String?,
      fileExtension: json['fileExtension'] as String?,
      estimatedBytes: (json['estimatedBytes'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PlannedTrackToJson(_PlannedTrack instance) =>
    <String, dynamic>{
      'kind': _$TrackKindEnumMap[instance.kind]!,
      'assembly': _$TrackAssemblyEnumMap[instance.assembly]!,
      'pieces': instance.pieces.map((e) => e.toJson()).toList(),
      'playlist': instance.playlist,
      'language': instance.language,
      'label': instance.label,
      'forced': instance.forced,
      'codecs': instance.codecs,
      'sourceId': instance.sourceId,
      'ifRange': instance.ifRange,
      'fileExtension': instance.fileExtension,
      'estimatedBytes': instance.estimatedBytes,
    };

const _$TrackKindEnumMap = {
  TrackKind.video: 'video',
  TrackKind.audio: 'audio',
  TrackKind.subtitle: 'subtitle',
};

const _$TrackAssemblyEnumMap = {
  TrackAssembly.single: 'single',
  TrackAssembly.concat: 'concat',
  TrackAssembly.hlsPlaylist: 'hlsPlaylist',
  TrackAssembly.vttSegments: 'vttSegments',
  TrackAssembly.ranges: 'ranges',
};

_PlannedPiece _$PlannedPieceFromJson(Map<String, dynamic> json) =>
    _PlannedPiece(
      url: json['url'] as String,
      file: json['file'] as String,
      duration: (json['duration'] as num?)?.toDouble(),
      rangeStart: (json['rangeStart'] as num?)?.toInt(),
      rangeEnd: (json['rangeEnd'] as num?)?.toInt(),
      size: (json['size'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PlannedPieceToJson(_PlannedPiece instance) =>
    <String, dynamic>{
      'url': instance.url,
      'file': instance.file,
      'duration': instance.duration,
      'rangeStart': instance.rangeStart,
      'rangeEnd': instance.rangeEnd,
      'size': instance.size,
    };
