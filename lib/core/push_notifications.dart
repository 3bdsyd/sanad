import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';

enum PushState { idle, connecting, ready, denied, failed }

class PushNotifications extends ChangeNotifier {
  PushNotifications({
    required this.registerToken,
    required this.onMessage,
    this.shouldPresent,
    FirebaseMessaging? messaging,
  }) : _messaging = messaging;

  final FirebaseMessaging? _messaging;
  FirebaseMessaging get _firebase => _messaging ?? FirebaseMessaging.instance;

  final Future<void> Function(String) registerToken;
  final Future<void> Function() onMessage;
  final bool Function(Map<String, dynamic>)? shouldPresent;
  final _local = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final taps = ValueNotifier<Map<String, dynamic>?>(null);
  PushState state = PushState.idle;
  bool _initialized = false, _busy = false, _disposed = false;
  String? _registeredToken;
  Timer? _retry;
  int _retries = 0;
  Future<void> _registration = Future.value();

  static const _channel = AndroidNotificationChannel(
    'sanad_updates',
    'إشعارات سند',
    description: 'متابعة الفرص والإعلانات',
    importance: Importance.high,
  );

  void _setState(PushState value) {
    if (_disposed) return;
    state = value;
    notifyListeners();
  }

  /// Rechecking on resume never repeats a declined system permission prompt.
  Future<void> start({bool requestAgain = false}) async {
    if (_disposed || _busy || !FirebaseBootstrap.supportsCurrentPlatform) {
      return;
    }
    _busy = true;
    _retry?.cancel();
    _setState(PushState.connecting);
    try {
      if (!FirebaseBootstrap.connection.isReady) throw StateError('firebase');
      final messaging = _firebase;
      if (!_initialized) {
        await _local.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
          onDidReceiveNotificationResponse: (response) {
            if (_disposed) return;
            final payload = response.payload;
            taps.value = payload == null
                ? {}
                : jsonDecode(payload) as Map<String, dynamic>;
          },
        );
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_channel);
        // Local presentation below handles the foreground on both platforms.
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
        if (_disposed) return;
        _subscriptions.addAll([
          messaging.onTokenRefresh.listen(
            (token) => unawaited(_register(token)),
            onError: (Object _) => _failed(),
          ),
          FirebaseMessaging.onMessage.listen(
            (message) => unawaited(_receive(message)),
          ),
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
            if (!_disposed) taps.value = message.data;
          }),
        ]);
        _initialized = true;
        final initial = await messaging.getInitialMessage();
        final localLaunch = await _local.getNotificationAppLaunchDetails();
        if (_disposed) return;
        if (initial != null) {
          taps.value = initial.data;
        } else if (localLaunch?.didNotificationLaunchApp == true) {
          final payload = localLaunch?.notificationResponse?.payload;
          taps.value = payload == null
              ? {}
              : jsonDecode(payload) as Map<String, dynamic>;
        }
      }
      var settings = await messaging.getNotificationSettings();
      final preferences = await SharedPreferences.getInstance();
      const key = 'snad.push.permission-requested';
      if (requestAgain || !(preferences.getBool(key) ?? false)) {
        // Android 13 reports denied both before the first request and after denial.
        await preferences.setBool(key, true);
        settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      if (_disposed) return;
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _setState(PushState.denied);
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await messaging.getAPNSToken() == null) {
        throw StateError('apns-pending');
      }
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 20),
      );
      if (token == null || token.isEmpty) throw StateError('token-pending');
      await _register(token);
    } catch (_) {
      _failed();
    } finally {
      _busy = false;
    }
  }

  Future<void> _register(String token) {
    return _registration = _registration.then((_) async {
      if (_disposed) return;
      try {
        final settings = await _firebase.getNotificationSettings();
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          _setState(PushState.denied);
          return;
        }
        if (token != _registeredToken) {
          await registerToken(token);
          _registeredToken = token;
        }
        _retries = 0;
        _retry?.cancel();
        _setState(PushState.ready);
      } catch (_) {
        _failed();
      }
    });
  }

  void _failed() {
    _setState(PushState.failed);
    if (_disposed || _retries >= 3) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: 5 * ++_retries), () => unawaited(start()));
  }

  Future<void> _receive(RemoteMessage message) async {
    if (_disposed) return;
    try {
      // Present immediately even if the REST inbox is slow or unavailable.
      unawaited(onMessage().catchError((Object _) {}));
      if (shouldPresent?.call(message.data) == false) return;
      final notification = message.notification;
      final title = notification?.title ?? message.data['title']?.toString();
      final body = notification?.body ?? message.data['body']?.toString();
      if (title == null && body == null) return;
      await _local.show(
        id:
            (message.messageId ?? '${DateTime.now().microsecondsSinceEpoch}')
                .hashCode &
            0x7fffffff,
        title: title ?? 'سند',
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (_) {
      _setState(PushState.failed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    taps.dispose();
    super.dispose();
  }
}
