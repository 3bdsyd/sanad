import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createNetworkClient() {
  if (Platform.isIOS) {
    final configuration = URLSessionConfiguration.ephemeralSessionConfiguration()
      // Freshness belongs to JobsStore; availability checks must reach the API.
      ..cache = null
      ..httpShouldSetCookies = false;
    return CupertinoClient.fromSessionConfiguration(configuration);
  }
  if (Platform.isAndroid) {
    try {
      return CronetClient.fromCronetEngine(
        CronetEngine.build(
          cacheMode: CacheMode.disabled,
          enableBrotli: true,
          enableHttp2: true,
          enableQuic: true,
        ),
        closeEngine: true,
      );
    } catch (_) {
      // Fall back only before sending: replaying a failed write is unsafe.
      debugPrint('Native HTTP unavailable; using Dart HTTP.');
    }
  }
  return IOClient(HttpClient()..idleTimeout = const Duration(seconds: 3));
}
