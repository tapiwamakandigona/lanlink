import 'dart:io';

import 'device_certificate.dart';

/// Verifies peer TLS certificates against pinned fingerprints.
///
/// Peers present self-signed certificates, so trust is decided here rather
/// than by the system CA store:
///
/// * When the caller knows the peer's fingerprint (QR payload, pinned peer,
///   discovery announce), the presented certificate is accepted IFF
///   `sha256(cert DER) == expected`. A mismatch is a hard rejection — never
///   silently accepted.
/// * When no fingerprint is known yet (first contact / subnet probing), the
///   certificate is accepted and its hash RECORDED, trust-on-first-use —
///   the same model LocalSend uses. Callers must then treat the recorded
///   hash as the peer's authoritative fingerprint (and pin it on pairing).
class CertificatePinner {
  final Map<String, String> _expected = {};
  final Map<String, String> _observed = {};

  static String _key(String host, int port) => '$host:$port';

  /// Declares the fingerprint we expect `host:port` to present. Pass an
  /// empty/blank [fingerprint] for first-contact (TOFU) endpoints.
  void expect(String host, int port, String? fingerprint) {
    final fp = fingerprint?.trim().toLowerCase() ?? '';
    if (fp.isEmpty) {
      _expected.remove(_key(host, port));
    } else {
      _expected[_key(host, port)] = fp;
    }
  }

  /// `badCertificateCallback` body: accept IFF the presented certificate
  /// matches the pin, or no pin exists yet (TOFU — hash is recorded).
  bool check(X509Certificate cert, String host, int port) {
    final presented = DeviceCertificate.fingerprintOfDer(cert.der);
    final key = _key(host, port);
    final expected = _expected[key];
    if (expected != null && expected != presented) {
      return false; // Pinned peer, wrong certificate: reject outright.
    }
    _observed[key] = presented;
    return true;
  }

  /// The cert hash last presented (and accepted) by `host:port`, or null.
  /// This is the authoritative peer fingerprint after any TLS round-trip.
  String? observed(String host, int port) => _observed[_key(host, port)];
}
