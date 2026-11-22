# Firebase لتطبيق سند

أضيفت حزمة `firebase_core` الرسمية وتهيئة آمنة في [firebase_bootstrap.dart](../lib/core/firebase_bootstrap.dart). معرّف Android وiOS الحالي هو `com.jobsnad.snad` ضمن مشروع Firebase `snd-project-8794b`، رقم المشروع `377548025897`. تطبيقَا Android وiOS بالمعرّف `com.jobsnad.snad` مسجّلان في Firebase، وهذه هي معرّفات التطبيق وإعداداتهما الحالية.

| المنصة | Firebase App ID |
| --- | --- |
| iOS | `1:377548025897:ios:cd3a2efd884c58a36bac38` |
| Android | `1:377548025897:android:90cc0a4f24dd28c56bac38` |

بيانات الفرص تبقى على [خادم REST الحالي](backend.md). أُضيف Firebase Messaging وإشعارات الجهاز على Android وiOS. لا تُستخدم Firestore أو Analytics. في تحديث4 نوفمبر2026 أُضيف عميل Firebase Authentication لتوثيق Google/Apple فقط؛ جلسة سند وبيانات الحساب والبريد ورمز الدخول تديرها API المنصة، ولا يعني وجود SDK أن المزودين مفعلان في لوحة Firebase. [إعدادات المنصة المطلوبة](backend-handoff-2026-11-03/CONFIGURATION.md). تفاصيل التنفيذ والتحقق في [الإشعارات والتنقل](notifications-and-navigation.md).

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

Firebase Core الحالي يتطلب iOS 15 أو أحدث وAndroid API 23 أو أحدث؛ ضُبط حد iOS الأدنى على 15 وضُمن حد Android ضمن Gradle؛ التطبيق ككل يحتاج API24 بسبب مكتبة الإعلانات. ملف plist مضاف إلى Resources في Runner، وGoogle Services plugin مفعّل على Android بواسطة FlutterFire. لا تضف تهيئة `FirebaseApp.configure()` يدوية مكررة في AppDelegate.

حد iOS 15 مثبت في إعدادات المشروع وهدفي `Runner` و`RunnerTests` لكل من Debug وProfile وRelease، وفي `AppFrameworkInfo.plist`. Flutter يحدّث حد حزمة Swift المولدة من إعدادات الهدف أثناء بناء iOS؛ لا تعدّل `ios/Flutter/ephemeral` يدوياً ولا تشغّل بناء منصتين بالتوازي لأن توليد ملفات Flutter مشترك بينهما.

```sh
flutter pub get
flutter analyze
flutter build ios --simulator
flutter build apk --debug
```

شغّل التطبيق على المنصتين وتحقق في سجل debug من `Firebase Core initialized: PROJECT_ID.` مع المعرّف المقصود. لا يكفي بناء ناجح لإثبات الربط. لا تطبع محتوى الإعدادات أو بيانات تسجيل دخول CLI في السجلات. إذا لم يُحدّد Project ID أو لم يُنفّذ هذا الفحص، يجب وصف الحالة بأنها «تجهيز الربط بانتظار إعداد المشروع»، وليس اتصالاً مكتملاً.

المراجع: [إعداد Firebase الرسمي لـFlutter](https://firebase.google.com/docs/flutter/setup)، [Firebase CLI](https://firebase.google.com/docs/cli)، [حزمة Firebase Core الرسمية](https://pub.dev/packages/firebase_core).


فحص الإنتاج في 5 أكتوبر 2026: تأكد تسجيل Android وiOS عبر Firebase CLI، وصُحح اعتماد إرسال Laravel إلى مشروع سند، ووُضع خارج الويب ودُوّر المفتاح بموافقة المستخدم. نجح FCM `validate_only` بعد الإصلاح. تفاصيل الحماية وحدود اختبار التسليم في [تدقيق الإشعارات](notifications-and-navigation.md#تدقيق-وإصلاح-الخادم-الحي--5-أكتوبر-2026).

مجموعة FlutterFire المثبتة للتحضير الحالي: Core4.15.2 وAuth6.7.1 وMessaging16.7.1، تطلب Firebase Apple SDK12.19.3 نفسه. تثبيت هذه المجموعة يمنع تعارض SPM exact versions، ولا يغير Project ID أو Bundle ID أو التوقيع. لا تعدّل نسخ الحزم داخل pub-cache يدوياً.
