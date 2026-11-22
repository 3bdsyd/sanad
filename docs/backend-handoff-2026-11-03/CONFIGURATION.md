# إعدادات التشغيل خارج شيفرة الواجهات

وجود مكتبة تسجيل دخول لا يعني أن Google/Apple أو البريد مفعلون. لا نسخ جديدة للمتجر قبل نجاح staging والإعدادات التالية. لا تغير مفاتيح الإنتاج أو الاشتراك أو الشهادات بشكل ضمني.

## الباك

- Firebase Admin SDK لمشروع snd-project-8794b مع credentials في secret manager/بيئة الخادم فقط، تحقق revoked tokens ومزوّد الهوية/aud/iss/auth_time.
- SMTP/مزود بريد مع نطاق إرسال موثوق وSPF/DKIM/DMARC، قالب OTP عربي5 دقائق، rate limits وqueue. staging بصندوق اختبار حقيقي؛ لا رمز ثابت في الإنتاج.
- أسرار access/refresh/HMAC/encryption مستقلة، TLS، قاعدة migrations، queue workers وscheduler ومخزن صور خاص، signed URLs، audit/backup/retention حسب SECURITY.md.
- FCM HTTP v1 credentials وAPNs key على Firebase من حساب Apple المدفوع المالك، صلاحيات Admin محدودة. لا server key داخل Flutter.
- capabilities تعكس الحالة الفعلية لكل مزود. تقديم Google/Apple كمتاحين مع إعداد ناقص ليس تسليماً ناجحاً.

## Google / Flutter

الحزم المضافة: firebase_auth6.7.1، google_sign_in7.2.0. لا Firestore أو Analytics. Firebase لتوثيق الهوية فقط، ثم POST /api/v2/auth/social للحصول على توكن سند. الجلسة الطويلة عند باك سند؛ يسجل العميل خروج SDK بعد التبادل.

فعّل Google ضمن Firebase Authentication وأضف SHA-1/SHA-256 لتوقيع Android النهائي وpackage com.jobsnad.snad. نزّل google-services.json وGoogleService-Info.plist من المشروع الحقيقي مع OAuth clients؛ ملفات Core الحالية لا تحتوي إعداد Google iOS كامل. لا تولّد OAuth IDs عشوائية.

Dart defines العامة: GOOGLE_SERVER_CLIENT_ID هو Web OAuth client الخاص بالتبادل، وGOOGLE_IOS_CLIENT_ID هو iOS OAuth client. عند iOS حدّث URL Types بالـREVERSED_CLIENT_ID الحقيقي وفق وثائق google_sign_in_ios. لا تعتبر URL scheme غير موجود قابلاً للإصلاح من الباك وحده. لم توضع قيم وهمية في plist.

Google على الويب يحتاج Firebase Web app حقيقية، define FIREBASE_WEB_APP_ID وFIREBASE_WEB_API_KEY وFIREBASE_WEB_AUTH_DOMAIN، وjobsnad.com ضمن authorized domains. لا تستعمل appId الهاتف للويب. إذا لم تضبط، خيار البريد يبقى طريق الدخول، مع رسالة واضحة للدخول السريع. API keys العامة المقيدة ليست credentials خادم.

## Apple

فعّل Sign in with Apple على App ID com.jobsnad.snad وفي Firebase Authentication: Team/Key/Services ID ومفتاح p8 في موضعه المحمي، وربط redirect المعتمد للويب/Android. استحقاق com.apple.developer.applesignin موجود في مشروع الإنتاج، لكن يلزم provisioning من فريق المالك المدفوع يدعم الميزة. لا تغيّر فريق الإنتاج لإرضاء بناء مجاني ولا تستخدم Ahmed Alkhamsen.

اختبر Apple إخفاء البريد/Private Relay، الاسم الذي قد يعاد مرة واحدة، دخول متكرر، الإلغاء، إعادة توثيق الحساب، ربط مزود آخر وحذف الحساب. Firebase Admin يتحقق من Firebase ID token؛ لا تطلب من الباك تفسير Apple token الخام بينما العميل يرسل Firebase token.

نسخة عبدالرحمن المجانية منفصلة ولا تثبت Apple Sign In أو APNs/Associated Domains. تجهيز الميزات لا يعني أنها تعمل بتوقيع مجاني أو أن حساب المتجر وافق عليها.

## صورة الشكوى والمتاجر

اختيار الصور system gallery عبر image_picker بلا طلب جهات اتصال أو موقع. NSPhotoLibraryUsageDescription مضافة، وrequestFullMetadata=false. لا كاميرا أو microphone مطلوبة لهذا الإصدار. تحقق من Android process-death/lost picker result قبل متجر نهائي.

التقييم عبر in_app_review: نافذة iOS/Google Play الأصلية، لا widget نجوم مقلد. بعد7 أيام و3 إجراءات، حد مرة في الجلسة وفاصل120 يوماً. المتجر يتحكم بالظهور؛ النسخة الشخصية/Android sideload ليست دليلاً على ظهور production. لا تربط التقييم بمكافأة أو فلترة «راضٍ/غير راضٍ».

