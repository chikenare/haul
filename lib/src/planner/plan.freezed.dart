// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DownloadPlan {

 List<PlannedTrack> get tracks;/// Extension of the merged file, without the dot.
 String get extension;/// Estimated weight, `0` when unknown.
 int get expectedBytes;
/// Create a copy of DownloadPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadPlanCopyWith<DownloadPlan> get copyWith => _$DownloadPlanCopyWithImpl<DownloadPlan>(this as DownloadPlan, _$identity);

  /// Serializes this DownloadPlan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadPlan&&const DeepCollectionEquality().equals(other.tracks, tracks)&&(identical(other.extension, extension) || other.extension == extension)&&(identical(other.expectedBytes, expectedBytes) || other.expectedBytes == expectedBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(tracks),extension,expectedBytes);

@override
String toString() {
  return 'DownloadPlan(tracks: $tracks, extension: $extension, expectedBytes: $expectedBytes)';
}


}

/// @nodoc
abstract mixin class $DownloadPlanCopyWith<$Res>  {
  factory $DownloadPlanCopyWith(DownloadPlan value, $Res Function(DownloadPlan) _then) = _$DownloadPlanCopyWithImpl;
@useResult
$Res call({
 List<PlannedTrack> tracks, String extension, int expectedBytes
});




}
/// @nodoc
class _$DownloadPlanCopyWithImpl<$Res>
    implements $DownloadPlanCopyWith<$Res> {
  _$DownloadPlanCopyWithImpl(this._self, this._then);

  final DownloadPlan _self;
  final $Res Function(DownloadPlan) _then;

/// Create a copy of DownloadPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tracks = null,Object? extension = null,Object? expectedBytes = null,}) {
  return _then(_self.copyWith(
tracks: null == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<PlannedTrack>,extension: null == extension ? _self.extension : extension // ignore: cast_nullable_to_non_nullable
as String,expectedBytes: null == expectedBytes ? _self.expectedBytes : expectedBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadPlan].
extension DownloadPlanPatterns on DownloadPlan {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadPlan() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadPlan value)  $default,){
final _that = this;
switch (_that) {
case _DownloadPlan():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadPlan value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadPlan() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<PlannedTrack> tracks,  String extension,  int expectedBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadPlan() when $default != null:
return $default(_that.tracks,_that.extension,_that.expectedBytes);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<PlannedTrack> tracks,  String extension,  int expectedBytes)  $default,) {final _that = this;
switch (_that) {
case _DownloadPlan():
return $default(_that.tracks,_that.extension,_that.expectedBytes);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<PlannedTrack> tracks,  String extension,  int expectedBytes)?  $default,) {final _that = this;
switch (_that) {
case _DownloadPlan() when $default != null:
return $default(_that.tracks,_that.extension,_that.expectedBytes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadPlan extends DownloadPlan {
  const _DownloadPlan({required final  List<PlannedTrack> tracks, required this.extension, this.expectedBytes = 0}): _tracks = tracks,super._();
  factory _DownloadPlan.fromJson(Map<String, dynamic> json) => _$DownloadPlanFromJson(json);

 final  List<PlannedTrack> _tracks;
@override List<PlannedTrack> get tracks {
  if (_tracks is EqualUnmodifiableListView) return _tracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tracks);
}

/// Extension of the merged file, without the dot.
@override final  String extension;
/// Estimated weight, `0` when unknown.
@override@JsonKey() final  int expectedBytes;

/// Create a copy of DownloadPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadPlanCopyWith<_DownloadPlan> get copyWith => __$DownloadPlanCopyWithImpl<_DownloadPlan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadPlanToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadPlan&&const DeepCollectionEquality().equals(other._tracks, _tracks)&&(identical(other.extension, extension) || other.extension == extension)&&(identical(other.expectedBytes, expectedBytes) || other.expectedBytes == expectedBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tracks),extension,expectedBytes);

@override
String toString() {
  return 'DownloadPlan(tracks: $tracks, extension: $extension, expectedBytes: $expectedBytes)';
}


}

/// @nodoc
abstract mixin class _$DownloadPlanCopyWith<$Res> implements $DownloadPlanCopyWith<$Res> {
  factory _$DownloadPlanCopyWith(_DownloadPlan value, $Res Function(_DownloadPlan) _then) = __$DownloadPlanCopyWithImpl;
@override @useResult
$Res call({
 List<PlannedTrack> tracks, String extension, int expectedBytes
});




}
/// @nodoc
class __$DownloadPlanCopyWithImpl<$Res>
    implements _$DownloadPlanCopyWith<$Res> {
  __$DownloadPlanCopyWithImpl(this._self, this._then);

  final _DownloadPlan _self;
  final $Res Function(_DownloadPlan) _then;

/// Create a copy of DownloadPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tracks = null,Object? extension = null,Object? expectedBytes = null,}) {
  return _then(_DownloadPlan(
tracks: null == tracks ? _self._tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<PlannedTrack>,extension: null == extension ? _self.extension : extension // ignore: cast_nullable_to_non_nullable
as String,expectedBytes: null == expectedBytes ? _self.expectedBytes : expectedBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PlannedTrack {

 TrackKind get kind; TrackAssembly get assembly; List<PlannedPiece> get pieces;/// Only on [TrackAssembly.hlsPlaylist]: the media playlist with its URIs
/// already swapped for the local names of [pieces].
 String? get playlist; String? get language; String? get label; bool get forced;/// The codecs the manifest declares (`avc1.640028,mp4a.40.2`), for the
/// local package's master playlist.
 String? get codecs;/// The manifest's id for what this track was planned from — the
/// representation or rendition — so a fresh link can be planned again
/// with the same choice.
 String? get sourceId;/// Only on [TrackAssembly.ranges]: the file's strong ETag, sent as
/// `If-Range` so a file that changed between two ranges answers whole
/// and is caught by its size instead of being spliced.
 String? get ifRange;/// Only on [TrackAssembly.ranges]: the joined file's extension, which
/// ffmpeg reads the container from.
 String? get fileExtension;
/// Create a copy of PlannedTrack
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlannedTrackCopyWith<PlannedTrack> get copyWith => _$PlannedTrackCopyWithImpl<PlannedTrack>(this as PlannedTrack, _$identity);

  /// Serializes this PlannedTrack to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlannedTrack&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.assembly, assembly) || other.assembly == assembly)&&const DeepCollectionEquality().equals(other.pieces, pieces)&&(identical(other.playlist, playlist) || other.playlist == playlist)&&(identical(other.language, language) || other.language == language)&&(identical(other.label, label) || other.label == label)&&(identical(other.forced, forced) || other.forced == forced)&&(identical(other.codecs, codecs) || other.codecs == codecs)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.ifRange, ifRange) || other.ifRange == ifRange)&&(identical(other.fileExtension, fileExtension) || other.fileExtension == fileExtension));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,assembly,const DeepCollectionEquality().hash(pieces),playlist,language,label,forced,codecs,sourceId,ifRange,fileExtension);

@override
String toString() {
  return 'PlannedTrack(kind: $kind, assembly: $assembly, pieces: $pieces, playlist: $playlist, language: $language, label: $label, forced: $forced, codecs: $codecs, sourceId: $sourceId, ifRange: $ifRange, fileExtension: $fileExtension)';
}


}

/// @nodoc
abstract mixin class $PlannedTrackCopyWith<$Res>  {
  factory $PlannedTrackCopyWith(PlannedTrack value, $Res Function(PlannedTrack) _then) = _$PlannedTrackCopyWithImpl;
@useResult
$Res call({
 TrackKind kind, TrackAssembly assembly, List<PlannedPiece> pieces, String? playlist, String? language, String? label, bool forced, String? codecs, String? sourceId, String? ifRange, String? fileExtension
});




}
/// @nodoc
class _$PlannedTrackCopyWithImpl<$Res>
    implements $PlannedTrackCopyWith<$Res> {
  _$PlannedTrackCopyWithImpl(this._self, this._then);

  final PlannedTrack _self;
  final $Res Function(PlannedTrack) _then;

/// Create a copy of PlannedTrack
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? assembly = null,Object? pieces = null,Object? playlist = freezed,Object? language = freezed,Object? label = freezed,Object? forced = null,Object? codecs = freezed,Object? sourceId = freezed,Object? ifRange = freezed,Object? fileExtension = freezed,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as TrackKind,assembly: null == assembly ? _self.assembly : assembly // ignore: cast_nullable_to_non_nullable
as TrackAssembly,pieces: null == pieces ? _self.pieces : pieces // ignore: cast_nullable_to_non_nullable
as List<PlannedPiece>,playlist: freezed == playlist ? _self.playlist : playlist // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,forced: null == forced ? _self.forced : forced // ignore: cast_nullable_to_non_nullable
as bool,codecs: freezed == codecs ? _self.codecs : codecs // ignore: cast_nullable_to_non_nullable
as String?,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,ifRange: freezed == ifRange ? _self.ifRange : ifRange // ignore: cast_nullable_to_non_nullable
as String?,fileExtension: freezed == fileExtension ? _self.fileExtension : fileExtension // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlannedTrack].
extension PlannedTrackPatterns on PlannedTrack {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlannedTrack value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlannedTrack() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlannedTrack value)  $default,){
final _that = this;
switch (_that) {
case _PlannedTrack():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlannedTrack value)?  $default,){
final _that = this;
switch (_that) {
case _PlannedTrack() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TrackKind kind,  TrackAssembly assembly,  List<PlannedPiece> pieces,  String? playlist,  String? language,  String? label,  bool forced,  String? codecs,  String? sourceId,  String? ifRange,  String? fileExtension)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlannedTrack() when $default != null:
return $default(_that.kind,_that.assembly,_that.pieces,_that.playlist,_that.language,_that.label,_that.forced,_that.codecs,_that.sourceId,_that.ifRange,_that.fileExtension);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TrackKind kind,  TrackAssembly assembly,  List<PlannedPiece> pieces,  String? playlist,  String? language,  String? label,  bool forced,  String? codecs,  String? sourceId,  String? ifRange,  String? fileExtension)  $default,) {final _that = this;
switch (_that) {
case _PlannedTrack():
return $default(_that.kind,_that.assembly,_that.pieces,_that.playlist,_that.language,_that.label,_that.forced,_that.codecs,_that.sourceId,_that.ifRange,_that.fileExtension);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TrackKind kind,  TrackAssembly assembly,  List<PlannedPiece> pieces,  String? playlist,  String? language,  String? label,  bool forced,  String? codecs,  String? sourceId,  String? ifRange,  String? fileExtension)?  $default,) {final _that = this;
switch (_that) {
case _PlannedTrack() when $default != null:
return $default(_that.kind,_that.assembly,_that.pieces,_that.playlist,_that.language,_that.label,_that.forced,_that.codecs,_that.sourceId,_that.ifRange,_that.fileExtension);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlannedTrack implements PlannedTrack {
  const _PlannedTrack({required this.kind, required this.assembly, required final  List<PlannedPiece> pieces, this.playlist, this.language, this.label, this.forced = false, this.codecs, this.sourceId, this.ifRange, this.fileExtension}): _pieces = pieces;
  factory _PlannedTrack.fromJson(Map<String, dynamic> json) => _$PlannedTrackFromJson(json);

@override final  TrackKind kind;
@override final  TrackAssembly assembly;
 final  List<PlannedPiece> _pieces;
@override List<PlannedPiece> get pieces {
  if (_pieces is EqualUnmodifiableListView) return _pieces;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pieces);
}

/// Only on [TrackAssembly.hlsPlaylist]: the media playlist with its URIs
/// already swapped for the local names of [pieces].
@override final  String? playlist;
@override final  String? language;
@override final  String? label;
@override@JsonKey() final  bool forced;
/// The codecs the manifest declares (`avc1.640028,mp4a.40.2`), for the
/// local package's master playlist.
@override final  String? codecs;
/// The manifest's id for what this track was planned from — the
/// representation or rendition — so a fresh link can be planned again
/// with the same choice.
@override final  String? sourceId;
/// Only on [TrackAssembly.ranges]: the file's strong ETag, sent as
/// `If-Range` so a file that changed between two ranges answers whole
/// and is caught by its size instead of being spliced.
@override final  String? ifRange;
/// Only on [TrackAssembly.ranges]: the joined file's extension, which
/// ffmpeg reads the container from.
@override final  String? fileExtension;

/// Create a copy of PlannedTrack
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlannedTrackCopyWith<_PlannedTrack> get copyWith => __$PlannedTrackCopyWithImpl<_PlannedTrack>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlannedTrackToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlannedTrack&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.assembly, assembly) || other.assembly == assembly)&&const DeepCollectionEquality().equals(other._pieces, _pieces)&&(identical(other.playlist, playlist) || other.playlist == playlist)&&(identical(other.language, language) || other.language == language)&&(identical(other.label, label) || other.label == label)&&(identical(other.forced, forced) || other.forced == forced)&&(identical(other.codecs, codecs) || other.codecs == codecs)&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.ifRange, ifRange) || other.ifRange == ifRange)&&(identical(other.fileExtension, fileExtension) || other.fileExtension == fileExtension));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,assembly,const DeepCollectionEquality().hash(_pieces),playlist,language,label,forced,codecs,sourceId,ifRange,fileExtension);

@override
String toString() {
  return 'PlannedTrack(kind: $kind, assembly: $assembly, pieces: $pieces, playlist: $playlist, language: $language, label: $label, forced: $forced, codecs: $codecs, sourceId: $sourceId, ifRange: $ifRange, fileExtension: $fileExtension)';
}


}

