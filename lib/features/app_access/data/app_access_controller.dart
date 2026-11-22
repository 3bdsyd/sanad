import 'package:flutter/foundation.dart';

import '../domain/app_access.dart';

class AppAccessController extends ChangeNotifier {
  AppAccessController(this._check);
  final Future<AppAccess> Function() _check;
  AppAccess? status;
  bool checking = false;
  String? error;
  String? _dismissedVersion;
  bool _disposed = false;

  bool get allowed => status?.kind == AppAccessKind.allowed;

  Future<void> refresh() async {
    if (checking || _disposed) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      var next = await _check();
      if (_disposed) return;
      if (next.kind == AppAccessKind.update &&
          !next.requiredUpdate &&
          next.latestVersion == _dismissedVersion) {
        next = const AppAccess();
      }
      status = next;
    } catch (_) {
      if (_disposed) return;
      // A failed recheck must never clear a known maintenance/required update.
      error = 'تعذّر التحقق من حالة الخدمة. تحقق من الاتصال وأعد المحاولة.';
    } finally {
      checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  void skipUpdate() {
    final current = status;
    if (checking ||
        current?.kind != AppAccessKind.update ||
        current!.requiredUpdate) {
      return;
    }
    _dismissedVersion = current.latestVersion;
    status = const AppAccess();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
