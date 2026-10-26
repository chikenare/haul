import 'dart:io';

import 'package:haul/src/engine/extension_points.dart';

/// [ImageFetcher] over `dart:io`. A picture is not worth waiting long for:
/// it gives up after [timeout].
class HttpImageFetcher implements ImageFetcher {
  const HttpImageFetcher({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<bool> fetch(String url, File file) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      return false;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final temp = File('${file.path}.tmp');
    try {
      final response = await (await client.getUrl(
        uri,
      )).close().timeout(timeout);
      // Many CDNs serve pictures as `octet-stream`; an error page is what
      // is not one.
      final type = response.headers.contentType?.primaryType;
      if (response.statusCode != HttpStatus.ok || type == 'text') {
        await response.drain<void>();
        return false;
      }
      await temp.parent.create(recursive: true);
      // The response itself times out, so the sink is never left bound
      // to it and always closes: the file is not kept open.
      final sink = temp.openWrite();
      try {
        await sink.addStream(response.timeout(timeout));
      } finally {
        await sink.close();
      }
      await temp.rename(file.path);
      return true;
    } on Object {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Gone with the folder.
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
