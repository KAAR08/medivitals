/// Build-time configuration, supplied with `--dart-define`.
///
/// Examples:
///   flutter run                                        # mock backend (default)
///   adb reverse tcp:8443 tcp:8443
///   flutter run --dart-define=USE_MOCK_BACKEND=false \
///               --dart-define-from-file=secrets/dev_ca.json
///
/// API_BASE_URL is the gateway (docker-compose); it routes /auth and /patients
/// to the Identity Service and everything else to the Telemetry Engine.
abstract final class AppConfig {
  /// When true, repositories are served by the in-memory [MockApiService]
  /// instead of the real HTTP / WebSocket backend.
  static const bool useMockBackend = bool.fromEnvironment(
    'USE_MOCK_BACKEND',
    defaultValue: true,
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://localhost:8443',
  );

  static const String _wsBaseUrlOverride =
      String.fromEnvironment('WS_BASE_URL');

  /// WebSocket base: WS_BASE_URL if given, else API_BASE_URL with
  /// https → wss (http → ws), so one setting configures both.
  static String get wsBaseUrl => _wsBaseUrlOverride.isNotEmpty
      ? _wsBaseUrlOverride
      : apiBaseUrl.replaceFirst(RegExp('^http'), 'ws');

  /// Chat exists only in the mock backend.
  static const bool chatEnabled = useMockBackend;
}