Google Play: https://play.google.com/store/apps/details?id=com.jobsnad.snad حسب رابط المالك. iOS غير منشور بعد؛ يظهر «قريباً على App Store» بلا رابط مخترع. الموقع يعرض دعوة تحميل تغطي المحتوى وقابلة للإغلاق مرة لكل تحميل صفحة، ويحفظ مسار الفرصة المطلوبة. لا AdSense حتى موافقة الموقع وكود حساب حقيقي.

## مراجع أولية رسمية

- [Firebase Flutter federated auth](https://firebase.google.com/docs/auth/flutter/federated-auth)
- [Firebase verify ID tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Google Sign-In Flutter](https://pub.dev/packages/google_sign_in) و[iOS setup](https://pub.dev/packages/google_sign_in_ios)
- [Apple Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
- [Google Play in-app review](https://developer.android.com/guide/playcore/in-app-review)
- [Apple requestReview](https://developer.apple.com/documentation/storekit/appstore/requestreview(in:))
- [in_app_review](https://pub.dev/packages/in_app_review) و[image_picker](https://pub.dev/packages/image_picker)

مراجعة المصادر بتاريخ3 نوفمبر2026؛ نجاح build لا يثبت إعداد حسابات المزودين أو تسليم البريد/Push.

## ما يعيده الباك لفريق Flutter

عبّئ [public-client-config.json](examples/public-client-config.json) بالقيم العامة المؤكدة فقط. ليس ملف بناء جاهزاً ولا تحوله إلى config/production.json وهو يحمل null أو عنوان staging الوهمي. لا Firebase service-account أو Apple p8 أو client_secret أو SMTP password أو مفاتيح توقيع فيه. GOOGLE_REVERSED_CLIENT_ID يحتاج إضافته إلى iOS URL Types بعد وصول القيمة الحقيقية؛ Dart define وحده لا يضيف URL scheme إلى تطبيق مثبت.

CORS لـv2 يسمح بالأصول المعتمدة فقط وبـAuthorization وContent-Type وAccept وIdempotency-Key في preflight، والطرق GET/POST/PUT/PATCH/DELETE/OPTIONS. لا wildcard أو cookies مضافة بلا تصميم. Cache-Control:no-store للخاص والمصادقة. استعمل app/version-check الحالي للتحديث الإجباري؛ minimum_client_contract في capabilities يوثق نسخة العقد ولا يغني عن حظر نسخ غير متوافقة عبر آلية تحديث التطبيق القائمة.

## حزم FlutterFire الأصلية

تحديث محلي4 نوفمبر2026: محاذاة firebase_core4.15.2 وfirebase_auth6.7.1 وfirebase_messaging16.7.1 على Firebase Apple SDK12.19.3؛ الإبقاء على Messaging16.7.0 كان يطلب12.19.0 تحديداً ويسبب تعارض Swift Package Manager. لا تعدل Package.swift داخل pub-cache أو الملفات المولدة لإخفاء التعارض. تُحدّث مجموعة FlutterFire معاً وتُبنى المنصتان بعد أي تغيير. [حزمة Messaging الرسمية16.7.1](https://pub.dev/packages/firebase_messaging/versions/16.7.1).

## تنزيل مكتبات Android في هذه الشبكة

أعاد dl.google.com خطأ404 لمكتبات منشورة، بينما أعاد نطاق توزيع Google الرسمي redirector.gvt1.com ملفات POM الصحيحة للمكتبات نفسها. أُضيف خيار بناء اختياري `snadGoogleDownloadFallback` في android/build.gradle.kts، محصور بمجموعات Google وAndroidX وعلى HTTPS، ومغلق افتراضياً. عند الحاجة فقط: `ORG_GRADLE_PROJECT_snadGoogleDownloadFallback=true flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/production.json`. لا يغيّر اتصال التطبيق أو يضيف مستودع طرف ثالث، ولا يحتاج أي إعداد من Laravel.

لتجاوز تعذر تنزيل أرشيفات iOS في هذه الشبكة، طوبقت بصمات GoogleMobileAds وFirebaseAnalytics وFirebaseFirestoreInternal من manifests الرسمية قبل وضعها في كاش SwiftPM. لا يعني تنزيل تبعيات SDK استعمال Firestore أو Analytics في التطبيق؛ لا يربط التطبيق خدماتهما. لم تعدّل مصادر SDK أو checksums. تظل نتيجة البناء الفعلية في VERIFICATION.md.

وحّدت ملفات Package.resolved في المشروع ومساحة العمل من ناتج حل مساحة العمل الرسمية؛ كانت مرحلة حل المشروع تختار إصدار إعلانات مختلفاً عن مرحلة بناء مساحة العمل. بقي SDK الإعلانات13.11.0 السابق، مع Firebase12.19.3 وGoogleSignIn9.2.0. لا تحديث تلقائي منفرداً لأي ملف lock قبل التحقق من الملف الآخر وبناء التطبيق.
