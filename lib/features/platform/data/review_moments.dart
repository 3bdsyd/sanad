import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Request the OS surface after meaningful use. No pre-rating, incentives or
/// claim that a prompt was shown: both stores control their own quotas.
abstract final class ReviewMoments {
  static bool _requestedThisSession = false;
  static Future<void> recordUse() async {
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey('snad.review.first-use')) {
      await p.setString(
        'snad.review.first-use',
        DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  static Future<void> completedAction({required bool demo}) async {
    if (demo ||
        kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    final count = (p.getInt('snad.review.actions') ?? 0) + 1;
    await p.setInt('snad.review.actions', count);
    final first = DateTime.tryParse(p.getString('snad.review.first-use') ?? '');
    final last = DateTime.tryParse(p.getString('snad.review.request') ?? '');
    if (_requestedThisSession ||
        count < 3 ||
        first == null ||
        DateTime.now().difference(first).inDays < 7 ||
        (last != null && DateTime.now().difference(last).inDays < 120)) {
      return;
    }
    try {
      if (!await InAppReview.instance.isAvailable()) return;
      _requestedThisSession = true;
      await p.setString(
        'snad.review.request',
        DateTime.now().toUtc().toIso8601String(),
      );
      await InAppReview.instance.requestReview();
    } catch (_) {
      /* A missing store must never affect the completed action. */
    }
  }
}
