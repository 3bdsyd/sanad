# مشاركة الفرص والروابط العميقة

المشاركة ترسل نص الفرصة مع رابط HTTPS:
`https://jobsnad.com/jobs/{id}`

على الويب يتغيّر شريط العنوان إلى `/jobs/{id}` عند فتح الفرصة من القائمة أو المحفوظات أو المتابعة. الرجوع والتقدّم في المتصفح يعيدان الصفحة والرابط معاً، ويُعاد فتح الفرصة عند تحديث الرابط أو مشاركته. فتح رابط مباشر ينشئ مسار رجوع إلى الرئيسية داخل الموقع؛ تبقى حماية مسودة النشر فعّالة عند الرجوع.

## سلوك الفتح

| الحالة | النتيجة |
| --- | --- |
| التطبيق مثبت + روابط موثّقة (Universal / App Links) | يفتح التطبيق على تفاصيل الفرصة |
| لا يوجد تطبيق | يفتح المتصفح على موقع سند ويفتح التفاصيل داخل الويب |
| معاينة محلية بلا دومين | المشاركة تعمل كنص؛ الرابط يعتمد `WEB_BASE_URL` |

## ما يلزم على الاستضافة

1. رفع مجلد `build/web` بما فيه `.well-known/`.
2. استبدال `TEAMID` في `.well-known/apple-app-site-association` بـ Apple Team ID من حساب المطوّر.
3. استبدال قيمة `REPLACE_…` في `.well-known/assetlinks.json` ببصمة SHA-256 لشهادة **توقيع التطبيق المثبّت**. عند التوزيع عبر Play App Signing استخدم شهادة App signing من Play Console، وليس شهادة upload وحدها. يمكن إضافة أكثر من شهادة عند وجود قنوات توزيع فعلية مختلفة. [مرجع Android الرسمي](https://developer.android.com/training/app-links/configure-assetlinks).
4. تفعيل Associated Domains على الـ Apple Developer App ID لـ `com.jobsnad.snad`.

بدون الخطوتين 2–4 يبقى الرابط يفتح المتصفح دائماً؛ التطبيق يفتح الرابط فقط بعد توثيق الدومين.

يتولى `app_links` استقبال الروابط؛ عُطّل معالج Flutter الافتراضي في إعدادات Android وiOS حتى لا يتنافس معه. مخطط `sanad://jobs/{id}` مسجّل على المنصتين للاختبار؛ رابط المشاركة العام يبقى HTTPS. [مرجع Flutter](https://docs.flutter.dev/ui/navigation/deep-linking).

فحص 30 سبتمبر 2026 وجد قيم `TEAMID` و`REPLACE_…` في ملفات الموقع المنشورة أيضاً؛ وجود ملفات JSON بحالة 200 لا يكفي لتوثيق الروابط.

## بناء مع رابط المشاركة

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://admin.jobsnad.com \
  --dart-define=WEB_BASE_URL=https://jobsnad.com
```
