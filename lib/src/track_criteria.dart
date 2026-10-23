import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Which audios or subtitles a download keeps.
@immutable
sealed class TrackPreference {
  const TrackPreference();

  /// From a stored value: `all`, `none` or `lang:es-419,en`.
  static TrackPreference parse(String? value) => switch (value) {
    null || 'all' => const AllTracks(),
    'none' => const NoTracks(),
    _ when value.startsWith(_languagePrefix) => LanguageTracks(
      value.substring(_languagePrefix.length).split(','),
    ),
    _ => const AllTracks(),
  };

  /// As an app or an account sends it: `all`, `none` or a list of BCP-47
  /// tags (`es-419`, `en-US`). Null when there is nothing to go by, so the
  /// caller falls back to its own default.
  static TrackPreference? fromTags(List<String>? tags) {
    if (tags == null || tags.isEmpty) return null;
    if (tags.contains('all')) return const AllTracks();
    final languages = [
      for (final tag in tags)
        if (tag != 'none') tag,
    ];
    return languages.isEmpty ? const NoTracks() : LanguageTracks(languages);
  }

  String encode() => switch (this) {
    AllTracks() => 'all',
    NoTracks() => 'none',
    LanguageTracks(:final languages) =>
      '$_languagePrefix${languages.join(',')}',
  };

  static const _languagePrefix = 'lang:';
}

final class AllTracks extends TrackPreference {
  const AllTracks();

  @override
  bool operator ==(Object other) => other is AllTracks;

  @override
  int get hashCode => 0;
}

final class NoTracks extends TrackPreference {
  const NoTracks();

  @override
  bool operator ==(Object other) => other is NoTracks;

  @override
  int get hashCode => 1;
}

/// The tracks of one or more languages (BCP-47), each on its own. With a
/// region (`es-419`) that variant is preferred; without one (`es`) every
/// track of the language counts.
final class LanguageTracks extends TrackPreference {
  const LanguageTracks(this.languages);

  final List<String> languages;

  @override
  bool operator ==(Object other) =>
      other is LanguageTracks &&
      const ListEquality<String>().equals(other.languages, languages);

  @override
  int get hashCode => Object.hashAll(languages);
}

/// What quality and tracks are picked from a source.
@immutable
class TrackCriteria {
  const TrackCriteria({
    this.maxHeight,
    this.audio = const AllTracks(),
    this.subtitles = const AllTracks(),
  });

  /// The best quality not above this height; null is the best there is.
  final int? maxHeight;

  /// Never leaves a video silent: with nothing matching, the default audio
  /// is kept (see `ResolvedSource.selectionFor`).
  final TrackPreference audio;
  final TrackPreference subtitles;

  @override
  bool operator ==(Object other) =>
      other is TrackCriteria &&
      other.maxHeight == maxHeight &&
      other.audio == audio &&
      other.subtitles == subtitles;

  @override
  int get hashCode => Object.hash(maxHeight, audio, subtitles);
}
