import 'package:flutter/foundation.dart';

abstract final class AppLinks {
  static const support = String.fromEnvironment(
    'SUPPORT_URL',
    defaultValue: 'https://jobsnad.com/support/',
  );
  static const privacy = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://jobsnad.com/privacy/',
  );

  /// Public web app origin used in share sheets, e.g. https://jobsnad.com
  static const web = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://jobsnad.com',
  );
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
    const api = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://admin.jobsnad.com',
    );
    if (kReleaseMode && api.trim() != 'demo' && (!hasSupport || !hasPrivacy)) {
      throw ReleaseConfigError(
        'روابط الدعم أو الخصوصية في إعدادات البناء غير صالحة. '
        'استخدم إعدادات التطبيق الافتراضية أو روابط HTTPS صالحة.',
      );
    }
  }
}

/// A build-time setting is missing: retrying cannot fix it, a rebuild can.
class ReleaseConfigError extends Error {
  ReleaseConfigError(this.message);
  final String message;
  @override
  String toString() => message;
}
