import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:shared_preferences/shared_preferences.dart';

const _certKey = 'lanlink_tls_cert_pem_v1';
const _keyKey = 'lanlink_tls_key_pem_v1';

/// The self-signed TLS identity of this install.
///
/// Every device generates a certificate + private key on first run and keeps
/// it for the lifetime of the install (same model as LocalSend). The device
/// fingerprint IS the SHA-256 hash of the certificate DER — it is proven
/// cryptographically during the TLS handshake instead of being self-reported
/// JSON, so a hostile LAN peer can no longer impersonate a pinned device.
class DeviceCertificate {
  DeviceCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
  }) : fingerprint = fingerprintOfPem(certificatePem);

  /// PEM-encoded X.509 certificate presented to peers.
  final String certificatePem;

  /// PEM-encoded private key (kept local, never sent on the wire).
  final String privateKeyPem;

  /// Lowercase hex SHA-256 of the certificate DER. This is the device
  /// fingerprint announced over multicast, `/info`, and QR payloads.
  final String fingerprint;

  /// Builds the server-side TLS context for `HttpServer.bindSecure`.
  SecurityContext securityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  static DeviceCertificate? _cached;

  /// Loads the persisted certificate, generating (and persisting) a fresh
  /// one on first run. Memoized per process.
  static Future<DeviceCertificate> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final certPem = prefs.getString(_certKey);
    final keyPem = prefs.getString(_keyKey);
    if (certPem != null &&
        certPem.isNotEmpty &&
        keyPem != null &&
        keyPem.isNotEmpty) {
      return _cached =
          DeviceCertificate(certificatePem: certPem, privateKeyPem: keyPem);
    }
    final fresh = generate();
    await prefs.setString(_certKey, fresh.certificatePem);
    await prefs.setString(_keyKey, fresh.privateKeyPem);
    return _cached = fresh;
  }

  /// Test hook: clears the process-level cache so a test can exercise the
  /// load/generate path with mocked preferences.
  static void debugResetCache() => _cached = null;

  /// Generates a fresh self-signed certificate (ECDSA P-256, valid ~10
  /// years). The subject is deliberately generic: identity comes from the
  /// key/fingerprint, not the DN.
  static DeviceCertificate generate() {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': 'LanLink'}, priv, pub);
    final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
    return DeviceCertificate(
      certificatePem: certPem,
      privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(priv),
    );
  }

  /// SHA-256 (lowercase hex) of the DER bytes of a PEM certificate.
  static String fingerprintOfPem(String pem) {
    final der = base64.decode(pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), ''));
    return fingerprintOfDer(der);
  }

  /// SHA-256 (lowercase hex) of raw certificate DER bytes.
  static String fingerprintOfDer(List<int> der) =>
      crypto.sha256.convert(der).toString();
}
