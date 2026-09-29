# Firebase لتطبيق سند

أضيفت حزمة `firebase_core` الرسمية وتهيئة آمنة في [firebase_bootstrap.dart](../lib/core/firebase_bootstrap.dart). سُجّل تطبيقا iOS وAndroid بالمعرّف الموجود `app.fursa.fursa` داخل المشروع الذي اختاره صاحب التطبيق: `snd-project-8794b`، رقم المشروع `377548025897` واسم العرض `snd project`. الإعدادات الفعلية مولّدة باستخدام FlutterFire، وليست قيماً تجريبية.

| المنصة | Firebase App ID |
| --- | --- |
| iOS | `1:377548025897:ios:070cb8c44eb4f8526bac38` |
| Android | `1:377548025897:android:a05cdfd42131016f6bac38` |

بيانات الفرص تبقى على [خادم REST الحالي](backend.md). لم تُضف Firestore أو حسابات مستخدمين أو Analytics أو FCM؛ مركز الإشعارات الحالي محلي، وليس push.

## ربط المشروع الحقيقي

المشروع مضبوط حالياً على `snd-project-8794b`. لإعادة توليد إعداداته، استخدم المعرّف نفسه. تغيير المشروع يحتاج تحديداً صريحاً للمشروع المقصود؛ لا تستخدم اسم العرض مكان المعرّف، ولا تستخدم حساب خدمة أو مفتاح إدارة داخل التطبيق.

إذا لم تكن الأدوات مثبّتة:

```sh
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

من جذر سند شغّل:

```sh
bash tools/configure_firebase.sh snd-project-8794b
```

الأمر يسجّل أو يعيد استخدام تطبيقي iOS وAndroid داخل المشروع المحدّد فقط. لا ينشئ مشروع Firebase جديداً، ولا ينشر الخادم أو قواعد بيانات. ينتج إعدادات FlutterFire في `lib/firebase_options.dart`، وإعداد iOS في `ios/Runner/GoogleService-Info.plist`، وإعداد Android في `android/app/google-services.json`. راجع تطابق Bundle ID/package name قبل البناء. معرّفات إعدادات العميل ليست أسرار إدارة؛ لا تستبدلها بملف حساب خدمة.

التهيئة تستعمل خيارات FlutterFire المولّدة تلقائياً بعد تهيئة Flutter binding:

```dart
import 'core/firebase_bootstrap.dart';
await FirebaseBootstrap.initialize();
```

تُتخطى منصات غير iOS وAndroid بأمان، بما فيها الويب، وتبقى معاينة التطبيق متاحة. خطأ التهيئة يكون `failed` ويستمر التصفح عبر الخادم المستقل؛ لا يُعرض نجاح اتصال وهمي. حالة `ready` تعني إنشاء Firebase App المحلي فقط، لا نجاح إرسال البيانات إلى خدمة لم تُضف بعد.

## متطلبات البناء والتحقق

Firebase Core الحالي يتطلب iOS 15 أو أحدث وAndroid API 23 أو أحدث؛ ضُبط حد iOS الأدنى على 15 وضُمن حد Android ضمن Gradle. ملف plist مضاف إلى Resources في Runner، وGoogle Services plugin مفعّل على Android بواسطة FlutterFire. لا تضف تهيئة `FirebaseApp.configure()` يدوية مكررة في AppDelegate.

```sh
flutter pub get
flutter analyze
flutter build ios --simulator
flutter build apk --debug
```

شغّل التطبيق على المنصتين وتحقق في سجل debug من `Firebase Core initialized: PROJECT_ID.` مع المعرّف المقصود. لا يكفي بناء ناجح لإثبات الربط. لا تطبع محتوى الإعدادات أو بيانات تسجيل دخول CLI في السجلات. إذا لم يُحدّد Project ID أو لم يُنفّذ هذا الفحص، يجب وصف الحالة بأنها «تجهيز الربط بانتظار إعداد المشروع»، وليس اتصالاً مكتملاً.

المراجع: [إعداد Firebase الرسمي لـFlutter](https://firebase.google.com/docs/flutter/setup)، [Firebase CLI](https://firebase.google.com/docs/cli)، [حزمة Firebase Core الرسمية](https://pub.dev/packages/firebase_core).
