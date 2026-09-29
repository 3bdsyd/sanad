import 'package:flutter/foundation.dart';

abstract final class AppLinks {
  static const support = String.fromEnvironment('SUPPORT_URL');
  static const privacy = String.fromEnvironment('PRIVACY_URL');

  /// Public web app origin used in share sheets, e.g. https://app.example.com
  static const web = String.fromEnvironment('WEB_BASE_URL');
  static bool get hasSupport => _https(support);
  static bool get hasPrivacy => _https(privacy);
  static bool get hasWeb => _https(web);
  static bool _https(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  /// Shareable HTTPS link for a published job when the web app is configured.
  static Uri? jobShareUri(String jobId) {
    if (!hasWeb || jobId.trim().isEmpty) return null;
    final base = Uri.parse(web);
    final segments = [
      ...base.pathSegments.where((part) => part.isNotEmpty),
      'jobs',
      jobId.trim(),
    ];
    return base.replace(pathSegments: segments, query: null, fragment: null);
  }

  static void validateRelease() {
    // Web previews and local hosting often omit store policy URLs; do not
    // hard-crash the canvas. Mobile store builds keep the strict check.
    if (kIsWeb) return;
    const api = String.fromEnvironment('API_BASE_URL');
    if (kReleaseMode && api.isNotEmpty && (!hasSupport || !hasPrivacy)) {
      throw StateError(
        'Live release requires HTTPS SUPPORT_URL and PRIVACY_URL.',
      );
    }
  }
}
