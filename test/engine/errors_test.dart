import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul/haul.dart';

void main() {
  group('isOutOfSpace', () {
    test('by the errno of each platform', () {
      for (final code in [28, 112, 39]) {
        expect(
          isOutOfSpace(FileSystemException('write', '/x', OSError('', code))),
          isTrue,
          reason: '$code',
        );
      }
      expect(
        isOutOfSpace(FileSystemException('write', '/x', const OSError('', 13))),
        isFalse,
      );
    });

    test('by the words, when the errno was lost', () {
      for (final text in [
        'No space left on device',
        'error: ENOSPC',
        'There is not enough space on the disk.',
        'Disk full',
        'SQLITE_FULL: database or disk is full',
      ]) {
        expect(isOutOfSpace(text), isTrue, reason: text);
        expect(isOutOfSpace(Exception(text)), isTrue, reason: text);
      }
      expect(isOutOfSpace('Permission denied'), isFalse);
      expect(isOutOfSpace(const FileSystemException('gone')), isFalse);
    });
  });

  group('downloadErrorOf', () {
    DownloadError of(String code) => downloadErrorOf(SourceException(code));

    test('a source that cannot be had is unavailable', () {
      for (final code in [
        SourceErrorCode.drm,
        SourceErrorCode.live,
        SourceErrorCode.empty,
        SourceErrorCode.unsupported,
      ]) {
        expect(of(code).code, DownloadErrorCode.unavailable, reason: code);
      }
    });

    test('the other source codes', () {
      expect(of(SourceErrorCode.network).code, DownloadErrorCode.network);
      expect(of(SourceErrorCode.missingPieces).code, DownloadErrorCode.corrupt);
      expect(
        of(SourceErrorCode.http(403)),
        const DownloadError(code: DownloadErrorCode.http, httpStatus: 403),
      );
      expect(of('something_new').code, DownloadErrorCode.unknown);
    });

    test('a full disk wins over what it came wrapped in', () {
      expect(
        downloadErrorOf(
          const SourceException(SourceErrorCode.network, 'No space left'),
        ).code,
        DownloadErrorCode.noSpace,
      );
      expect(
        downloadErrorOf(
          const FileSystemException('write', '/x', OSError('', 28)),
        ).code,
        DownloadErrorCode.noSpace,
      );
    });

    test('network failures from outside the fetcher', () {
      for (final error in <Object>[
        const SocketException('Failed host lookup'),
        const HttpException('Connection closed'),
        TimeoutException('refresh'),
      ]) {
        expect(
          downloadErrorOf(error).code,
          DownloadErrorCode.network,
          reason: '$error',
        );
      }
    });

    test('anything else is unknown', () {
      expect(downloadErrorOf(StateError('x')).code, DownloadErrorCode.unknown);
      expect(
        downloadErrorOf(const FileSystemException('denied')).code,
        DownloadErrorCode.unknown,
      );
    });
  });
}
