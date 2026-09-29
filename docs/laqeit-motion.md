# لقيت — الحركة جزء من الاستخدام

> هذه وثيقة للنسخة السابقة. التصميم الحالي يلغي البوب أب ويستخدم صفحات كاملة وألواناً موحّدة؛ راجع [إعادة التصميم](redesign-ux.md).

الاسم الظاهر أصبح «لقيت»، مع بقاء معرفات الحزمة والقنوات ومفاتيح `fursa.*` كما هي حتى لا يفقد المستخدم المحفوظة وإدارة إعلاناته.

## الرحلات

- الرئيسية تستخدم هيدر يتمدد ثم ينكمش مع التمرير؛ البحث والفلاتر يبقيان مثبتين. بطاقات القائمة تبنى عند اقترابها من الشاشة.
- فتح الفرصة يلتقط الكارد ويربط مستطيله بشاشة التفاصيل خلال 620ms؛ الرجوع يعكس الانتقال. الصورة المؤقتة تُحرر بعد انتهاء المسار. تعذّر التقاطها لا يمنع فتح التفاصيل.
- القلب يحمل الكارد بصرياً باتجاه المحفوظة. الفرصة تختفي من نتائج الاكتشاف بعد حفظها؛ خيار «إظهار المحفوظة» يعيد إدراجها. الضغط المطوّل يتيح حمل البطاقة وإفلاتها على هدف المحفوظة فوق الناف بار، والقلب بديل متاح دون سحب.
- تفاصيل الفرصة لها عنوان مثبت ينكمش، وحفظ سريع، ومنطقة تواصل ثابتة تظهر بعد التمرير. التحقق الخادمي من توفر الإعلان قبل التواصل بقي قائماً.
- نموذج النشر والفلاتر يبدأان بارتفاع 78%، ويتمدّدان إلى المساحة الكاملة المتاحة بالسحب أو مقبض التوسيع. التركيز على حقل النشر يوسّع النموذج ثم يكشف الحقل فوق الكيبورد. التحقق يشمل حقول الخطوة كلها، وينقل التركيز لأول خطأ.
- الأخطاء رسائل `SignalCard` ثابتة في سياق الإجراء مع إغلاق صريح؛ لا SnackBar ولا اختفاء تلقائي للمعلومة قبل قراءتها.
- الفلاتر مجموعات خيارات تتمدد داخل الصفحة. البحث والفلاتر النشطة يستعادان محلياً. يمكن حفظ حتى 20 بحثاً وحذفها أو تطبيقها من الرئيسية.
- «على بالك» مركز متابعة داخل التطبيق: فرص متاحة تطابق عمليات البحث المحفوظة، وحالات إعلانات صاحب الجهاز. العلامة الزرقاء تعني نتيجة لم تُفتح بعد، وليست إشعار دفع أو ادعاء وصول جديد. السحب يحدث البيانات؛ لا توجد خدمة push خلفية.
- جميع الحركات الهيكلية تحترم Reduce Motion. UITabBar الأصلي والقنوات الأصلية باقية، ولا يوجد تسجيل دخول جديد.

## الهوية والأصول

علامة «لقيت» السابقة ما عادت ضمن حزمة التطبيق. اللوغو المعتمد هو [سند](../assets/images/sanad-logo.png)، وأيقونات المنصات تتولد منه عبر [مولّد أيقونات التطبيق](../tools/generate_brand_assets.py). أيقونات الإجراءات تبقى متجهة في [المصدر](../assets/icons/fursa-symbols.json).

الأمر الوصفي المستخدم للتوليد:

> Use case: logo-brand. Create one final polished app icon for a Syrian Arabic jobs app named Laqeit (لقيت, means 'I found'). No typography or letters in the artwork. A distinctive original white bold rounded geometric symbol combining an open doorway, a path turning upward/right, and a small warm golden dot suggesting a person arriving at opportunity. Simple instantly recognizable silhouette, slightly sculpted premium 3D enamel or soft glass depth but mostly flat enough to remain crystal clear at 24px. Palette: slate blue #467BB6 full-bleed opaque square background with a very restrained #6794BF light upper-left glow; pure warm white symbol; one tiny golden #FFD178 accent only. Symbol centered, occupies 58% of canvas with generous equal margins. Square 1024x1024 composition. Full canvas filled, NO rounded app-icon mask baked in, no border, no surrounding device/mockup, no frame, no text, no watermark, no busy decoration, no briefcase stock icon, no resemblance to an existing brand. Designed for iOS and Android launcher icon and small in-app brand mark.

## المعاينة

[الرئيسية](screenshots/laqeit-home.png) · [البحث المثبت](screenshots/laqeit-pinned.png) · [الفلاتر](screenshots/laqeit-filters.png) · [المتابعة](screenshots/laqeit-notifications.png) · [النموذج](screenshots/laqeit-form-sheet.png) · [التحقق](screenshots/laqeit-validation.png).

هذه معاينة ببيانات تجريبية؛ نشر الخدمة وتشغيل الإشراف وإشعارات الدفع الخارجية ليس جزءاً من هذه التعديلات. لا توجد مزاعم نجاح تجاري أو اختبار على شبكة سورية فعلية.

## التحقق المنفذ

- `dart format .` و`flutter analyze`: دون ملاحظات.
- بناء release للويب وبناء debug لمحاكي iOS نجحا.
- فحص Chrome فعلي أكد حمل البطاقة وإفلاتها على المحفوظة، فتح التفاصيل، تثبيت الهيدر، حفظ الفلاتر والبحث واستعادتهما بعد reload، وتطابق نتائج المتابعة. لم تظهر page errors.
- فحص النموذج أدخل بيانات صحيحة، ترك الوصف خارج الجزء المرئي فارغاً، فتوقف الانتقال وانتقل التركيز إليه؛ ثم تحقق من اشتراط وسيلة التواصل وأتم حفظ إعلان تجريبي محلي.
- Reduce Motion: صورتان متتاليتان لشاشة البداية متطابقتان، والحفظ يعمل دون حركة. تمت معاينة 320×640 و390×844 وسطح المكتب.
- XCTest مؤقت خارج المشروع: اختباران ناجحان على iPhone 17 / iOS 26.5. تأكدت تبويبات UITabBar الثلاثة، فتح التفاصيل، تمدد النموذج، ظهور الكيبورد، وانتقال التركيز إلى الوصف الخاطئ. [الآيفون](screenshots/laqeit-iphone-home.png) · [تركيز الحقل فوق الكيبورد](screenshots/laqeit-iphone-field-focus.png).
- لا توجد حزمة اختبارات أو متطلبات PR جديدة داخل المستودع. لم يُختبر هاتف فعلي أو VoiceOver أو إشعارات push.
