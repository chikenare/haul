import 'package:flutter/widgets.dart';
import 'package:haul/src/engine/errors.dart';
import 'package:haul/src/engine/model.dart';
import 'package:haul/src/planner/errors.dart';

/// Every text haul's widgets show, in English. [HaulStrings.of] picks
/// Spanish ([HaulStringsEs]) for an `es` locale.
///
/// To change any of them — or add a language — extend this class (or
/// [HaulStringsEs]) and override what differs, then hand it to
/// `HaulController(strings:)`. [error] is where an app's own error codes (from a
/// `RefreshException`) get their text.
class HaulStrings {
  const HaulStrings();

  /// Built-in strings for [locale]: Spanish for `es`, English otherwise.
  static HaulStrings forLocale(Locale locale) =>
      locale.languageCode == 'es' ? const HaulStringsEs() : const HaulStrings();

  // Status
  String status(DownloadStatus status) => switch (status) {
    DownloadStatus.queued => 'Queued',
    DownloadStatus.resolving => 'Preparing',
    DownloadStatus.downloading => 'Downloading',
    DownloadStatus.paused => 'Paused',
    DownloadStatus.assembling => 'Finishing',
    DownloadStatus.done => 'Downloaded',
    DownloadStatus.failed => 'Failed',
  };
  String get waitingForWifi => 'Waiting for Wi-Fi';

  /// A finished package, which only the app plays.

  String get pause => 'Pause';
  String get resume => 'Resume';
  String get retry => 'Retry';
  String get play => 'Play';
  String get delete => 'Delete';
  String get removeKeepFile => 'Remove from list, keep the file';
  String get export => 'Save as a file';
  String get exported => 'Saved as a file';
  String get cancel => 'Cancel';
  String get pauseAll => 'Pause all';
  String get resumeAll => 'Resume all';
  String get deleteAll => 'Delete all';

  // Lists
  String get empty => 'Nothing downloaded yet';
  String downloads(int count) => count == 1 ? '1 download' : '$count downloads';

  /// A parent's or a season's progress: `3 of 5 downloaded`.
  String doneOf(int done, int total) => '$done of $total downloaded';

  String deleteConfirm(String title) => 'Delete "$title"?';
  String deleteParentConfirm(String title, int count) =>
      'Delete the ${downloads(count)} of "$title"?';

  // Errors
  String error(DownloadError error) => switch (error.code) {
    DownloadErrorCode.network => 'No connection. It goes on when it can.',
    DownloadErrorCode.http => 'The server refused it (${error.httpStatus}).',
    DownloadErrorCode.noSpace => 'Not enough space on the device.',
    DownloadErrorCode.mux => 'The file could not be put together.',
    DownloadErrorCode.unavailable => 'This video cannot be downloaded.',
    DownloadErrorCode.corrupt => 'The download came back damaged.',
    DownloadErrorCode.publish => 'The file could not be saved in its folder.',
    _ => error.message ?? 'Something went wrong.',
  };

  /// Why a source could not be read, before anything was asked for: from a
  /// `SourceException` the planner threw; anything else is the generic
  /// text.
  String sourceError(Object error) {
    final code = error is SourceException ? error.code : null;
    if (code != null) {
      if (SourceErrorCode.httpStatus(code) case final status?) {
        return 'The server refused it ($status).';
      }
    }
    return switch (code) {
      SourceErrorCode.drm => 'This video is protected and cannot be saved.',
      SourceErrorCode.live => 'A live stream cannot be downloaded.',
      SourceErrorCode.empty => 'There is nothing to download in this video.',
      SourceErrorCode.unsupported => 'This video format is not supported.',
      SourceErrorCode.network => 'No connection. Try again later.',
      SourceErrorCode.missingPieces => 'Part of the video is missing.',
      _ => 'Something went wrong.',
    };
  }

  /// `1.2 GB`.
  String bytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
      value /= 1000;
      unit++;
    }
    final digits = unit == 0 || value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

class HaulStringsEs extends HaulStrings {
  const HaulStringsEs();

  @override
  String status(DownloadStatus status) => switch (status) {
    DownloadStatus.queued => 'En cola',
    DownloadStatus.resolving => 'Preparando',
    DownloadStatus.downloading => 'Descargando',
    DownloadStatus.paused => 'En pausa',
    DownloadStatus.assembling => 'Terminando',
    DownloadStatus.done => 'Descargado',
    DownloadStatus.failed => 'Falló',
  };
  @override
  String get waitingForWifi => 'Esperando Wi-Fi';
  @override
  @override
  String get pause => 'Pausar';
  @override
  String get resume => 'Reanudar';
  @override
  String get retry => 'Reintentar';
  @override
  String get play => 'Reproducir';
  @override
  String get delete => 'Eliminar';
  @override
  String get removeKeepFile => 'Quitar de la lista y conservar el archivo';
  @override
  String get export => 'Guardar como archivo';
  @override
  String get exported => 'Guardado como archivo';
  @override
  String get cancel => 'Cancelar';
  @override
  String get pauseAll => 'Pausar todo';
  @override
  String get resumeAll => 'Reanudar todo';
  @override
  String get deleteAll => 'Eliminar todo';

  @override
  String get empty => 'Todavía no descargaste nada';
  @override
  String downloads(int count) => count == 1 ? '1 descarga' : '$count descargas';
  @override
  String doneOf(int done, int total) => '$done de $total descargados';

  @override
  String deleteConfirm(String title) => '¿Eliminar «$title»?';
  @override
  String deleteParentConfirm(String title, int count) =>
      '¿Eliminar las ${downloads(count)} de «$title»?';

  @override
  String error(DownloadError error) => switch (error.code) {
    DownloadErrorCode.network => 'Sin conexión. Sigue cuando pueda.',
    DownloadErrorCode.http => 'El servidor lo rechazó (${error.httpStatus}).',
    DownloadErrorCode.noSpace => 'No queda espacio en el dispositivo.',
    DownloadErrorCode.mux => 'No se pudo armar el archivo.',
    DownloadErrorCode.unavailable => 'Este video no se puede descargar.',
    DownloadErrorCode.corrupt => 'La descarga llegó dañada.',
    DownloadErrorCode.publish => 'No se pudo guardar el archivo en su carpeta.',
    _ => error.message ?? 'Algo salió mal.',
  };

  @override
  String sourceError(Object error) {
    final code = error is SourceException ? error.code : null;
    if (code != null) {
      if (SourceErrorCode.httpStatus(code) case final status?) {
        return 'El servidor lo rechazó ($status).';
      }
    }
    return switch (code) {
      SourceErrorCode.drm => 'Este video está protegido y no se puede guardar.',
      SourceErrorCode.live => 'Una transmisión en vivo no se puede descargar.',
      SourceErrorCode.empty => 'No hay nada que descargar en este video.',
      SourceErrorCode.unsupported =>
        'El formato de este video no es compatible.',
      SourceErrorCode.network => 'Sin conexión. Inténtalo más tarde.',
      SourceErrorCode.missingPieces => 'Falta una parte del video.',
      _ => 'Algo salió mal.',
    };
  }
}
