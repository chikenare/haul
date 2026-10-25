import 'package:flutter/widgets.dart';
import 'package:haul/src/engine/errors.dart';
import 'package:haul/src/engine/model.dart';

/// Every text haul's widgets show, in English. [HaulStrings.of] picks
/// Spanish ([HaulStringsEs]) for an `es` locale.
///
/// To change any of them — or add a language — extend this class (or
/// [HaulStringsEs]) and override what differs, then hand it to
/// `HaulScope(strings:)`. [error] is where an app's own error codes (from a
/// `RefreshException`) get their text, and [section] where a section id
/// (`'1'`) becomes `Season 1`.
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
  String get cancel => 'Cancel';
  String get pauseAll => 'Pause all';
  String get resumeAll => 'Resume all';
  String get deleteAll => 'Delete all';

  // Lists
  String get empty => 'Nothing downloaded yet';
  String downloads(int count) => count == 1 ? '1 download' : '$count downloads';

  /// How a section of a group is headed. The id as it is by default.
  String section(String id) => id;

  String deleteConfirm(String title) => 'Delete "$title"?';
  String deleteGroupConfirm(String title, int count) =>
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

  // Settings and the first-download sheet
  String get setupTitle => 'Before your first download';
  String get setupIntro => 'You can change all of this later in the settings.';
  String get format => 'Format';
  String get formatApp => 'To watch in the app';
  String get formatAppHint => 'Ready sooner. Only this app plays it.';
  String get formatFile => 'One file (MKV)';
  String get formatFileHint =>
      'Takes a few more seconds at the end. Opens in other players.';
  String get destination => 'Where files go';
  String get destinationPublic => 'Downloads';
  String get destinationPublicHint => 'In the Downloads folder of the device.';
  String get destinationApp => 'Only in the app';
  String get destinationAppHint => 'Nothing else sees them.';
  String get destinationFolder => 'A folder of my choice';
  String get destinationFolderHint => 'Pick it now.';
  String get destinationFolderLost =>
      'That folder can no longer be written to. Pick it again.';
  String get changeFolder => 'Change';
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
  String deleteConfirm(String title) => '¿Eliminar «$title»?';
  @override
  String deleteGroupConfirm(String title, int count) =>
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
  String get destination => 'Dónde se guardan';
  @override
  String get destinationPublic => 'Descargas';
  @override
  String get destinationPublicHint =>
      'En la carpeta Descargas del dispositivo.';
  @override
  String get destinationApp => 'Solo en la app';
  @override
  String get destinationAppHint => 'Nadie más los ve.';
  @override
  String get destinationFolder => 'Una carpeta que elija';
  @override
  String get destinationFolderHint => 'Elígela ahora.';
  @override
  String get destinationFolderLost =>
      'Ya no se puede escribir en esa carpeta. Elígela de nuevo.';
  @override
  String get changeFolder => 'Cambiar';
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
