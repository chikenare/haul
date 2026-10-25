// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_OutputMode _$OutputModeFromJson(Map<String, dynamic> json) => _OutputMode(
  kind:
      $enumDecodeNullable(_$OutputKindEnumMap, json['kind']) ??
      OutputKind.package,
  subtitleSidecars: json['subtitleSidecars'] as bool? ?? false,
);

Map<String, dynamic> _$OutputModeToJson(_OutputMode instance) =>
    <String, dynamic>{
      'kind': _$OutputKindEnumMap[instance.kind]!,
      'subtitleSidecars': instance.subtitleSidecars,
    };

const _$OutputKindEnumMap = {
  OutputKind.package: 'package',
  OutputKind.file: 'file',
};

_OutputName _$OutputNameFromJson(Map<String, dynamic> json) => _OutputName(
  baseName: json['baseName'] as String,
  folders:
      (json['folders'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$OutputNameToJson(_OutputName instance) =>
    <String, dynamic>{
      'baseName': instance.baseName,
      'folders': instance.folders,
    };

_DownloadGroup _$DownloadGroupFromJson(Map<String, dynamic> json) =>
    _DownloadGroup(
      id: json['id'] as String,
      title: json['title'] as String,
      imageUrl: json['imageUrl'] as String?,
    );

Map<String, dynamic> _$DownloadGroupToJson(_DownloadGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'imageUrl': instance.imageUrl,
    };

_DownloadProgress _$DownloadProgressFromJson(Map<String, dynamic> json) =>
    _DownloadProgress(
      donePieces: (json['donePieces'] as num?)?.toInt() ?? 0,
      totalPieces: (json['totalPieces'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      segmented: json['segmented'] as bool? ?? false,
    );

Map<String, dynamic> _$DownloadProgressToJson(_DownloadProgress instance) =>
    <String, dynamic>{
      'donePieces': instance.donePieces,
      'totalPieces': instance.totalPieces,
      'bytes': instance.bytes,
      'totalBytes': instance.totalBytes,
      'segmented': instance.segmented,
    };

_DownloadError _$DownloadErrorFromJson(Map<String, dynamic> json) =>
    _DownloadError(
      code: json['code'] as String,
      message: json['message'] as String?,
      httpStatus: (json['httpStatus'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DownloadErrorToJson(_DownloadError instance) =>
    <String, dynamic>{
      'code': instance.code,
      'message': instance.message,
      'httpStatus': instance.httpStatus,
    };

_DownloadRecord _$DownloadRecordFromJson(Map<String, dynamic> json) =>
    _DownloadRecord(
      id: json['id'] as String,
      key: json['key'] as String,
      title: json['title'] as String,
      name: OutputName.fromJson(json['name'] as Map<String, dynamic>),
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      group: json['group'] == null
          ? null
          : DownloadGroup.fromJson(json['group'] as Map<String, dynamic>),
      section: json['section'] as String?,
      order: json['order'] as num?,
      imageUrl: json['imageUrl'] as String?,
      status: $enumDecode(_$DownloadStatusEnumMap, json['status']),
      error: json['error'] == null
          ? null
          : DownloadError.fromJson(json['error'] as Map<String, dynamic>),
      source: const _SourceConverter().fromJson(
        json['source'] as Map<String, Object?>,
      ),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      linkDead: json['linkDead'] as bool? ?? false,
      replan: json['replan'] as bool? ?? false,
      run: (json['run'] as num?)?.toInt() ?? 0,
      tracks: json['tracks'] == null
          ? const TrackChoice.policy()
          : const _TrackChoiceConverter().fromJson(
              json['tracks'] as Map<String, Object?>,
            ),
      output: json['output'] == null
          ? const OutputMode()
          : OutputMode.fromJson(json['output'] as Map<String, dynamic>),
      outputLocator: json['outputLocator'] as String?,
      outputKind: $enumDecodeNullable(_$OutputKindEnumMap, json['outputKind']),
      stagedPath: json['stagedPath'] as String?,
      publishTarget: json['publishTarget'] as String?,
      progress: json['progress'] == null
          ? const DownloadProgress()
          : DownloadProgress.fromJson(json['progress'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$DownloadRecordToJson(_DownloadRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'key': instance.key,
      'title': instance.title,
      'name': instance.name.toJson(),
      'metadata': instance.metadata,
      'group': instance.group?.toJson(),
      'section': instance.section,
      'order': instance.order,
      'imageUrl': instance.imageUrl,
      'status': _$DownloadStatusEnumMap[instance.status]!,
      'error': instance.error?.toJson(),
      'source': const _SourceConverter().toJson(instance.source),
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'linkDead': instance.linkDead,
      'replan': instance.replan,
      'run': instance.run,
      'tracks': const _TrackChoiceConverter().toJson(instance.tracks),
      'output': instance.output.toJson(),
      'outputLocator': instance.outputLocator,
      'outputKind': _$OutputKindEnumMap[instance.outputKind],
      'stagedPath': instance.stagedPath,
      'publishTarget': instance.publishTarget,
      'progress': instance.progress.toJson(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

const _$DownloadStatusEnumMap = {
  DownloadStatus.queued: 'queued',
  DownloadStatus.resolving: 'resolving',
  DownloadStatus.downloading: 'downloading',
  DownloadStatus.paused: 'paused',
  DownloadStatus.assembling: 'assembling',
  DownloadStatus.done: 'done',
  DownloadStatus.failed: 'failed',
};
