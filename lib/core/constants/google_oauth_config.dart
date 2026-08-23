/// Google OAuth configuration for Drive backup.
///
/// Setup: https://console.cloud.google.com/ → APIs & Services → Credentials
/// 1. Enable Google Drive API
/// 2. OAuth consent screen (External) with drive.file + drive.readonly scopes
/// 3. Android client: package `com.example.flu_app` + your SHA-1
/// 4. Web client → paste Client ID below as [serverClientId]
class GoogleOAuthConfig {
  /// Web OAuth 2.0 Client ID from Google Cloud Console.
  /// Required for Drive API access on Android.
  static const String serverClientId =
      '797895855626-sc661vu1hpceh2b28jla3run5795dcnd.apps.googleusercontent.com';

  static const String _placeholderPrefix = 'YOUR_WEB_CLIENT_ID';

  static bool get isConfigured =>
      serverClientId.isNotEmpty &&
      !serverClientId.startsWith(_placeholderPrefix);

  static const String setupHint =
      'Google Drive is not configured. Add your Web OAuth Client ID in '
      'lib/core/constants/google_oauth_config.dart';
}
