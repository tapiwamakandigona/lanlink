import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Translates the low-level exceptions and HTTP status codes that surface
/// during a transfer into short, plain-English sentences a non-technical
/// user can act on.
///
/// The goal is that nobody ever sees a raw `SocketException` or
/// `DioException [connection timeout]` string. [peerName] is woven into the
/// message when we have it (e.g. "Couldn't reach Tapiwa's phone …").
String friendlyTransferError(Object error, {String? peerName}) {
  final who = (peerName == null || peerName.trim().isEmpty)
      ? 'the other device'
      : peerName.trim();

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      // transformTimeout (dio >= 5.10) fires when decoding a response body
      // exceeds its budget — to the user that is the same "it timed out".
      case DioExceptionType.transformTimeout:
        return 'Timed out reaching $who. Make sure both devices are on '
            'the same Wi-Fi or hotspot and try again.';
      case DioExceptionType.connectionError:
        return "Couldn't reach $who. Check that LanLink is open on the "
            'other device and both are on the same network.';
      case DioExceptionType.cancel:
        return 'Transfer cancelled.';
      case DioExceptionType.badCertificate:
        return "Couldn't verify a secure connection to $who.";
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return _httpMessage(code, who);
      case DioExceptionType.unknown:
        return friendlyTransferError(error.error ?? error, peerName: peerName);
    }
  }

  if (error is SocketException) {
    return "Couldn't reach $who. Check that both devices are on the same "
        'network and LanLink is open on the other one.';
  }
  if (error is HttpException) {
    return 'The network connection to $who dropped mid-transfer. Try again.';
  }
  if (error is TimeoutException) {
    return 'Timed out talking to $who. Move the devices closer and try again.';
  }
  if (error is FileSystemException) {
    final detail = error.osError?.message ?? error.message;
    return 'Couldn\'t read a file from storage'
        '${detail.isEmpty ? '' : ' ($detail)'}.';
  }

  // Fall back to the raw message but keep it short and never blank.
  final raw = error.toString().trim();
  if (raw.isEmpty) return 'Something went wrong reaching $who. Try again.';
  return raw;
}

/// Maps an HTTP status code from a failed transfer step to plain English.
String friendlyHttpStatus(int? code, {String? peerName}) => _httpMessage(
    code,
    (peerName == null || peerName.trim().isEmpty)
        ? 'the other device'
        : peerName.trim());

String _httpMessage(int? code, String who) {
  switch (code) {
    case 403:
      return '$who declined the files.';
    case 404:
      return "$who didn't recognise the request. Make sure it's running a "
          'recent version of LanLink.';
    case 409:
      return '$who is busy with another transfer. Try again in a moment.';
    case 500:
    case 502:
    case 503:
      return '$who hit an error while receiving. Try again.';
    default:
      if (code == null) {
        return "Couldn't reach $who. Try again.";
      }
      return '$who responded with an unexpected error (code $code). '
          'Try again.';
  }
}
