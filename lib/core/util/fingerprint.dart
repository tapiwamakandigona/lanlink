import '../security/device_certificate.dart';

/// Returns the stable device fingerprint for this install.
///
/// Since the HTTPS transport landed the fingerprint is no longer a random
/// self-reported value: it is the SHA-256 hash of this device's TLS
/// certificate DER (see [DeviceCertificate]), so peers can verify it
/// cryptographically during the handshake. First call generates and
/// persists the certificate; subsequent calls return the same value.
Future<String> loadOrCreateFingerprint() async =>
    (await DeviceCertificate.load()).fingerprint;
