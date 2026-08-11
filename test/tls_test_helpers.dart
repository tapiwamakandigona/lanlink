// Shared TLS fixtures for tests that spin up real [Receiver] servers and
// dial them over loopback HTTPS (protocol 2.1: HTTPS-only transport).

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:lanlink/core/security/device_certificate.dart';

DeviceCertificate? _certA;
DeviceCertificate? _certB;

/// Process-wide test certificate for the (first) receiver under test.
/// Generated once per test process — EC keygen is fast but not free.
DeviceCertificate testCertificate() => _certA ??= DeviceCertificate.generate();

/// A second, distinct identity for tests running two peers whose
/// fingerprints must differ.
DeviceCertificate testCertificateB() => _certB ??= DeviceCertificate.generate();

/// Drop-in [Receiver.certificateProvider] serving [testCertificate].
Future<DeviceCertificate> testCertificateProvider() async => testCertificate();

/// Drop-in [Receiver.certificateProvider] serving [testCertificateB].
Future<DeviceCertificate> testCertificateProviderB() async =>
    testCertificateB();

/// Raw [HttpClient] that accepts any self-signed certificate. For tests
/// that exercise the receiver's HTTP behavior, not the pinning layer.
HttpClient trustAllHttpClient() =>
    HttpClient()..badCertificateCallback = (cert, host, port) => true;

/// [Dio] client that accepts any self-signed certificate.
Dio trustAllDio([BaseOptions? options]) {
  final d = Dio(options ?? BaseOptions());
  d.httpClientAdapter =
      IOHttpClientAdapter(createHttpClient: trustAllHttpClient);
  return d;
}
