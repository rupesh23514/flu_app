/// Admin telemetry API configuration.
///
/// Values are supplied at **compile time** via `--dart-define`:
///
///   flutter build apk --release \
///     --dart-define=ADMIN_API_URL=https://your-app.vercel.app \
///     --dart-define=TELEMETRY_API_KEY=your-secret-key
///
/// Leave either value empty (the default) to disable telemetry entirely.
/// Telemetry failures are always silent and never block the user.
class AdminApiConfig {
  AdminApiConfig._();

  /// Admin API base URL (no trailing slash).
  /// Set via --dart-define=ADMIN_API_URL=https://...
  static const String baseUrl = String.fromEnvironment(
    'ADMIN_API_URL',
    defaultValue: '',
  );

  /// Shared secret sent in X-Telemetry-Key header.
  /// Must match TELEMETRY_API_KEY on the server.
  static const String telemetryApiKey = String.fromEnvironment(
    'TELEMETRY_API_KEY',
    defaultValue: '',
  );

  /// Returns true only when both URL and key are provided at build time.
  static bool get isConfigured =>
      baseUrl.isNotEmpty && telemetryApiKey.isNotEmpty;

  static String get telemetryHeartbeatUrl => '$baseUrl/api/v1/telemetry/heartbeat';
  static String get telemetryEventsUrl => '$baseUrl/api/v1/telemetry/events';
  static String get telemetryStatusUrl => '$baseUrl/api/v1/telemetry/status';
}
