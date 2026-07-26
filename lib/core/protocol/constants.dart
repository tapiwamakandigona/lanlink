/// Protocol constants used by both the server and client sides of LanLink.
///
/// LanLink speaks the [LocalSend v2 protocol](https://github.com/localsend/protocol),
/// which means LanLink instances can interoperate with LocalSend out of the box.
class LanLinkProtocol {
  LanLinkProtocol._();

  /// Wire protocol version we implement.
  static const protocolVersion = '2.0';

  // NOTE: The hard-coded appVersion constant was removed because it was stale
  // (2.0.0 vs pubspec 3.5.0+13) and unused. The canonical version lives in
  // pubspec.yaml and can be read at runtime via package_info_plus.

  /// Default TCP port for the HTTP server. Matches LocalSend's default.
  static const defaultPort = 53317;

  /// Multicast group used for UDP discovery announcements.
  static const multicastGroup = '224.0.0.167';

  /// UDP port for discovery announcements (same as TCP).
  static const discoveryPort = 53317;

  /// Interval between proactive discovery announcements.
  static const announceInterval = Duration(seconds: 5);

  /// API base path for all v2 endpoints.
  static const apiPrefix = '/api/localsend/v2';

  // --- API routes ---
  static const routeInfo = '$apiPrefix/info';
  static const routeRegister = '$apiPrefix/register';
  static const routePrepareUpload = '$apiPrefix/prepare-upload';
  static const routeUpload = '$apiPrefix/upload';
  static const routeCancel = '$apiPrefix/cancel';

  // --- LanLink extension routes (additive; plain LocalSend never calls
  // these, and all LocalSend v2 routes above keep their exact semantics) ---

  /// Consumes a one-time connect token minted for a QR code and returns the
  /// device info. Replaying a consumed (or unknown) token yields 401.
  static const routeConnect = '/api/lanlink/v1/connect';

  /// Ends the symmetric session between two paired devices (F3
  /// Disconnect/Unpair). Body carries the caller's device info; the callee
  /// only honours it when the fingerprint matches a currently linked peer
  /// (403 otherwise), then clears its side of the session.
  static const routeDisconnect = '/api/lanlink/v1/disconnect';

  // --- Device type strings (LocalSend convention) ---
  static const deviceTypeMobile = 'mobile';
  static const deviceTypeDesktop = 'desktop';
  static const deviceTypeHeadless = 'headless';
}
