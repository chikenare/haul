import 'package:flutter/material.dart';
import 'package:haul/src/android/haul_android.dart';
import 'package:haul/src/engine/download_engine.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/widgets/haul_settings.dart';
import 'package:haul/src/widgets/haul_strings.dart';

/// Picks a folder on desktop (the app's own file picker); null when the
/// user backs out.
typedef DirectoryPicker = Future<String?> Function();

/// What haul's widgets below it share: the engine, the user's settings,
/// and how the app wants things said and done. Put it once above the
/// screens that show downloads.
class HaulScope extends InheritedWidget {
  const HaulScope({
    super.key,
    required this.engine,
    this.settings,
    this.strings,
    this.android = HaulAndroid.i,
    this.pickDirectory,
    this.canRetry,
    required super.child,
  });

  final DownloadEngine engine;

  /// Needed by the setup sheet and the settings tiles.
  final HaulSettingsController? settings;

  /// Null: [HaulStrings.forLocale] of the app's locale.
  final HaulStrings? strings;
  final HaulAndroid android;

  /// Offers "a folder of my choice" on desktop, where haul brings no
  /// picker of its own. Android uses the system's.
  final DirectoryPicker? pickDirectory;

  /// Whether a failed download is worth retrying; by default every one
  /// is. An app answers false for its own codes a retry would not change
  /// (an allowance spent).
  final bool Function(DownloadError error)? canRetry;

  static HaulScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HaulScope>();
    assert(scope != null, 'No HaulScope above this widget');
    return scope!;
  }

  /// [strings], or the built-in ones for the app's locale.
  static HaulStrings stringsOf(BuildContext context) =>
      of(context).strings ??
      HaulStrings.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      );

  @override
  bool updateShouldNotify(HaulScope oldWidget) =>
      engine != oldWidget.engine ||
      settings != oldWidget.settings ||
      strings != oldWidget.strings ||
      android != oldWidget.android ||
      pickDirectory != oldWidget.pickDirectory ||
      canRetry != oldWidget.canRetry;
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
