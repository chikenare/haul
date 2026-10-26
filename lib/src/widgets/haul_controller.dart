import 'package:flutter/material.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/download_engine.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/haul_strings.dart';

/// What haul's download list works with: the engine, and how the app
/// wants things said and done. The app makes one — at start, next
/// to its engine — keeps it however it keeps its state (Riverpod, a
/// singleton…) and hands it to each widget as `controller:`.
class HaulController {
  HaulController({
    required this.engine,
    this.strings,
    this.android = HaulAndroid.i,
    this.canRetry,
  });

  final DownloadEngine engine;

  /// Null: [HaulStrings.forLocale] of the app's locale.
  final HaulStrings? strings;
  final HaulAndroid android;

  /// Whether a failed download is worth retrying; by default every one
  /// is. An app answers false for its own codes a retry would not change
  /// (an allowance spent).
  final bool Function(DownloadError error)? canRetry;

  /// [strings], or the built-in ones for the locale of [context].
  HaulStrings stringsOf(BuildContext context) =>
      strings ??
      HaulStrings.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      );
}

/// How haul's widgets look, on top of the app's `ThemeData` — colours and
/// text come from its `ColorScheme` and `TextTheme` unless set here. Add
/// it to `ThemeData.extensions`.
@immutable
class HaulTheme extends ThemeExtension<HaulTheme> {
  const HaulTheme({
    this.thumbnailSize = const Size(112, 63),
    this.thumbnailRadius = 6,
    this.tilePadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.progressColor,
    this.errorColor,
    this.placeholderIcon = Icons.movie_outlined,
  });

  final Size thumbnailSize;
  final double thumbnailRadius;
  final EdgeInsets tilePadding;

  /// Null: the scheme's primary.
  final Color? progressColor;

  /// Null: the scheme's error.
  final Color? errorColor;
  final IconData placeholderIcon;

  static HaulTheme of(BuildContext context) =>
      Theme.of(context).extension<HaulTheme>() ?? const HaulTheme();

  Color progressOf(BuildContext context) =>
      progressColor ?? Theme.of(context).colorScheme.primary;

  Color errorOf(BuildContext context) =>
      errorColor ?? Theme.of(context).colorScheme.error;

  @override
  HaulTheme copyWith({
    Size? thumbnailSize,
    double? thumbnailRadius,
    EdgeInsets? tilePadding,
    Color? progressColor,
    Color? errorColor,
    IconData? placeholderIcon,
  }) => HaulTheme(
    thumbnailSize: thumbnailSize ?? this.thumbnailSize,
    thumbnailRadius: thumbnailRadius ?? this.thumbnailRadius,
    tilePadding: tilePadding ?? this.tilePadding,
    progressColor: progressColor ?? this.progressColor,
    errorColor: errorColor ?? this.errorColor,
    placeholderIcon: placeholderIcon ?? this.placeholderIcon,
  );

  @override
  HaulTheme lerp(HaulTheme? other, double t) {
    if (other == null) return this;
    return HaulTheme(
      thumbnailSize: Size.lerp(thumbnailSize, other.thumbnailSize, t)!,
      thumbnailRadius:
          thumbnailRadius + (other.thumbnailRadius - thumbnailRadius) * t,
      tilePadding: EdgeInsets.lerp(tilePadding, other.tilePadding, t)!,
      progressColor: Color.lerp(progressColor, other.progressColor, t),
      errorColor: Color.lerp(errorColor, other.errorColor, t),
      placeholderIcon: t < 0.5 ? placeholderIcon : other.placeholderIcon,
    );
  }
}
