import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snad/core/firebase_bootstrap.dart';
import 'package:snad/core/push_notifications.dart';

class _Messaging implements FirebaseMessaging {
  final tokens = StreamController<String>.broadcast();
  AuthorizationStatus status = AuthorizationStatus.denied;
  bool grant = true;
  int requests = 0;
  String? apns = 'apns';
  String token = 'first';
  @override
  Stream<String> get onTokenRefresh => tokens.stream;
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<String?> getAPNSToken() async => apns;
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async => token;
  @override
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async {}
  @override
  Future<NotificationSettings> getNotificationSettings() async =>
      NotificationSettings(
        authorizationStatus: status,
        alert: AppleNotificationSetting.enabled,
        announcement: AppleNotificationSetting.disabled,
        badge: AppleNotificationSetting.enabled,
        carPlay: AppleNotificationSetting.disabled,
        lockScreen: AppleNotificationSetting.enabled,
        notificationCenter: AppleNotificationSetting.enabled,
        showPreviews: AppleShowPreviewSetting.always,
        timeSensitive: AppleNotificationSetting.disabled,
        criticalAlert: AppleNotificationSetting.disabled,
        sound: AppleNotificationSetting.enabled,
        providesAppNotificationSettings: AppleNotificationSetting.disabled,
      );
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    requests++;
    status = grant
        ? AuthorizationStatus.authorized
        : AuthorizationStatus.denied;
    return getNotificationSettings();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    FirebaseBootstrap.connection = const FirebaseConnection(
      FirebaseConnectionState.ready,
    );
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'requests system permission once, registers and updates token',
    () async {
      final messaging = _Messaging();
      final registered = <String>[];
      final push = PushNotifications(
        messaging: messaging,
        registerToken: (token) async {
          registered.add(token);
        },
        onMessage: () async {},
      );
      await push.start();
      expect(messaging.requests, 1);
      expect(push.state, PushState.ready);
      await push.start();
      expect(messaging.requests, 1);
      expect(registered, ['first']);
      messaging.tokens.add('refreshed');
      await Future<void>.delayed(Duration.zero);
      expect(registered, ['first', 'refreshed']);
      push.dispose();
      await messaging.tokens.close();
    },
  );
  test('denial does not register or repeat the prompt on resume', () async {
    final messaging = _Messaging()..grant = false;
    var registrations = 0;
    final push = PushNotifications(
      messaging: messaging,
      registerToken: (_) async {
        registrations++;
      },
      onMessage: () async {},
    );
    await push.start();
    await push.start();
    expect(push.state, PushState.denied);
    expect(messaging.requests, 1);
    expect(registrations, 0);
    messaging.grant = true;
    await push.start(requestAgain: true);
    expect(messaging.requests, 2);
    expect(push.state, PushState.ready);
    push.dispose();
    await messaging.tokens.close();
  });
  test('iOS waits for APNs and then retries token registration', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final messaging = _Messaging()..apns = null;
    var registrations = 0;
    final push = PushNotifications(
      messaging: messaging,
      registerToken: (_) async {
        registrations++;
      },
      onMessage: () async {},
    );
    await push.start();
    expect(registrations, 0);
    expect(push.state, PushState.failed);
    messaging.apns = 'ready';
    await push.start();
    expect(registrations, 1);
    expect(push.state, PushState.ready);
    expect(messaging.requests, 1);
    push.dispose();
    await messaging.tokens.close();
  });
}
