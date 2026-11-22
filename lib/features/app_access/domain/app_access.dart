enum AppAccessKind { allowed, maintenance, update }

class AppAccess {
  const AppAccess({
    this.kind = AppAccessKind.allowed,
    this.requiredUpdate = false,
    this.latestVersion = '',
    this.storeUri,
  });

  final AppAccessKind kind;
  final bool requiredUpdate;
  final String latestVersion;
  final Uri? storeUri;

  static bool enabled(Object? value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  static Map<String, dynamic> data(Map<String, dynamic> payload) =>
      payload['data'] is Map
      ? {...payload, ...Map<String, dynamic>.from(payload['data'] as Map)}
      : payload;

  static bool isMaintenance(Map<String, dynamic> payload) {
    final fields = data(payload);
    return enabled(fields['maintenance']) ||
        enabled(fields['is_maintenance']) ||
        enabled(fields['enabled']);
  }

  factory AppAccess.version(Map<String, dynamic> payload, String platform) {
    final fields = data(payload);
    final required = enabled(fields['force_update']);
    if (!required && !enabled(fields['update_available'])) {
      return const AppAccess();
    }
    final version = fields['latest_version'];
    return AppAccess(
      kind: AppAccessKind.update,
      requiredUpdate: required,
      latestVersion:
          version is String && RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(version)
          ? version
          : '',
      storeUri: validStoreUri(fields['store_url'], platform),
    );
  }

  /// Only an actual mobile store listing can be offered as an update action.
  static Uri? validStoreUri(Object? value, String platform) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    if (platform == 'android' &&
        uri.host == 'play.google.com' &&
        uri.path == '/store/apps/details' &&
        uri.queryParameters['id'] == 'com.jobsnad.snad') {
      return uri;
    }
    if (platform == 'ios' &&
        uri.host == 'apps.apple.com' &&
        RegExp(r'/id\d+$').hasMatch(uri.path)) {
      return uri;
    }
    return null;
  }
}