/// @nodoc
abstract mixin class _$PlannedTrackCopyWith<$Res> implements $PlannedTrackCopyWith<$Res> {
  factory _$PlannedTrackCopyWith(_PlannedTrack value, $Res Function(_PlannedTrack) _then) = __$PlannedTrackCopyWithImpl;
@override @useResult
$Res call({
 TrackKind kind, TrackAssembly assembly, List<PlannedPiece> pieces, String? playlist, String? language, String? label, bool forced, String? codecs, String? sourceId, String? ifRange, String? fileExtension
});




}
/// @nodoc
class __$PlannedTrackCopyWithImpl<$Res>
    implements _$PlannedTrackCopyWith<$Res> {
  __$PlannedTrackCopyWithImpl(this._self, this._then);

  final _PlannedTrack _self;
  final $Res Function(_PlannedTrack) _then;

/// Create a copy of PlannedTrack
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? assembly = null,Object? pieces = null,Object? playlist = freezed,Object? language = freezed,Object? label = freezed,Object? forced = null,Object? codecs = freezed,Object? sourceId = freezed,Object? ifRange = freezed,Object? fileExtension = freezed,}) {
  return _then(_PlannedTrack(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as TrackKind,assembly: null == assembly ? _self.assembly : assembly // ignore: cast_nullable_to_non_nullable
as TrackAssembly,pieces: null == pieces ? _self._pieces : pieces // ignore: cast_nullable_to_non_nullable
as List<PlannedPiece>,playlist: freezed == playlist ? _self.playlist : playlist // ignore: cast_nullable_to_non_nullable
as String?,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,forced: null == forced ? _self.forced : forced // ignore: cast_nullable_to_non_nullable
as bool,codecs: freezed == codecs ? _self.codecs : codecs // ignore: cast_nullable_to_non_nullable
as String?,sourceId: freezed == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String?,ifRange: freezed == ifRange ? _self.ifRange : ifRange // ignore: cast_nullable_to_non_nullable
as String?,fileExtension: freezed == fileExtension ? _self.fileExtension : fileExtension // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PlannedPiece {

 String get url; String get file;/// Seconds of media, only on DASH fragments: the local package's
/// playlist is written from them. Null on the init.
 double? get duration;/// Inclusive byte range of the file, only on [TrackAssembly.ranges].
 int? get rangeStart; int? get rangeEnd;
/// Create a copy of PlannedPiece
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlannedPieceCopyWith<PlannedPiece> get copyWith => _$PlannedPieceCopyWithImpl<PlannedPiece>(this as PlannedPiece, _$identity);

  /// Serializes this PlannedPiece to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlannedPiece&&(identical(other.url, url) || other.url == url)&&(identical(other.file, file) || other.file == file)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.rangeStart, rangeStart) || other.rangeStart == rangeStart)&&(identical(other.rangeEnd, rangeEnd) || other.rangeEnd == rangeEnd));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,file,duration,rangeStart,rangeEnd);

@override
String toString() {
  return 'PlannedPiece(url: $url, file: $file, duration: $duration, rangeStart: $rangeStart, rangeEnd: $rangeEnd)';
}


}

/// @nodoc
abstract mixin class $PlannedPieceCopyWith<$Res>  {
  factory $PlannedPieceCopyWith(PlannedPiece value, $Res Function(PlannedPiece) _then) = _$PlannedPieceCopyWithImpl;
@useResult
$Res call({
 String url, String file, double? duration, int? rangeStart, int? rangeEnd
});




}
/// @nodoc
class _$PlannedPieceCopyWithImpl<$Res>
    implements $PlannedPieceCopyWith<$Res> {
  _$PlannedPieceCopyWithImpl(this._self, this._then);

  final PlannedPiece _self;
  final $Res Function(PlannedPiece) _then;

/// Create a copy of PlannedPiece
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? file = null,Object? duration = freezed,Object? rangeStart = freezed,Object? rangeEnd = freezed,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,rangeStart: freezed == rangeStart ? _self.rangeStart : rangeStart // ignore: cast_nullable_to_non_nullable
as int?,rangeEnd: freezed == rangeEnd ? _self.rangeEnd : rangeEnd // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlannedPiece].
extension PlannedPiecePatterns on PlannedPiece {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlannedPiece value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlannedPiece() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlannedPiece value)  $default,){
final _that = this;
switch (_that) {
case _PlannedPiece():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlannedPiece value)?  $default,){
final _that = this;
switch (_that) {
case _PlannedPiece() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String file,  double? duration,  int? rangeStart,  int? rangeEnd)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlannedPiece() when $default != null:
return $default(_that.url,_that.file,_that.duration,_that.rangeStart,_that.rangeEnd);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String file,  double? duration,  int? rangeStart,  int? rangeEnd)  $default,) {final _that = this;
switch (_that) {
case _PlannedPiece():
return $default(_that.url,_that.file,_that.duration,_that.rangeStart,_that.rangeEnd);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String file,  double? duration,  int? rangeStart,  int? rangeEnd)?  $default,) {final _that = this;
switch (_that) {
case _PlannedPiece() when $default != null:
return $default(_that.url,_that.file,_that.duration,_that.rangeStart,_that.rangeEnd);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlannedPiece implements PlannedPiece {
  const _PlannedPiece({required this.url, required this.file, this.duration, this.rangeStart, this.rangeEnd});
  factory _PlannedPiece.fromJson(Map<String, dynamic> json) => _$PlannedPieceFromJson(json);

@override final  String url;
@override final  String file;
/// Seconds of media, only on DASH fragments: the local package's
/// playlist is written from them. Null on the init.
@override final  double? duration;
/// Inclusive byte range of the file, only on [TrackAssembly.ranges].
@override final  int? rangeStart;
@override final  int? rangeEnd;

/// Create a copy of PlannedPiece
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlannedPieceCopyWith<_PlannedPiece> get copyWith => __$PlannedPieceCopyWithImpl<_PlannedPiece>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlannedPieceToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlannedPiece&&(identical(other.url, url) || other.url == url)&&(identical(other.file, file) || other.file == file)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.rangeStart, rangeStart) || other.rangeStart == rangeStart)&&(identical(other.rangeEnd, rangeEnd) || other.rangeEnd == rangeEnd));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,file,duration,rangeStart,rangeEnd);

