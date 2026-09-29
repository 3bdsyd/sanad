# نشر سند على الويب

الويب مفيد للتصفح بلا تثبيت ولروابط مشاركة الفرص. Firebase Core يتخطّى الويب عمداً؛ الفرص تبقى على `https://snd.avorix.io`. التخزين الآمن على المتصفح أضعف من الجوال — لا تعتمد عليه لإدارة إعلانات حساسة على جهاز مشترك.

## بناء

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://snd.avorix.io \
  --dart-define=WEB_BASE_URL=https://YOUR_WEB_HOST \
  --dart-define=SUPPORT_URL=https://… \
  --dart-define=PRIVACY_URL=https://…
```

للمعاينة المحلية بعد البناء:

```bash
cd build/web && python3 -m http.server 5180
# ثم افتح http://127.0.0.1:5180
```

المخرجات في `build/web`. اضبط `WEB_BASE_URL` على أصل الموقع العام (HTTPS) حتى زر المشاركة يضم رابطاً مثل `https://YOUR_WEB_HOST/jobs/{id}`. على الويب يُتخطّى شرط روابط الدعم/الخصوصية عند التشغيل حتى لا تتعطّل المعاينة؛ للرفع العام أبقِ الروابط مضبوطة.

## استضافة مقترحة

- **Firebase Hosting** (نفس مشروع `snd-project-8794b`) أو Cloudflare Pages أو مجلد static على خادمك.
- أضف أصل الويب إلى `ALLOWED_ORIGINS` على الـ API؛ بدون ذلك المتصفح يرفض الطلبات.
- اجعل كل المسارات تعيد `index.html` (SPA rewrite) حتى الروابط العميقة لا تكسر التحميل.

مثال Firebase Hosting بعد `firebase login`:

```bash
firebase init hosting   # public = build/web ، single-page app = yes
firebase deploy --only hosting
```

## حدود النسخة الحالية

- فتح `/jobs/{id}` من الرابط المشترك يعرض التطبيق، لكن توجيه المسار إلى شاشة التفاصيل لم يُفعَّل بعد؛ المشاركة تنقل النص والرابط، والتصفح اليدوي من الهوم يعمل.
- الناف بار الأصلي iOS غير موجود على الويب؛ يظهر بديل Flutter الزجاجي.
- لا تنشر بدون CORS مضبوط وروابط دعم/خصوصية حقيقية إن كان الإصدار عاماً.
