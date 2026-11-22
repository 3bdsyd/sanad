import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/app_access.dart';

class AppAccessService {
  AppAccessService({required this.base, required http.Client client})
    : _client = client;

  final String base;
  final http.Client _client;

  Future<AppAccess> check({String? platform, String? version}) async {
    if (base == 'demo') return const AppAccess();
    final maintenance = await _read('/api/app/maintenance');
    if (AppAccess.isMaintenance(maintenance)) {
      return const AppAccess(kind: AppAccessKind.maintenance);
    }
    // The live service only accepts Android and iOS version checks.
    if (platform == null) return const AppAccess();
    if (version == null || version.isEmpty) {
      throw const FormatException('version');
    }
    return AppAccess.version(
      await _read('/api/app/version-check', {
        'version': version,
        'platform': platform,
      }),
      platform,
    );
  }

  Future<Map<String, dynamic>> _read(
    String path, [
    Map<String, String>? query,
  ]) async {
    final origin = Uri.tryParse(base.trim());
    final localDebug =
        kDebugMode &&
        origin != null &&
        ['localhost', '127.0.0.1', '::1', '[::1]'].contains(origin.host);
    if (origin == null ||
        origin.host.isEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        origin.userInfo.isNotEmpty ||
        (origin.scheme != 'https' &&
            !(localDebug && origin.scheme == 'http'))) {
      throw const FormatException('API_BASE_URL');
    }
    final uri = origin.replace(
      path: '${origin.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query,
    );
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    final response = await (() async {
      return http.Response.fromStream(await _client.send(request));
    })().timeout(const Duration(seconds: 8));
    // The local reference backend may not implement these optional routes.
    if (response.statusCode == 404) return const {};
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map) throw const FormatException('app status');
    final payload = Map<String, dynamic>.from(value);
    if (response.statusCode == 503 &&
        path.endsWith('/maintenance') &&
        AppAccess.isMaintenance(payload)) {
      return payload;
    }
    if (response.statusCode != 200 || payload['success'] == false) {
      throw const FormatException('app status');
    }
    return payload;
  }
}
