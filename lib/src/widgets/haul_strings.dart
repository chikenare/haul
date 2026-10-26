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
  String get inApp => 'In the app';

  // Actions
  String get download => 'Download';
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

  // Settings and the first-download sheet
  String get setupTitle => 'Before your first download';
  String get setupIntro => 'You can change all of this later in the settings.';
  String get format => 'Format';
  String get formatApp => 'To watch in the app';
  String get formatAppHint => 'Ready sooner. Only this app plays it.';
  String get formatFile => 'One file (MKV)';
  String get formatFileHint =>
      'Takes a few more seconds at the end. Opens in other players.';

  /// Before turning [formatFile] on (`HaulFormatTile(confirm: true)`).
  String get formatFileConfirmTitle => 'Save as one file?';
  String get formatFileConfirm =>
      'The file is put together at the end of each download: keep the app '
      'open while it is, and leave room for twice its size.';
  String get formatFileConfirmAction => 'Turn on';
  String freeSpace(String bytes) => 'Free: $bytes';
  String get destination => 'Where files go';

  /// Where files go until the user picks a folder: no permission needed.
  String get destinationDefault => 'Default folder';
  String get destinationApp => 'Only in the app';
  String get destinationFolderLost =>
      'That folder can no longer be written to. Pick it again.';
  String get useDefaultFolder => 'Use the default folder';
  String get wifiOnly => 'Only on Wi-Fi';
  String get wifiOnlyHint => 'Nothing is downloaded on mobile data.';
  String get battery => 'Download in the background';
  String get batteryHint =>
      'The battery saver may stop downloads while the app is closed.';
  String get batteryAction => 'Allow';
  String get batteryDone => 'Allowed';

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
  String get inApp => 'En la app';

  @override
  String get download => 'Descargar';
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

  @override
  String get setupTitle => 'Antes de tu primera descarga';
  @override
  String get setupIntro => 'Puedes cambiar todo esto después en los ajustes.';
  @override
  String get format => 'Formato';
  @override
  String get formatApp => 'Para ver en la app';
  @override
  String get formatAppHint => 'Está lista antes. Solo esta app la reproduce.';
  @override
  String get formatFile => 'Un archivo (MKV)';
  @override
  String get formatFileHint =>
      'Tarda unos segundos más al terminar. Se abre con otros reproductores.';
  @override
  String get formatFileConfirmTitle => '¿Guardar como un archivo?';
  @override
  String get formatFileConfirm =>
      'El archivo se arma al final de cada descarga: deja la app abierta '
      'mientras tanto y deja espacio para el doble de su tamaño.';
  @override
  String get formatFileConfirmAction => 'Activar';
  @override
  String freeSpace(String bytes) => 'Libre: $bytes';
  @override
  String get destination => 'Dónde se guardan';
  @override
  String get destinationDefault => 'Carpeta por defecto';
  @override
  String get destinationApp => 'Solo en la app';
  @override
  String get destinationFolderLost =>
      'Ya no se puede escribir en esa carpeta. Elígela de nuevo.';
  @override
  String get useDefaultFolder => 'Usar la carpeta por defecto';
  @override
  String get wifiOnly => 'Solo con Wi-Fi';
  @override
  String get wifiOnlyHint => 'No se descarga nada con datos móviles.';
  @override
  String get battery => 'Descargar en segundo plano';
  @override
  String get batteryHint =>
      'El ahorro de batería puede frenar las descargas con la app cerrada.';
  @override
  String get batteryAction => 'Permitir';
  @override
  String get batteryDone => 'Permitido';
}
