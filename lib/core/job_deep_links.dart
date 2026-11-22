import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'app_links.dart' as sanad;

/// Resolves shared job URLs: https://jobsnad.com/jobs/{id} (and www).
class JobDeepLinks {
  JobDeepLinks({required this.onJobId});

  final FutureOr<void> Function(String jobId) onJobId;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _handled;
  DateTime? _handledAt;
  bool _disposed = false;

  Future<void> start() async {
    if (!kIsWeb) {
      _sub = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(_consume(uri)),
        onError: (Object _) {},
      );
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) await _consume(initial);
      } catch (_) {}
    } else {
      await _consume(Uri.base);
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _consume(Uri uri) async {
    final id = jobIdFromUri(uri);
    if (_disposed || id == null) return;
    final now = DateTime.now();
    if (id == _handled &&
        _handledAt != null &&
        now.difference(_handledAt!) < const Duration(seconds: 1)) {
      return;
    }
    _handled = id;
    _handledAt = now;
    await onJobId(id);
  }

  /// Accepts /jobs/12, /jobs/12/, and sanad://jobs/12.
  static String? jobIdFromUri(Uri uri) {
    if (uri.userInfo.isNotEmpty) return null;
    final host = uri.host.toLowerCase();
    final custom = uri.scheme == 'sanad' && host == 'jobs';
    final allowedHost =
        host == 'jobsnad.com' ||
        host == 'www.jobsnad.com' ||
        (sanad.AppLinks.hasWeb &&
            host == Uri.tryParse(sanad.AppLinks.web)?.host);
    if (!custom && (uri.scheme != 'https' || !allowedHost)) {
      return null;
    }

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final String? id;
    if (custom && segments.length == 1) {
      id = segments.single;
    } else if (segments.length == 2 && segments[0] == 'jobs') {
      id = segments[1];
    } else {
      return null;
    }
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
  }
}
