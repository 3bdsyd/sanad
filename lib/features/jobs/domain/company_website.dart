/// Empty is a valid omitted website. Null means an unsafe or malformed URL.
/// This matches the API validator; the server never fetches these addresses.
String? normalizeCompanyWebsite(String raw) {
  if (RegExp(r'[\x00-\x1F\x7F\u202A-\u202E\u2066-\u2069\\]').hasMatch(raw)) {
    return null;
  }
  var value = raw.trim();
  if (value.isEmpty) return '';
  if (RegExp(
    r'\s|%(?:0[0-9a-f]|1[0-9a-f]|7f)',
    caseSensitive: false,
  ).hasMatch(value)) {
    return null;
  }
  if (!RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(value)) {
    value = 'https://$value';
  }
  // Uri canonicalization removes an empty user-info segment (`https://@…`).
  // Reject it before parsing so client and API accept the same input.
  if (RegExp(r'^https?://[^/?#]*@', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
      !uri.hasAuthority ||
      uri.authority.contains('@') ||
      !uri.host.contains('.') ||
      uri.host.length > 253 ||
      uri.host
          .split('.')
          .any(
            (label) => !RegExp(
              r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
              caseSensitive: false,
            ).hasMatch(label),
          )) {
    return null;
  }
  try {
    if (uri.port < 1 || uri.port > 65535) return null;
  } on FormatException {
    return null;
  }
  final normalized = uri.replace(scheme: uri.scheme.toLowerCase()).toString();
  return normalized.length <= 2048 ? normalized : null;
}
