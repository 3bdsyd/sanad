import 'dart:async';

import 'package:flutter/material.dart';

import 'job_deep_links.dart';
import 'motion.dart';
import 'web_nav_history.dart';
import '../features/jobs/data/jobs_store.dart';
import '../features/jobs/presentation/job_details.dart';
import '../features/jobs/presentation/notifications.dart';
import '../features/platform/presentation/notification_destination.dart';

/// Listens for shared job URLs and opens [JobDetails] when the store is ready.
class JobLinkHost extends StatefulWidget {
  const JobLinkHost({
    super.key,
    required this.store,
    this.pushEnabled = false,
    required this.navigatorKey,
    required this.welcomeVisible,
    required this.onDismissWelcome,
    required this.child,
  });

  final JobsStore store;
  final bool pushEnabled;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool Function() welcomeVisible;
  final VoidCallback onDismissWelcome;
  final Widget child;

  @override
  State<JobLinkHost> createState() => _JobLinkHostState();
}

class _JobLinkHostState extends State<JobLinkHost> with WidgetsBindingObserver {
  JobDeepLinks? _links;
  String? _pendingId;
  bool _opening = false;
  String? _visibleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.push.taps.addListener(_pushTapped);
    if (widget.pushEnabled && !widget.store.isDemo) {
      unawaited(widget.store.push.start());
    }
    _links = JobDeepLinks(onJobId: _onJobId);
    unawaited(_links!.start());
  }

  @override
  void didUpdateWidget(covariant JobLinkHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.push.taps.removeListener(_pushTapped);
      widget.store.push.taps.addListener(_pushTapped);
    }
    if (widget.pushEnabled &&
        (!oldWidget.pushEnabled || oldWidget.store != widget.store)) {
      if (!widget.store.isDemo) unawaited(widget.store.push.start());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pushTapped();
      });
    }
    if (_pendingId != null && !widget.welcomeVisible()) {
      final id = _pendingId!;
      _pendingId = null;
      unawaited(_open(id));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.push.taps.removeListener(_pushTapped);
    _links?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.pushEnabled &&
        !widget.store.isDemo) {
      unawaited(widget.store.push.start());
      unawaited(widget.store.refreshNotices());
    }
  }

  void _pushTapped() {
    if (!mounted || !widget.pushEnabled) return;
    final data = widget.store.push.taps.value;
    final nav = widget.navigatorKey.currentState;
    if (data == null || nav == null) return;
    widget.store.push.taps.value = null;
    unawaited(widget.store.refreshNotices());
    if (data['destination'] != null) {
      unawaited(
        openNotificationDestination(
          nav.context,
          widget.store,
          data,
        ).catchError((Object _) {}),
      );
      return;
    }
    final id = data['job_id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      unawaited(_onJobId(id));
    } else {
      unawaited(
        openPage<void>(
          nav.context,
          NotificationsPage(
            store: widget.store,
            onJob: (job) => openPage<void>(
              nav.context,
              JobDetails(job: job, store: widget.store),
              webPath: '/jobs/${Uri.encodeComponent(job.id)}',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _onJobId(String id) async {
    if (widget.welcomeVisible()) {
      _pendingId = id;
      widget.onDismissWelcome();
      return;
    }
    await _open(id);
  }

  Future<void> _open(String id) async {
    if (!mounted || _visibleId == id) return;
    if (_opening) {
      _pendingId = id;
      return;
    }
    _opening = true;
    try {
      // Wait until the nested navigator exists after splash/welcome.
      for (var i = 0; i < 40 && widget.navigatorKey.currentState == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
      final nav = widget.navigatorKey.currentState;
      if (nav == null) {
        _pendingId = id;
        return;
      }
      final job = await widget.store.fetchJob(id);
      if (!mounted || !nav.mounted) return;
      if (job == null || !job.isAvailable) {
        widget.store.showError(
          'تعذّر فتح الفرصة. قد تكون انتهت؛ تحقق من الاتصال وحاول مجدداً.',
        );
        return;
      }
      if (_pendingId != null) return;
      // Preserve any draft beneath a shared link; opening it must not discard
      // a protected form through a programmatic popUntil.
      await Future<void>.delayed(Duration.zero);
      final traversal = WebNavHistory.instance.pendingTraversal;
      if (traversal != null) await traversal;
      if (!mounted || !nav.mounted) return;
      _visibleId = id;
      unawaited(
        openPage<void>(
          nav.context,
          JobDetails(job: job, store: widget.store),
          webPath: '/jobs/${Uri.encodeComponent(job.id)}',
        ).whenComplete(() {
          if (_visibleId == id) _visibleId = null;
        }),
      );
    } finally {
      _opening = false;
      final pending = _pendingId;
      _pendingId = null;
      if (mounted && pending != null) unawaited(_open(pending));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
