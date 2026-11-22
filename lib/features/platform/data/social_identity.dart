import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/platform_models.dart';

/// Firebase only verifies identity. Jobs, accounts and chat remain on our API.
abstract final class SocialIdentity {
  static Future<void>? _google;

  static Future<String> token(String provider) async {
    if (kIsWeb && Firebase.apps.isEmpty) {
      const appId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
      const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
      const authDomain = String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN');
      if (appId.isNotEmpty && apiKey.isNotEmpty && authDomain.isNotEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            authDomain: authDomain,
            messagingSenderId: '377548025897',
            projectId: 'snd-project-8794b',
          ),
        );
      }
    }
    if (Firebase.apps.isEmpty) {
      throw const PlatformFailure(
        'الدخول السريع غير مهيّأ في هذه النسخة. يمكنك المتابعة بالبريد الإلكتروني.',
      );
    }
    UserCredential result;
    if (provider == 'apple') {
      final apple = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      result = kIsWeb
          ? await FirebaseAuth.instance.signInWithPopup(apple)
          : await FirebaseAuth.instance.signInWithProvider(apple);
    } else if (kIsWeb) {
      result = await FirebaseAuth.instance.signInWithPopup(
        GoogleAuthProvider(),
      );
    } else {
      const client = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
      const serverClient = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
      if (defaultTargetPlatform == TargetPlatform.iOS && client.isEmpty) {
        throw const PlatformFailure(
          'الدخول باستخدام Google غير مهيّأ في نسخة آيفون هذه. يمكنك المتابعة بالبريد الإلكتروني.',
        );
      }
      _google ??= GoogleSignIn.instance.initialize(
        clientId: client.isEmpty ? null : client,
        serverClientId: serverClient.isEmpty ? null : serverClient,
      );
      await _google;
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      result = await FirebaseAuth.instance.signInWithCredential(credential);
    }
    final value = await result.user?.getIdToken(true);
    if (value == null || value.isEmpty) {
      throw const PlatformFailure('تعذّر التحقق من الحساب. أعد المحاولة.');
    }
    return value;
  }

  static Future<void> clear() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      /* API session is already cleared. */
    }
  }
}
