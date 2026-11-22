import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Keeps browser back/forward aligned with nested [Navigator] pages on web.
class WebNavHistory {
  WebNavHistory._();
  static final WebNavHistory instance = WebNavHistory._();

  GlobalKey<NavigatorState>? _navigatorKey;
  web.EventListener? _listener;
  final _pages = <int, Future<void> Function()>{};
  final _paths = <int, String>{};
  final _session = DateTime.now().microsecondsSinceEpoch.toString();
  var _depth = 0;
  var _browserDepth = 0;
  var _browserPop = false;
  int? _appPopTarget;
  int? _restoringDepth;
  Completer<void>? _traversal;
  Timer? _traverseTimer;
  Future<void> _events = Future<void>.value();

  /// New routes wait for an in-app Back to reach its browser history entry.
  Future<void>? get pendingTraversal => _traversal?.future;
  int get pageDepth => _depth;

  /// Our nested navigator owns history. The engine's default handler would
  /// treat these entries as foreign and issue a second Back traversal.
  void initialize() {
    ui_web.urlStrategy = null;
  }

  void bind(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    if (_listener != null) return;
    // JobLinkHost captures the incoming URI before the navigator binds.
    // Give a directly opened job a real home entry to return to.
    _paths[0] =
        RegExp(
          r'^/jobs/[A-Za-z0-9_-]{1,128}/?$',
        ).hasMatch(web.window.location.pathname)
        ? '/'
        : web.window.location.href;
    _replaceState();
    _listener = ((web.Event event) {
      final state = (event as web.PopStateEvent).state.dartify();
      final target = state is Map && state['sanadSession'] == _session
          ? (state['sanadDepth'] as num?)?.toInt() ?? 0
          : 0;
      _browserDepth = target;
      if (_appPopTarget == target) {
        _appPopTarget = null;
        _finishTraversal();
        return;
      }
      _events = _events.then((_) => _navigateTo(target));
    }).toJS;
    web.window.addEventListener('popstate', _listener!);
  }

  Future<void> _navigateTo(int target) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    if (target < _depth) {
      while (target < _depth && nav.mounted && nav.canPop()) {
        final before = _depth;
        _browserPop = true;
        try {
          // PopScope may keep a draft open and show its inline leave choice.
          await nav.maybePop();
          // The route Future resumes openPage's history callback asynchronously.
          await Future<void>.delayed(Duration.zero);
        } finally {
          _browserPop = false;
        }
        if (_depth == before) break;
      }
      if (_depth != target) _scheduleTraversal();
    } else if (target > _depth) {
      for (var next = _depth + 1; next <= target; next++) {
        final reopen = _pages[next];
        if (reopen == null) break;
        _restoringDepth = next;
        unawaited(reopen());
        if (_restoringDepth != null) {
          // Its originating widget no longer exists.
          _restoringDepth = null;
          break;
        }
      }
      if (_depth != target) {
        _browserDepth = _depth;
        _replaceState();
      }
    }
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      web.window.removeEventListener('popstate', listener);
      _listener = null;
    }
    _navigatorKey = null;
    _pages.clear();
    _paths.clear();
    _traverseTimer?.cancel();
    _finishTraversal();
    _depth = 0;
    _browserDepth = 0;
    _browserPop = false;
    _appPopTarget = null;
    _restoringDepth = null;
  }

  void didPushPage({Future<void> Function()? reopen, String? path}) {
    final restored = _restoringDepth;
    _restoringDepth = null;
    if (restored != null) {
      _depth = restored;
      if (reopen != null) _pages[_depth] = reopen;
      return;
    }
    _depth++;
    _browserDepth = _depth;
    _pages.removeWhere((depth, _) => depth >= _depth);
    _paths.removeWhere((depth, _) => depth >= _depth);
    if (reopen != null) _pages[_depth] = reopen;
    _paths[_depth] = path ?? web.window.location.href;
    web.window.history.pushState(_state, '', _paths[_depth]);
  }

  /// Call when a pushed route is closed by the in-app back control.
  void didPopPageByApp() {
    if (_depth <= 0) return;
    _depth--;
    if (!_browserPop) _scheduleTraversal();
  }

  void _scheduleTraversal() {
    _traversal ??= Completer<void>();
    // Batch popUntil into one traversal, then wait for its real popstate.
    _traverseTimer?.cancel();
    _traverseTimer = Timer(Duration.zero, () {
      final delta = _depth - _browserDepth;
      if (delta == 0) {
        _finishTraversal();
        return;
      }
      _appPopTarget = _depth;
      web.window.history.go(delta);
    });
  }

  void _finishTraversal() {
    final traversal = _traversal;
    _traversal = null;
    if (traversal != null && !traversal.isCompleted) traversal.complete();
  }

  JSAny? get _state => {'sanadSession': _session, 'sanadDepth': _depth}.jsify();

  void _replaceState() => web.window.history.replaceState(
    _state,
    '',
    _paths[_depth] ?? web.window.location.href,
  );
}
