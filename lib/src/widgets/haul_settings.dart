import 'package:flutter/foundation.dart';
import 'package:haul/src/engine/haul_output_sink.dart';
import 'package:haul/src/engine/model.dart';

/// The user's download settings, as one value. haul does not store it:
/// the app keeps [toJson] wherever it keeps its preferences and hands it to
/// a [HaulSettingsController].
@immutable
class HaulSettings {
  const HaulSettings({
    this.merge = false,
    this.destination = const HaulDestination.public(),
    this.wifiOnly = false,
    this.setupDone = false,
  });

  factory HaulSettings.fromJson(Map<String, Object?> json) => HaulSettings(
    merge: json['merge'] as bool? ?? false,
    destination: switch (json['destination']) {
      final Map<String, Object?> d => HaulDestination.fromJson(d),
      _ => const HaulDestination.public(),
    },
    wifiOnly: json['wifiOnly'] as bool? ?? false,
    setupDone: json['setupDone'] as bool? ?? false,
  );

  /// One file (MKV, or the source's own) rather than the local package the
  /// app plays — which is ready sooner and is only seen by the app.
  final bool merge;

  /// Where one file goes; a package always stays in the app.
  final HaulDestination destination;
  final bool wifiOnly;

  /// The first-download sheet was accepted once (see `ensureHaulSetup`).
  final bool setupDone;

  /// What a download asked for now becomes. [subtitleSidecars]: also keep
  /// the subtitles beside the file, for players that only style those.
  OutputMode output({bool subtitleSidecars = false}) => merge
      ? OutputMode(kind: OutputKind.file, subtitleSidecars: subtitleSidecars)
      : OutputMode.package;

  HaulSettings copyWith({
    bool? merge,
    HaulDestination? destination,
    bool? wifiOnly,
    bool? setupDone,
  }) => HaulSettings(
    merge: merge ?? this.merge,
    destination: destination ?? this.destination,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    setupDone: setupDone ?? this.setupDone,
  );

  Map<String, Object?> toJson() => {
    'merge': merge,
    'destination': destination.toJson(),
    'wifiOnly': wifiOnly,
    'setupDone': setupDone,
  };

  @override
  bool operator ==(Object other) =>
      other is HaulSettings &&
      other.merge == merge &&
      other.destination == destination &&
      other.wifiOnly == wifiOnly &&
      other.setupDone == setupDone;

  @override
  int get hashCode => Object.hash(merge, destination, wifiOnly, setupDone);
}

/// The settings the widgets read and change. [onChanged] is where the app
/// stores them. Hand [wifiOnly] to `DownloadEngine(wifiOnly:)` and
/// `() async => controller.value.destination` to `HaulOutputSink`.
class HaulSettingsController extends ValueNotifier<HaulSettings> {
  HaulSettingsController([super.value = const HaulSettings(), this.onChanged]);

  /// Called with every new value, to store it.
  final void Function(HaulSettings settings)? onChanged;

  late final ValueListenable<bool> wifiOnly = _Selected(
    this,
    (s) => s.wifiOnly,
  );

  void update(HaulSettings Function(HaulSettings settings) change) {
    final next = change(value);
    if (next == value) return;
    value = next;
    onChanged?.call(next);
  }
}

/// One field of a [ValueListenable], notifying only when it changes.
class _Selected<T, R> extends ChangeNotifier implements ValueListenable<R> {
  _Selected(this._source, this._select) : _value = _select(_source.value) {
    _source.addListener(_onSource);
  }

  final ValueListenable<T> _source;
  final R Function(T) _select;
  R _value;

  void _onSource() {
    final next = _select(_source.value);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  R get value => _value;

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}
