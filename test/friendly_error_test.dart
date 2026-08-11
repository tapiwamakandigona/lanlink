import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/util/friendly_error.dart';

void main() {
  group('friendlyTransferError', () {
    final req = RequestOptions(path: '/x');

    test('connection timeout is plain English and mentions the peer', () {
      final msg = friendlyTransferError(
        DioException(
            requestOptions: req, type: DioExceptionType.connectionTimeout),
        peerName: "Tapiwa's phone",
      );
      expect(msg, contains("Tapiwa's phone"));
      expect(msg.toLowerCase(), contains('timed out'));
      expect(msg, isNot(contains('DioException')));
    });

    test('connection error suggests checking the network', () {
      final msg = friendlyTransferError(
        DioException(
            requestOptions: req, type: DioExceptionType.connectionError),
      );
      expect(msg.toLowerCase(), contains('network'));
      expect(msg, contains('the other device'));
    });

    test('bad response maps status code to friendly text', () {
      final msg = friendlyTransferError(
        DioException(
          requestOptions: req,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: req, statusCode: 403),
        ),
        peerName: 'Laptop',
      );
      expect(msg, contains('Laptop'));
      expect(msg.toLowerCase(), contains('declined'));
    });

    test('raw SocketException never leaks', () {
      final msg = friendlyTransferError(
        const SocketException('Connection refused'),
        peerName: 'PC',
      );
      expect(msg, isNot(contains('SocketException')));
      expect(msg, contains('PC'));
    });

    test('TimeoutException is humanised', () {
      final msg = friendlyTransferError(TimeoutException('nope'));
      expect(msg, isNot(contains('TimeoutException')));
      expect(msg.toLowerCase(), contains('timed out'));
    });

    test('empty error string still yields a non-blank message', () {
      final msg = friendlyTransferError(_BlankError(), peerName: 'X');
      expect(msg.trim(), isNotEmpty);
    });
  });

  group('friendlyHttpStatus', () {
    test('409 explains the device is busy', () {
      expect(friendlyHttpStatus(409).toLowerCase(), contains('busy'));
    });
    test('unknown code still produces guidance', () {
      final msg = friendlyHttpStatus(418, peerName: 'Teapot');
      expect(msg, contains('Teapot'));
      expect(msg, contains('418'));
    });
  });

  group('storage errors', () {
    test('ENOSPC (posix 28) says out of space', () {
      final msg = friendlyTransferError(const FileSystemException(
          'write failed', '/sdcard/x', OSError('No space left on device', 28)));
      expect(msg, contains('Not enough storage space'));
    });

    test('Windows disk full (112) says out of space', () {
      final msg = friendlyTransferError(const FileSystemException(
          'write failed', r'C:\x', OSError('There is not enough space', 112)));
      expect(msg, contains('Not enough storage space'));
    });

    test('permission denied points to Settings', () {
      final msg = friendlyTransferError(const FileSystemException(
          'cannot open', '/root/x', OSError('Permission denied', 13)));
      expect(msg, contains('save folder in Settings'));
    });

    test('other storage errors keep the OS detail', () {
      final msg = friendlyTransferError(const FileSystemException(
          'boom', '/x', OSError('Input/output error', 5)));
      expect(msg, contains('storage error'));
      expect(msg, contains('Input/output error'));
    });
  });
}

class _BlankError {
  @override
  String toString() => '';
}
