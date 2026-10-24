// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$OutputMode {

 OutputKind get kind;/// With [OutputKind.file], whether the subtitles also stay beside the
/// file — some players only style subtitles loaded from outside.
 bool get subtitleSidecars;
/// Create a copy of OutputMode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutputModeCopyWith<OutputMode> get copyWith => _$OutputModeCopyWithImpl<OutputMode>(this as OutputMode, _$identity);

  /// Serializes this OutputMode to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputMode&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.subtitleSidecars, subtitleSidecars) || other.subtitleSidecars == subtitleSidecars));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,subtitleSidecars);

@override
String toString() {
  return 'OutputMode(kind: $kind, subtitleSidecars: $subtitleSidecars)';
}


}

/// @nodoc
abstract mixin class $OutputModeCopyWith<$Res>  {
  factory $OutputModeCopyWith(OutputMode value, $Res Function(OutputMode) _then) = _$OutputModeCopyWithImpl;
@useResult
$Res call({
 OutputKind kind, bool subtitleSidecars
});




}
/// @nodoc
class _$OutputModeCopyWithImpl<$Res>
    implements $OutputModeCopyWith<$Res> {
  _$OutputModeCopyWithImpl(this._self, this._then);

  final OutputMode _self;
  final $Res Function(OutputMode) _then;

/// Create a copy of OutputMode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? subtitleSidecars = null,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as OutputKind,subtitleSidecars: null == subtitleSidecars ? _self.subtitleSidecars : subtitleSidecars // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [OutputMode].
extension OutputModePatterns on OutputMode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OutputMode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OutputMode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OutputMode value)  $default,){
final _that = this;
switch (_that) {
case _OutputMode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OutputMode value)?  $default,){
final _that = this;
switch (_that) {
case _OutputMode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OutputKind kind,  bool subtitleSidecars)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OutputMode() when $default != null:
return $default(_that.kind,_that.subtitleSidecars);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OutputKind kind,  bool subtitleSidecars)  $default,) {final _that = this;
switch (_that) {
case _OutputMode():
return $default(_that.kind,_that.subtitleSidecars);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OutputKind kind,  bool subtitleSidecars)?  $default,) {final _that = this;
switch (_that) {
case _OutputMode() when $default != null:
return $default(_that.kind,_that.subtitleSidecars);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OutputMode implements OutputMode {
  const _OutputMode({this.kind = OutputKind.package, this.subtitleSidecars = false});
  factory _OutputMode.fromJson(Map<String, dynamic> json) => _$OutputModeFromJson(json);

@override@JsonKey() final  OutputKind kind;
/// With [OutputKind.file], whether the subtitles also stay beside the
/// file — some players only style subtitles loaded from outside.
@override@JsonKey() final  bool subtitleSidecars;

/// Create a copy of OutputMode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OutputModeCopyWith<_OutputMode> get copyWith => __$OutputModeCopyWithImpl<_OutputMode>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OutputModeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OutputMode&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.subtitleSidecars, subtitleSidecars) || other.subtitleSidecars == subtitleSidecars));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,kind,subtitleSidecars);

@override
String toString() {
  return 'OutputMode(kind: $kind, subtitleSidecars: $subtitleSidecars)';
}


}

/// @nodoc
abstract mixin class _$OutputModeCopyWith<$Res> implements $OutputModeCopyWith<$Res> {
  factory _$OutputModeCopyWith(_OutputMode value, $Res Function(_OutputMode) _then) = __$OutputModeCopyWithImpl;
@override @useResult
$Res call({
 OutputKind kind, bool subtitleSidecars
});




}
/// @nodoc
class __$OutputModeCopyWithImpl<$Res>
    implements _$OutputModeCopyWith<$Res> {
  __$OutputModeCopyWithImpl(this._self, this._then);

  final _OutputMode _self;
  final $Res Function(_OutputMode) _then;

/// Create a copy of OutputMode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? subtitleSidecars = null,}) {
  return _then(_OutputMode(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as OutputKind,subtitleSidecars: null == subtitleSidecars ? _self.subtitleSidecars : subtitleSidecars // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$OutputName {

 String get baseName; List<String> get folders;
/// Create a copy of OutputName
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OutputNameCopyWith<OutputName> get copyWith => _$OutputNameCopyWithImpl<OutputName>(this as OutputName, _$identity);

  /// Serializes this OutputName to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OutputName&&(identical(other.baseName, baseName) || other.baseName == baseName)&&const DeepCollectionEquality().equals(other.folders, folders));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,baseName,const DeepCollectionEquality().hash(folders));

@override
String toString() {
  return 'OutputName(baseName: $baseName, folders: $folders)';
}


}

/// @nodoc
abstract mixin class $OutputNameCopyWith<$Res>  {
  factory $OutputNameCopyWith(OutputName value, $Res Function(OutputName) _then) = _$OutputNameCopyWithImpl;
@useResult
$Res call({
 String baseName, List<String> folders
});




}
/// @nodoc
class _$OutputNameCopyWithImpl<$Res>
    implements $OutputNameCopyWith<$Res> {
  _$OutputNameCopyWithImpl(this._self, this._then);

  final OutputName _self;
  final $Res Function(OutputName) _then;

/// Create a copy of OutputName
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? baseName = null,Object? folders = null,}) {
  return _then(_self.copyWith(
baseName: null == baseName ? _self.baseName : baseName // ignore: cast_nullable_to_non_nullable
as String,folders: null == folders ? _self.folders : folders // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [OutputName].
extension OutputNamePatterns on OutputName {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OutputName value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OutputName() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OutputName value)  $default,){
final _that = this;
switch (_that) {
case _OutputName():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OutputName value)?  $default,){
final _that = this;
switch (_that) {
case _OutputName() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String baseName,  List<String> folders)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OutputName() when $default != null:
return $default(_that.baseName,_that.folders);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String baseName,  List<String> folders)  $default,) {final _that = this;
switch (_that) {
case _OutputName():
return $default(_that.baseName,_that.folders);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String baseName,  List<String> folders)?  $default,) {final _that = this;
switch (_that) {
case _OutputName() when $default != null:
return $default(_that.baseName,_that.folders);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OutputName implements OutputName {
  const _OutputName({required this.baseName, final  List<String> folders = const []}): _folders = folders;
  factory _OutputName.fromJson(Map<String, dynamic> json) => _$OutputNameFromJson(json);

@override final  String baseName;
 final  List<String> _folders;
@override@JsonKey() List<String> get folders {
  if (_folders is EqualUnmodifiableListView) return _folders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_folders);
}


/// Create a copy of OutputName
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OutputNameCopyWith<_OutputName> get copyWith => __$OutputNameCopyWithImpl<_OutputName>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OutputNameToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OutputName&&(identical(other.baseName, baseName) || other.baseName == baseName)&&const DeepCollectionEquality().equals(other._folders, _folders));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,baseName,const DeepCollectionEquality().hash(_folders));

@override
String toString() {
  return 'OutputName(baseName: $baseName, folders: $folders)';
}


}

/// @nodoc
abstract mixin class _$OutputNameCopyWith<$Res> implements $OutputNameCopyWith<$Res> {
  factory _$OutputNameCopyWith(_OutputName value, $Res Function(_OutputName) _then) = __$OutputNameCopyWithImpl;
@override @useResult
$Res call({
 String baseName, List<String> folders
});




}
/// @nodoc
class __$OutputNameCopyWithImpl<$Res>
    implements _$OutputNameCopyWith<$Res> {
  __$OutputNameCopyWithImpl(this._self, this._then);

  final _OutputName _self;
  final $Res Function(_OutputName) _then;

/// Create a copy of OutputName
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? baseName = null,Object? folders = null,}) {
  return _then(_OutputName(
baseName: null == baseName ? _self.baseName : baseName // ignore: cast_nullable_to_non_nullable
as String,folders: null == folders ? _self._folders : folders // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$DownloadProgress {

 int get donePieces; int get totalPieces; int get bytes; int get totalBytes;/// Counted by pieces rather than bytes: a fragmented source's weight is
/// only an estimate from its bitrate.
 bool get segmented;
/// Create a copy of DownloadProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadProgressCopyWith<DownloadProgress> get copyWith => _$DownloadProgressCopyWithImpl<DownloadProgress>(this as DownloadProgress, _$identity);

  /// Serializes this DownloadProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadProgress&&(identical(other.donePieces, donePieces) || other.donePieces == donePieces)&&(identical(other.totalPieces, totalPieces) || other.totalPieces == totalPieces)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.segmented, segmented) || other.segmented == segmented));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,donePieces,totalPieces,bytes,totalBytes,segmented);

@override
String toString() {
  return 'DownloadProgress(donePieces: $donePieces, totalPieces: $totalPieces, bytes: $bytes, totalBytes: $totalBytes, segmented: $segmented)';
}


}

/// @nodoc
abstract mixin class $DownloadProgressCopyWith<$Res>  {
  factory $DownloadProgressCopyWith(DownloadProgress value, $Res Function(DownloadProgress) _then) = _$DownloadProgressCopyWithImpl;
@useResult
$Res call({
 int donePieces, int totalPieces, int bytes, int totalBytes, bool segmented
});




}
/// @nodoc
class _$DownloadProgressCopyWithImpl<$Res>
    implements $DownloadProgressCopyWith<$Res> {
  _$DownloadProgressCopyWithImpl(this._self, this._then);

  final DownloadProgress _self;
  final $Res Function(DownloadProgress) _then;

/// Create a copy of DownloadProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? donePieces = null,Object? totalPieces = null,Object? bytes = null,Object? totalBytes = null,Object? segmented = null,}) {
  return _then(_self.copyWith(
donePieces: null == donePieces ? _self.donePieces : donePieces // ignore: cast_nullable_to_non_nullable
as int,totalPieces: null == totalPieces ? _self.totalPieces : totalPieces // ignore: cast_nullable_to_non_nullable
as int,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,segmented: null == segmented ? _self.segmented : segmented // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadProgress].
extension DownloadProgressPatterns on DownloadProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadProgress value)  $default,){
final _that = this;
switch (_that) {
case _DownloadProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadProgress value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int donePieces,  int totalPieces,  int bytes,  int totalBytes,  bool segmented)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadProgress() when $default != null:
return $default(_that.donePieces,_that.totalPieces,_that.bytes,_that.totalBytes,_that.segmented);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int donePieces,  int totalPieces,  int bytes,  int totalBytes,  bool segmented)  $default,) {final _that = this;
switch (_that) {
case _DownloadProgress():
return $default(_that.donePieces,_that.totalPieces,_that.bytes,_that.totalBytes,_that.segmented);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int donePieces,  int totalPieces,  int bytes,  int totalBytes,  bool segmented)?  $default,) {final _that = this;
switch (_that) {
case _DownloadProgress() when $default != null:
return $default(_that.donePieces,_that.totalPieces,_that.bytes,_that.totalBytes,_that.segmented);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadProgress extends DownloadProgress {
  const _DownloadProgress({this.donePieces = 0, this.totalPieces = 0, this.bytes = 0, this.totalBytes = 0, this.segmented = false}): super._();
  factory _DownloadProgress.fromJson(Map<String, dynamic> json) => _$DownloadProgressFromJson(json);

@override@JsonKey() final  int donePieces;
@override@JsonKey() final  int totalPieces;
@override@JsonKey() final  int bytes;
@override@JsonKey() final  int totalBytes;
/// Counted by pieces rather than bytes: a fragmented source's weight is
/// only an estimate from its bitrate.
@override@JsonKey() final  bool segmented;

/// Create a copy of DownloadProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadProgressCopyWith<_DownloadProgress> get copyWith => __$DownloadProgressCopyWithImpl<_DownloadProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadProgress&&(identical(other.donePieces, donePieces) || other.donePieces == donePieces)&&(identical(other.totalPieces, totalPieces) || other.totalPieces == totalPieces)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.segmented, segmented) || other.segmented == segmented));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,donePieces,totalPieces,bytes,totalBytes,segmented);

@override
String toString() {
  return 'DownloadProgress(donePieces: $donePieces, totalPieces: $totalPieces, bytes: $bytes, totalBytes: $totalBytes, segmented: $segmented)';
}


}

/// @nodoc
abstract mixin class _$DownloadProgressCopyWith<$Res> implements $DownloadProgressCopyWith<$Res> {
  factory _$DownloadProgressCopyWith(_DownloadProgress value, $Res Function(_DownloadProgress) _then) = __$DownloadProgressCopyWithImpl;
@override @useResult
$Res call({
 int donePieces, int totalPieces, int bytes, int totalBytes, bool segmented
});




}
/// @nodoc
class __$DownloadProgressCopyWithImpl<$Res>
    implements _$DownloadProgressCopyWith<$Res> {
  __$DownloadProgressCopyWithImpl(this._self, this._then);

  final _DownloadProgress _self;
  final $Res Function(_DownloadProgress) _then;

/// Create a copy of DownloadProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? donePieces = null,Object? totalPieces = null,Object? bytes = null,Object? totalBytes = null,Object? segmented = null,}) {
  return _then(_DownloadProgress(
donePieces: null == donePieces ? _self.donePieces : donePieces // ignore: cast_nullable_to_non_nullable
as int,totalPieces: null == totalPieces ? _self.totalPieces : totalPieces // ignore: cast_nullable_to_non_nullable
as int,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,segmented: null == segmented ? _self.segmented : segmented // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$DownloadError {

 String get code; String? get message; int? get httpStatus;
/// Create a copy of DownloadError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadErrorCopyWith<DownloadError> get copyWith => _$DownloadErrorCopyWithImpl<DownloadError>(this as DownloadError, _$identity);

  /// Serializes this DownloadError to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,message,httpStatus);

@override
String toString() {
  return 'DownloadError(code: $code, message: $message, httpStatus: $httpStatus)';
}


}

/// @nodoc
abstract mixin class $DownloadErrorCopyWith<$Res>  {
  factory $DownloadErrorCopyWith(DownloadError value, $Res Function(DownloadError) _then) = _$DownloadErrorCopyWithImpl;
@useResult
$Res call({
 String code, String? message, int? httpStatus
});




}
/// @nodoc
class _$DownloadErrorCopyWithImpl<$Res>
    implements $DownloadErrorCopyWith<$Res> {
  _$DownloadErrorCopyWithImpl(this._self, this._then);

  final DownloadError _self;
  final $Res Function(DownloadError) _then;

/// Create a copy of DownloadError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = freezed,Object? httpStatus = freezed,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadError].
extension DownloadErrorPatterns on DownloadError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadError() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadError value)  $default,){
final _that = this;
switch (_that) {
case _DownloadError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadError value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadError() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String? message,  int? httpStatus)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadError() when $default != null:
return $default(_that.code,_that.message,_that.httpStatus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String? message,  int? httpStatus)  $default,) {final _that = this;
switch (_that) {
case _DownloadError():
return $default(_that.code,_that.message,_that.httpStatus);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String? message,  int? httpStatus)?  $default,) {final _that = this;
switch (_that) {
case _DownloadError() when $default != null:
return $default(_that.code,_that.message,_that.httpStatus);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadError implements DownloadError {
  const _DownloadError({required this.code, this.message, this.httpStatus});
  factory _DownloadError.fromJson(Map<String, dynamic> json) => _$DownloadErrorFromJson(json);

@override final  String code;
@override final  String? message;
@override final  int? httpStatus;

/// Create a copy of DownloadError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadErrorCopyWith<_DownloadError> get copyWith => __$DownloadErrorCopyWithImpl<_DownloadError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadErrorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,message,httpStatus);

@override
String toString() {
  return 'DownloadError(code: $code, message: $message, httpStatus: $httpStatus)';
}


}

/// @nodoc
abstract mixin class _$DownloadErrorCopyWith<$Res> implements $DownloadErrorCopyWith<$Res> {
  factory _$DownloadErrorCopyWith(_DownloadError value, $Res Function(_DownloadError) _then) = __$DownloadErrorCopyWithImpl;
@override @useResult
$Res call({
 String code, String? message, int? httpStatus
});




}
/// @nodoc
class __$DownloadErrorCopyWithImpl<$Res>
    implements _$DownloadErrorCopyWith<$Res> {
  __$DownloadErrorCopyWithImpl(this._self, this._then);

  final _DownloadError _self;
  final $Res Function(_DownloadError) _then;

/// Create a copy of DownloadError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = freezed,Object? httpStatus = freezed,}) {
  return _then(_DownloadError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$DownloadRecord {

/// The engine's own id, never reused; also the name of its folder.
 String get id;/// The app's identity for what is downloaded, unique among records:
/// asking for the same key again finds this record.
 String get key;/// What the download is shown and merged as.
 String get title; OutputName get name;/// The app's own data, kept and handed back as is.
 Map<String, Object?> get metadata; DownloadStatus get status; DownloadError? get error;@_SourceConverter() SourceRequest get source;/// When the source's link stops working, when the app knows it.
 DateTime? get expiresAt;/// The server refused the source's link: the next attempt asks the app
/// for a fresh one, whatever [expiresAt] says.
 bool get linkDead;@_TrackChoiceConverter() TrackChoice get tracks; OutputMode get output;/// The finished download: the package's master playlist or the file, as
/// the output sink stored it (a path, or whatever the sink understands).
 String? get outputLocator; OutputKind? get outputKind;/// The one file, written and not yet handed to the output sink: what a
/// kill between the two picks up from instead of merging again.
 String? get stagedPath; DownloadProgress get progress; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadRecordCopyWith<DownloadRecord> get copyWith => _$DownloadRecordCopyWithImpl<DownloadRecord>(this as DownloadRecord, _$identity);

  /// Serializes this DownloadRecord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.key, key) || other.key == key)&&(identical(other.title, title) || other.title == title)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.metadata, metadata)&&(identical(other.status, status) || other.status == status)&&(identical(other.error, error) || other.error == error)&&(identical(other.source, source) || other.source == source)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.linkDead, linkDead) || other.linkDead == linkDead)&&(identical(other.tracks, tracks) || other.tracks == tracks)&&(identical(other.output, output) || other.output == output)&&(identical(other.outputLocator, outputLocator) || other.outputLocator == outputLocator)&&(identical(other.outputKind, outputKind) || other.outputKind == outputKind)&&(identical(other.stagedPath, stagedPath) || other.stagedPath == stagedPath)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,key,title,name,const DeepCollectionEquality().hash(metadata),status,error,source,expiresAt,linkDead,tracks,output,outputLocator,outputKind,stagedPath,progress,createdAt,updatedAt);

@override
String toString() {
  return 'DownloadRecord(id: $id, key: $key, title: $title, name: $name, metadata: $metadata, status: $status, error: $error, source: $source, expiresAt: $expiresAt, linkDead: $linkDead, tracks: $tracks, output: $output, outputLocator: $outputLocator, outputKind: $outputKind, stagedPath: $stagedPath, progress: $progress, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $DownloadRecordCopyWith<$Res>  {
  factory $DownloadRecordCopyWith(DownloadRecord value, $Res Function(DownloadRecord) _then) = _$DownloadRecordCopyWithImpl;
@useResult
$Res call({
 String id, String key, String title, OutputName name, Map<String, Object?> metadata, DownloadStatus status, DownloadError? error,@_SourceConverter() SourceRequest source, DateTime? expiresAt, bool linkDead,@_TrackChoiceConverter() TrackChoice tracks, OutputMode output, String? outputLocator, OutputKind? outputKind, String? stagedPath, DownloadProgress progress, DateTime createdAt, DateTime updatedAt
});


$OutputNameCopyWith<$Res> get name;$DownloadErrorCopyWith<$Res>? get error;$OutputModeCopyWith<$Res> get output;$DownloadProgressCopyWith<$Res> get progress;

}
/// @nodoc
class _$DownloadRecordCopyWithImpl<$Res>
    implements $DownloadRecordCopyWith<$Res> {
  _$DownloadRecordCopyWithImpl(this._self, this._then);

  final DownloadRecord _self;
  final $Res Function(DownloadRecord) _then;

/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? key = null,Object? title = null,Object? name = null,Object? metadata = null,Object? status = null,Object? error = freezed,Object? source = null,Object? expiresAt = freezed,Object? linkDead = null,Object? tracks = null,Object? output = null,Object? outputLocator = freezed,Object? outputKind = freezed,Object? stagedPath = freezed,Object? progress = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as OutputName,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as DownloadError?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SourceRequest,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,linkDead: null == linkDead ? _self.linkDead : linkDead // ignore: cast_nullable_to_non_nullable
as bool,tracks: null == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as TrackChoice,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as OutputMode,outputLocator: freezed == outputLocator ? _self.outputLocator : outputLocator // ignore: cast_nullable_to_non_nullable
as String?,outputKind: freezed == outputKind ? _self.outputKind : outputKind // ignore: cast_nullable_to_non_nullable
as OutputKind?,stagedPath: freezed == stagedPath ? _self.stagedPath : stagedPath // ignore: cast_nullable_to_non_nullable
as String?,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as DownloadProgress,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}
/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OutputNameCopyWith<$Res> get name {
  
  return $OutputNameCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DownloadErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $DownloadErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OutputModeCopyWith<$Res> get output {
  
  return $OutputModeCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DownloadProgressCopyWith<$Res> get progress {
  
  return $DownloadProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [DownloadRecord].
extension DownloadRecordPatterns on DownloadRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadRecord value)  $default,){
final _that = this;
switch (_that) {
case _DownloadRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadRecord value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String key,  String title,  OutputName name,  Map<String, Object?> metadata,  DownloadStatus status,  DownloadError? error, @_SourceConverter()  SourceRequest source,  DateTime? expiresAt,  bool linkDead, @_TrackChoiceConverter()  TrackChoice tracks,  OutputMode output,  String? outputLocator,  OutputKind? outputKind,  String? stagedPath,  DownloadProgress progress,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadRecord() when $default != null:
return $default(_that.id,_that.key,_that.title,_that.name,_that.metadata,_that.status,_that.error,_that.source,_that.expiresAt,_that.linkDead,_that.tracks,_that.output,_that.outputLocator,_that.outputKind,_that.stagedPath,_that.progress,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String key,  String title,  OutputName name,  Map<String, Object?> metadata,  DownloadStatus status,  DownloadError? error, @_SourceConverter()  SourceRequest source,  DateTime? expiresAt,  bool linkDead, @_TrackChoiceConverter()  TrackChoice tracks,  OutputMode output,  String? outputLocator,  OutputKind? outputKind,  String? stagedPath,  DownloadProgress progress,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _DownloadRecord():
return $default(_that.id,_that.key,_that.title,_that.name,_that.metadata,_that.status,_that.error,_that.source,_that.expiresAt,_that.linkDead,_that.tracks,_that.output,_that.outputLocator,_that.outputKind,_that.stagedPath,_that.progress,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String key,  String title,  OutputName name,  Map<String, Object?> metadata,  DownloadStatus status,  DownloadError? error, @_SourceConverter()  SourceRequest source,  DateTime? expiresAt,  bool linkDead, @_TrackChoiceConverter()  TrackChoice tracks,  OutputMode output,  String? outputLocator,  OutputKind? outputKind,  String? stagedPath,  DownloadProgress progress,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _DownloadRecord() when $default != null:
return $default(_that.id,_that.key,_that.title,_that.name,_that.metadata,_that.status,_that.error,_that.source,_that.expiresAt,_that.linkDead,_that.tracks,_that.output,_that.outputLocator,_that.outputKind,_that.stagedPath,_that.progress,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadRecord extends DownloadRecord {
  const _DownloadRecord({required this.id, required this.key, required this.title, required this.name, final  Map<String, Object?> metadata = const {}, required this.status, this.error, @_SourceConverter() required this.source, this.expiresAt, this.linkDead = false, @_TrackChoiceConverter() this.tracks = const TrackChoice.policy(), this.output = const OutputMode(), this.outputLocator, this.outputKind, this.stagedPath, this.progress = const DownloadProgress(), required this.createdAt, required this.updatedAt}): _metadata = metadata,super._();
  factory _DownloadRecord.fromJson(Map<String, dynamic> json) => _$DownloadRecordFromJson(json);

/// The engine's own id, never reused; also the name of its folder.
@override final  String id;
/// The app's identity for what is downloaded, unique among records:
/// asking for the same key again finds this record.
@override final  String key;
/// What the download is shown and merged as.
@override final  String title;
@override final  OutputName name;
/// The app's own data, kept and handed back as is.
 final  Map<String, Object?> _metadata;
/// The app's own data, kept and handed back as is.
@override@JsonKey() Map<String, Object?> get metadata {
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_metadata);
}

@override final  DownloadStatus status;
@override final  DownloadError? error;
@override@_SourceConverter() final  SourceRequest source;
/// When the source's link stops working, when the app knows it.
@override final  DateTime? expiresAt;
/// The server refused the source's link: the next attempt asks the app
/// for a fresh one, whatever [expiresAt] says.
@override@JsonKey() final  bool linkDead;
@override@JsonKey()@_TrackChoiceConverter() final  TrackChoice tracks;
@override@JsonKey() final  OutputMode output;
/// The finished download: the package's master playlist or the file, as
/// the output sink stored it (a path, or whatever the sink understands).
@override final  String? outputLocator;
@override final  OutputKind? outputKind;
/// The one file, written and not yet handed to the output sink: what a
/// kill between the two picks up from instead of merging again.
@override final  String? stagedPath;
@override@JsonKey() final  DownloadProgress progress;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadRecordCopyWith<_DownloadRecord> get copyWith => __$DownloadRecordCopyWithImpl<_DownloadRecord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadRecordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.key, key) || other.key == key)&&(identical(other.title, title) || other.title == title)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&(identical(other.status, status) || other.status == status)&&(identical(other.error, error) || other.error == error)&&(identical(other.source, source) || other.source == source)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.linkDead, linkDead) || other.linkDead == linkDead)&&(identical(other.tracks, tracks) || other.tracks == tracks)&&(identical(other.output, output) || other.output == output)&&(identical(other.outputLocator, outputLocator) || other.outputLocator == outputLocator)&&(identical(other.outputKind, outputKind) || other.outputKind == outputKind)&&(identical(other.stagedPath, stagedPath) || other.stagedPath == stagedPath)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,key,title,name,const DeepCollectionEquality().hash(_metadata),status,error,source,expiresAt,linkDead,tracks,output,outputLocator,outputKind,stagedPath,progress,createdAt,updatedAt);

@override
String toString() {
  return 'DownloadRecord(id: $id, key: $key, title: $title, name: $name, metadata: $metadata, status: $status, error: $error, source: $source, expiresAt: $expiresAt, linkDead: $linkDead, tracks: $tracks, output: $output, outputLocator: $outputLocator, outputKind: $outputKind, stagedPath: $stagedPath, progress: $progress, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$DownloadRecordCopyWith<$Res> implements $DownloadRecordCopyWith<$Res> {
  factory _$DownloadRecordCopyWith(_DownloadRecord value, $Res Function(_DownloadRecord) _then) = __$DownloadRecordCopyWithImpl;
@override @useResult
$Res call({
 String id, String key, String title, OutputName name, Map<String, Object?> metadata, DownloadStatus status, DownloadError? error,@_SourceConverter() SourceRequest source, DateTime? expiresAt, bool linkDead,@_TrackChoiceConverter() TrackChoice tracks, OutputMode output, String? outputLocator, OutputKind? outputKind, String? stagedPath, DownloadProgress progress, DateTime createdAt, DateTime updatedAt
});


@override $OutputNameCopyWith<$Res> get name;@override $DownloadErrorCopyWith<$Res>? get error;@override $OutputModeCopyWith<$Res> get output;@override $DownloadProgressCopyWith<$Res> get progress;

}
/// @nodoc
class __$DownloadRecordCopyWithImpl<$Res>
    implements _$DownloadRecordCopyWith<$Res> {
  __$DownloadRecordCopyWithImpl(this._self, this._then);

  final _DownloadRecord _self;
  final $Res Function(_DownloadRecord) _then;

/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? key = null,Object? title = null,Object? name = null,Object? metadata = null,Object? status = null,Object? error = freezed,Object? source = null,Object? expiresAt = freezed,Object? linkDead = null,Object? tracks = null,Object? output = null,Object? outputLocator = freezed,Object? outputKind = freezed,Object? stagedPath = freezed,Object? progress = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_DownloadRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as OutputName,metadata: null == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as DownloadError?,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SourceRequest,expiresAt: freezed == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as DateTime?,linkDead: null == linkDead ? _self.linkDead : linkDead // ignore: cast_nullable_to_non_nullable
as bool,tracks: null == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as TrackChoice,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as OutputMode,outputLocator: freezed == outputLocator ? _self.outputLocator : outputLocator // ignore: cast_nullable_to_non_nullable
as String?,outputKind: freezed == outputKind ? _self.outputKind : outputKind // ignore: cast_nullable_to_non_nullable
as OutputKind?,stagedPath: freezed == stagedPath ? _self.stagedPath : stagedPath // ignore: cast_nullable_to_non_nullable
as String?,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as DownloadProgress,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OutputNameCopyWith<$Res> get name {
  
  return $OutputNameCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DownloadErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $DownloadErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OutputModeCopyWith<$Res> get output {
  
  return $OutputModeCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}/// Create a copy of DownloadRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DownloadProgressCopyWith<$Res> get progress {
  
  return $DownloadProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

// dart format on
