import 'package:flutter/widgets.dart';

/// Web browser History sync for [Navigator] pushes. Stub off the web.
class WebNavHistory {
  WebNavHistory._();
  static final WebNavHistory instance = WebNavHistory._();

  Future<void>? get pendingTraversal => null;
  int get pageDepth => 0;

  void initialize() {}

  void bind(GlobalKey<NavigatorState> navigatorKey) {}

  void dispose() {}

  void didPushPage({Future<void> Function()? reopen, String? path}) {}

  void didPopPageByApp() {}
}