@override
String toString() {
  return 'PlannedPiece(url: $url, file: $file, duration: $duration, rangeStart: $rangeStart, rangeEnd: $rangeEnd)';
}


}

/// @nodoc
abstract mixin class _$PlannedPieceCopyWith<$Res> implements $PlannedPieceCopyWith<$Res> {
  factory _$PlannedPieceCopyWith(_PlannedPiece value, $Res Function(_PlannedPiece) _then) = __$PlannedPieceCopyWithImpl;
@override @useResult
$Res call({
 String url, String file, double? duration, int? rangeStart, int? rangeEnd
});




}
/// @nodoc
class __$PlannedPieceCopyWithImpl<$Res>
    implements _$PlannedPieceCopyWith<$Res> {
  __$PlannedPieceCopyWithImpl(this._self, this._then);

  final _PlannedPiece _self;
  final $Res Function(_PlannedPiece) _then;

/// Create a copy of PlannedPiece
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? file = null,Object? duration = freezed,Object? rangeStart = freezed,Object? rangeEnd = freezed,}) {
  return _then(_PlannedPiece(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as String,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,rangeStart: freezed == rangeStart ? _self.rangeStart : rangeStart // ignore: cast_nullable_to_non_nullable
as int?,rangeEnd: freezed == rangeEnd ? _self.rangeEnd : rangeEnd // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
