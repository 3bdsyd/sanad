/// Session-wide limits survive list-row eviction and theme/size changes.
class AdLoadPolicy {
  AdLoadPolicy({
    DateTime Function()? now,
    this.maxAttempts = 4,
    this.maxNativeLoads = 2,
    this.retryCycle = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final int maxAttempts, maxNativeLoads;
  final Duration retryCycle;
  final _states = <String, _LoadState>{};
  int _nativeLoads = 0;

  AdLoadAttempt? begin(String placement, {required bool native}) {
    if (waitFor(placement, native: native) != Duration.zero) return null;
    final state = _states.putIfAbsent(placement, _LoadState.new);
    final attempt = AdLoadAttempt._(placement, native);
    state.pending = attempt;
    state.attempts++;
    if (native) _nativeLoads++;
    return attempt;
  }

  /// Permanent configuration errors stop; transient failures can recover after
  /// a bounded batch and a longer cooldown, while an owner is still active.
  Duration? waitFor(String placement, {required bool native}) {
    final state = _states[placement];
    if (state != null &&
        state.attempts >= maxAttempts &&
        state.pending == null) {
      if (state.permanent) return null;
      if (state.next != null && state.next!.isAfter(_now())) {
        return state.next!.difference(_now());
      }
      state.attempts = 0;
      state.next = null;
    }
    if (state?.pending != null || (native && _nativeLoads >= maxNativeLoads)) {
      return const Duration(seconds: 2);
    }
    final next = state?.next;
    if (next != null && next.isAfter(_now())) return next.difference(_now());
    return Duration.zero;
  }

  _LoadState? _finish(AdLoadAttempt attempt) {
    final state = _states[attempt.placement];
    if (state == null || !identical(state.pending, attempt)) return null;
    state.pending = null;
    if (attempt.native) _nativeLoads--;
    return state;
  }

  void succeeded(AdLoadAttempt attempt) {
    final state = _finish(attempt);
    if (state == null) return;
    state.attempts = 0;
    state.permanent = false;
    state.next = null;
  }

  void failed(
    AdLoadAttempt attempt, {
    bool noFill = false,
    bool permanent = false,
  }) {
    final state = _finish(attempt);
    if (state == null) return;
    state.permanent = permanent;
    if (permanent) state.attempts = maxAttempts;
    final seconds = noFill
        ? 120
        : (30 * (1 << (state.attempts - 1))).clamp(30, 120);
    state.next = _now().add(
      state.attempts >= maxAttempts && !permanent
          ? retryCycle
          : Duration(seconds: seconds),
    );
  }

  void failedSdk(AdLoadAttempt attempt, {required bool ios, int? code}) =>
      failed(
        attempt,
        noFill: ios ? code == 1 : code == 3,
        // Mediation data/adapter errors can recover after remote configuration
        // changes; they must not silence this placement for the whole session.
        permanent:
            code != null &&
            (ios ? const [0, 4, 10, 12, 19, 20, 21] : const [1, 8]).contains(
              code,
            ),
      );

  void abandoned(AdLoadAttempt attempt) {
    final state = _finish(attempt);
    if (state != null) state.next = _now().add(const Duration(seconds: 15));
  }
}

class AdLoadAttempt {
  AdLoadAttempt._(this.placement, this.native);
  final String placement;
  final bool native;
}

class _LoadState {
  int attempts = 0;
  bool permanent = false;
  DateTime? next;
  AdLoadAttempt? pending;
}

final adLoadPolicy = AdLoadPolicy();
