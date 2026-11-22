# عقد المنصة الجديدة — 2026-11-03.5

هذه الوثيقة تحكم /api/v2. OpenAPI يحدد كل مسار وحقوله وأمثلته. تبقى عمليات التصفح والبحث والكتالوج والصيانة والتحديث على /api دون كسر نسخ المتجر القديمة. خادم Python المرجعي القديم لا ينفذ المنصة تلقائياً؛ المطلوب تنفيذها في باك سند القائم.

## قواعد HTTP

- HTTPS وJSON UTF-8. Accept وContent-Type من application/json. التواريخ ISO 8601 UTC من الخادم.
- نجاح v2 دائماً `{data:...}`. القوائم `{data:[],meta:{next_cursor:null}}`، مع unread_count للتنبيهات. قائمة فارغة 200. GET لا ينشئ طلباً أو محادثة أو impression.
- حماية الحساب `Authorization: Bearer <Sanad access_token>`، لا device_id في v2 ولا API key سري في Flutter. التفويض من الجلسة لا من user_id في body.
- الخطأ `{error:{code,message,fields:{field:[message]}},request_id}`؛ fields اختيارية. لا stack traces أو SQL أو أسرار.
- 400 JSON غير صالح؛ 401 جلسة؛ 403 إجراء ممنوع؛ 404 غير موجود/غير مملوك؛ 409 تعارض حالة/نسخة/مفتاح؛ 410 تحدٍّ منتهي؛ 413 حجم؛ 415 صيغة؛ 422 تحقق؛ 429 مع Retry-After ثوانٍ؛ 503 غير مفعل. لا fallback ديمو عند فشل الإنتاج.
- كل كتابة تحمل Idempotency-Key بطول16–128. النطاق `(actor,method,canonical_path,key)` مع hash للـbody. التكرار بنفس البيانات يعيد نفس المورد دون حدث جديد؛ اختلاف البيانات بنفس المفتاح 409 idempotency_conflict. قيد فريد ومعاملة للتوازي، واحتفاظ بالنتيجة 7 أيام على الأقل للوظيفة والتقديم والرسالة والشكوى. لا تعِد كتابة متعذرة تلقائياً بمفتاح جديد.
- per_page افتراضي/أقصى50؛ cursor مبهم مربوط بالحساب والاستعلام والترتيب. الصفحة الأولى الأحدث، والتالية أقدم. الرسائل **داخل** الصفحة تصاعدية `(created_at,id)`، وnext_cursor يشير للسجل الأقدم. meta.can_send مطلوبة في رد الرسائل. لا ترسل السجل كله.
- جسم JSON عادي64KiB، رفع الصورة8MiB على البوابة والتطبيق، رد القائمة أقل من2MiB. العميل يرفض الأكبر.

## الدخول والجلسة

GET /capabilities عام: platform_enabled وemail_login وgoogle_login وapple_login وterms_version=2026-11-03 وminimum_client_contract. false للمزوّد غير المعد. توفر Firebase Core لا يعني تفعيل المصادقة.

POST /auth/email/challenge {email,locale:ar}: challenge_id عشوائي، retry_after=60، expires_in=300. لا يكشف وجود حساب. رمز6 أرقام،5 محاولات،5 دقائق. ثلاثة إرساليات لكل بريد خلال10 دقائق، وحد IP منفصل؛ لا رمز في API أو السجلات، حتى staging يستعمل صندوق اختبار.

POST /auth/email/verify {challenge_id,code,name,terms_version}: يثبت البريد وينشئ الحساب إن كان جديداً أو يفتحه. لا يعدّل اسم حساب قائم من شاشة الدخول. الاسم2–80 للحساب الجديد فقط. بعد إثبات الرمز، إذا كان الحساب جديداً والاسم غير موجود، أعد422 name_required دون استهلاك التحدي حتى يكمل المستخدم اسمه ضمن نفس مهلة الخمس دقائق؛ لا تكشف وجود الحساب قبل إثبات الرمز. الحساب القائم يدخل بالبريد والرمز فقط. وتسجّل الموافقة وإصدارها وتاريخها. التحدي أحادي الاستخدام؛ إعادة نفس الطلب/المفتاح بعد فقدان الرد تعيد جلسته ضمن مهلة replay محمية.

POST /auth/social {firebase_id_token,provider,terms_version}: **Firebase ID token** من SDK بعد Google/Apple، وليس Google access token أو Apple authorization code. التحقق بـFirebase Admin لمشروع snd-project-8794b، ثم جلسة سند. لا أسرار خدمة Firebase داخل Flutter.

Session: access_token قوي محدود15 دقيقة، token_type=Bearer، access_expires_at، refresh_token عشوائي256-bit صالح30 يوماً مع تدوير، refresh_expires_at، user. Member: id نص ثابت، name، email، headline، phone، country ISO أو فارغ، providers، summary، skills، languages، experience_years. لا دور إداري قابل للتعديل.

POST /auth/refresh {refresh_token} بلا Bearer، بمفتاح محاولة ثابت محفوظ. تدوير access/refresh بمعاملة، وطلبات متزامنة بنفس المفتاح تعيد الزوج نفسه. احتفظ برد replay **مشفّر**5 دقائق على الأقل للرمز السابق والمفتاح لاستعادة جواب ضائع بعد إغلاق التطبيق. إعادة الرمز السابق بمفتاح مختلف تكشف reuse وتلغي عائلة الجلسة. تخزن بصمات الرموز، ولا نص خام سوى replay مشفر محدود العمر. 401/403 نهائي يمسح جلسة العميل والكاش؛ مهلة الشبكة لا تلغي الحساب.

POST /auth/logout {refresh_token}: إبطال access/refresh للجلسة وربط FCM الخاص بها فوراً؛ لا يوقف أجهزة الحساب الأخرى. عند تعذر تأكيد الإلغاء يعرض العميل إعادة المحاولة. لا تعتمد على انتظار انتهاء JWT فقط.

## الملف والحذف والحظر

GET /me لصاحب الجلسة. PATCH /me {name,headline,phone,summary,skills,languages,experience_years}: المسمى headline≤160، النبذة summary≤1000، هاتف E.164 اختياري أو فارغ. skills مصفوفة حتى20 عنصراً، languages حتى10؛ كل عنصر1–40 حرفاً بعد trim، بلا تكرار. experience_years عدد صحيح0–60 أو null؛ الصفر يعني دون خبرة وليس غياب المعلومة. الحقول المهنية الإضافية اختيارية، وأرجع defaults للحساب القديم: summary فارغ، skills/languages=[]، experience_years=null. واجهة الاكتمال تعد الحقول الفعلية فقط ولا تعني تقييم قابلية التوظيف. لا تعديل بريد أو ملكية أو role. الملف خاص، ويشارك عند التقديم فقط.

POST /me/identities {provider,firebase_id_token}: جلسة قائمة، مزوّد موثق، بريد مطابق موثق، auth_time حديث<5 دقائق، identity غير مرتبطة بحساب آخر. لا دمج تلقائياً بمجرد تساوي البريد في social login. عند وجود حساب سابق أعد account_exists_use_email مع إرشاد الدخول بالبريد ثم الربط. Apple Private Relay لا يربط ببريد مختلف تلقائياً.

POST /auth/reauth/email/challenge يرسل لبريد الحساب الحالي؛ body فارغ. POST /auth/reauth/verify {challenge_id,code} يعيد reauth_ticket أحادية5 دقائق. DELETE /me {reauth_ticket}: يلغي كل الجلسات وFCM، يسحب الفرص، يلغي الطلبات النشطة، ويزيل الملف والصور الخاصة. المحادثات للطرف الآخر للقراءة باسم «حساب محذوف» دون الملف، وفق مدة الاحتفاظ في SECURITY.md. الحذف idempotent حتى عندما تضيع الاستجابة بعد إبطال الجلسة، دون إحياء التوكن. لا كلمة مرور لحساب اجتماعي فقط.

GET /me/blocks، PUT وDELETE /me/blocks/{memberId}. الحظر يمنع الرسائل في الاتجاهين ولا ينبه الطرف المحظور أو يكشف من حظره. إلغاء حظري لا يلغي حظر الطرف الآخر. التفويض يتحقق في كل إرسال، وليس UI فقط.

## المحفوظات والبحث المحفوظ

GET /me/favorite-ids كل المعرفات كنصوص حتى10000 لتثبيت القلب دون طلب لكل كارد؛ حد الإضافة422. GET /me/favorites صفحات Job كاملة مع الحالات؛ تبقى فرصة توقفت مع علامة غير متاحة، دون كشف pending أو تواصل محذوف. PUT /me/favorites/{jobId} يضمن الحفظ ويعيد **Job كاملة**؛ DELETE يضمن الإزالة ويعيد data.success=true. ليست toggle.

GET/POST /me/saved-searches وDELETE .../{searchId}: حتى20 بحثاً، name1–120، query≤200، filters بأسماء SavedSearchFilters الدقيقة في OpenAPI؛ البلد ISO، المحافظة من الكتالوج، category اسم معتمد، minSalary مع العملة والفترة. طبّع المطابقة مثل /api/filterjob، وامنع تكرار نفس الفلتر.

عند إنشاء البحث يسجل watermark صامتاً: الفرص القديمة ليست جديدة. نشر فرصة بعده ينشئ تطابقاً فريداً `(member_id,job_id)` حتى لو طابق عدة فلاتر. GET /me/saved-search-matches يعيد Job منشورة سارية مع is_new وannounced. PUT .../read {job_ids:["970001"]} للمفتوح، وPUT .../acknowledge يمنع تكرار رسالة العودة دون اعتبار التفاصيل مقروءة. حالات متزامنة بين الأجهزة؛ لا تعتمد على ساعة الهاتف أو أول50 نتيجة محلية.

## الإعلان والمراجعة

POST /jobs يستقبل CreateAccountJob: النموذج القديم بلا device_id، مع contact_consent=true وaccepts_applications=true. المالك من الجلسة، والحالة pending دائماً؛ ارفض id/status/owner_id/created_at وحقول الخادم الإضافية. البلد ثم المحافظة، مدة7/14/30، العملة مستقلة عن بلد الهاتف، وتطبيع REGIONS.md في القديم والجديد.

GET /me/jobs وGET /me/jobs/{id} يعيدان **كامل** العنوان والوصف والمتطلبات والتواصل والراتب والمكان والحالة حتى pending/rejected، مع applications_count وrejection_reason الخاصين. عنوان فقط أو حذف التفاصيل غير مقبول. POST /jobs/{id}/withdraw يوقف الظهور والتقديم الجديد ويبقي الطلبات والمحادثات السابقة للمراجعة.

GET /admin/jobs طابور المراجعة. POST .../approve ينشر المنتظر غير المنتهي ويسجل published_at من الخادم. POST .../reject {reason} يرفض المنتظر أو يزيل المنشور المخالف بسبب خاص للمالك. إعادة approve لا تعيد إطلاق إشعارات التطابق. لا pending للعامة عبر البحث أو التفاصيل أو المحفوظات. توكن المشرف لا يصل للعميل.

الفرص المستوردة مجهولة المالك تبقى accepts_applications=false وتواصلها خارجياً. تفعيل تقديمها يحتاج ربط ملكية مثبت إدارياً؛ device_id المكشوف سابقاً ليس إثبات ملكية. لا تنشئ شات مع جهة ليست صاحبة حساب.

## التقديم والحالة

POST /jobs/{id}/applications {note} لفرصة منشورة سارية تقبل التقديم، والمتقدم ليس مالكها. note اختياري≤2000. Unique(member_id,job_id)، ولقطة مصرح بها من الملف من الخادم، لا applicant_id من body. البداية submitted. إعادة التقديم تعيد الموجود200 ولو بمفتاح مختلف. withdrawn نهائية، دون طلب ثانٍ لنفس الفرصة في هذا الإصدار.

GET /me/applications للمتقدم، GET /jobs/{id}/applications للمالك، GET /applications/{id} لأحدهما فقط. الرد: Job، applicant المسموح، note، status، conversation_id أو null، viewer_role من الخادم، version، created_at، updated_at، history. لا ملاحظات إدارة أو ملفات أشخاص آخرين.

PATCH /applications/{id} {status,note,expected_version}: قفل صف/compare-and-swap بمعاملة؛ تزيد version، وتعارض409 version_conflict يتطلب قراءة جديدة. note سبب مرئي≤500. history غير قابل للتحرير. لا تغيير حالة بمجرد فتح الطلب.

| الفاعل والحالة | الانتقالات |
| --- | --- |
| المالك: submitted | under_review، shortlisted، accepted، rejected |
| المالك: under_review | shortlisted، accepted، rejected |
| المالك: shortlisted | accepted، rejected |
| المتقدم: submitted/under_review/shortlisted | withdrawn فقط |
| accepted/rejected/withdrawn | نهائية، لا رجوع |

قبول متقدم لا يغلق الفرصة تلقائياً ولا يمثل عقد توظيف. المعلن يسحب الإعلان عند الانتهاء. إشعار تغيير الحالة للمتقدم، وإشعار سحب الطلب للمالك.

### البحث وتصفية الطلبات — إضافة مستوحاة من المرجع

GET /me/applications وGET /jobs/{jobId}/applications يقبلان status اختياري من الحالات الست، q≤200 حرف، sort=newest|oldest (افتراضي newest)، مع per_page/cursor الحاليين. الأول يبحث بعنوان الوظيفة واسم الجهة؛ الثاني باسم المتقدم ومسمّاه ومهاراته من profile_snapshot المصرح به. طبّق ملكية السجلات أولاً، ثم البحث والتصفية، ثم pagination، ولا تبحث في حسابات لم تقدم إلى هذه الفرصة. البحث Unicode parameterized دون تركيب SQL، والترتيب `(created_at,id)` في الاتجاه المطلوب. cursor مربوط بالعضو والمسار والفلاتر والترتيب؛ تغييرها مع cursor قديم يعيد422 invalid_cursor. لا تستخدم أول50 نتيجة لتوهم المستخدم أنها كل نتائج البحث. القائمة الفارغة200 طبيعية؛ التاريخ من created_at الخادمي. لا إشعار عند الفرز أو البحث أو قراءة الملف، ولا تغيير حالة الطلب آلياً.

## المحادثات

POST /applications/{id}/conversation: المالك يبدأ لطلب غير withdrawn، والمتقدم يسترجع الموجودة فقط. Unique(application_id)، الموجود200 والجديد201، وغير المخول404. peer للطرف الآخر، job_title/id، last_message أو null، unread_count، can_send وblocked_by_me.

GET /conversations وGET /conversations/{id} وGET .../messages للمشاركين فقط. الرسالة id/client_id/sender_id/text/created_at/delivery_state. هوية المرسل والتاريخ من الخادم. POST .../messages {client_id,text} بطول1–4000. Unique(conversation_id,sender_id,client_id)، واختلاف النص لنفس المعرف409. لا صور أو صوت أو CV في الشات بهذا الإصدار؛ صورة الشكوى منفصلة. لا «متصل الآن» دون presence فعلية.

PUT .../read {message_id} يتقدم فقط لرسالة حقيقية داخل المحادثة ولا يرجع للخلف. delivered لا تعني قبول FCM؛ إن لم يوجد ACK تسليم فعلي تبقى sent حتى read. لا ادعاء تشفير من طرف لطرف.

العميل يستخدم polling كل8 ثوانٍ للمحادثة الظاهرة فقط،30 ثانية بعد خطأ، ويتوقف بالخلفية. FCM يحدّث المحادثة الظاهرة دون إشعار محلي مكرر. آخر50 رسالة أولاً ثم cursor للأقدم. WebSocket/Pusher ليس شرطاً ولا توجد مفاتيح وهمية له.

## الشكاوى والمرفقات

POST /uploads {purpose:complaint,mime_type,content_base64} لصورة JPG/PNG/WebP حقيقية≤5MiB بعد فك Base64، body≤8MiB. يرجع id وexpires_at لمدة24 ساعة؛ الرفع خاص بالعضو. افحص البايتات فعلياً وأبعاد≤20MP، أعد الترميز لإزالة EXIF، وامنع SVG/HTML والملفات المؤذية؛ لا تعتمد على الامتداد. نظّف الرفع غير المرتبط بعد24 ساعة.

POST /complaints {text,image_id?,conversation_id?}: نص10–4000؛ الصورة ملكه وللغرض الصحيح وغير مستعملة لشكوى أخرى؛ المحادثة له. معاملة واحدة تربط الشكوى والصورة والحدث. GET /me/complaints الحالة والرد ورابط صورة موقّع قصير العمر للمبلّغ فقط؛ لا Bearer إلى نطاق صورة خارجي ولا مرفق عام. GET/PATCH /admin/complaints لمشرف مخول، response مرئي للمبلّغ.

## الإشعارات والكاش والتقييم والإعلانات

NOTIFICATION-EVENTS.md مرجع الأحداث. PUT /me/push-device يربط الرمز بالجلسة وينزعه من الحساب السابق؛ لا يعيد ربطه طلب visit قديم غير مصادق. GET /me/notifications مع payload وجهة، PUT .../{id}/read للمالك. تفضيلات GET/PUT /me/notification-preferences للـpush فقط؛ لا تلغي صندوق الحساب.

النقل URLSession على iOS وCronet المضمّن على Android، وعميل المتصفح للويب. HTTP cache معطل. كاش عام في JobsStore، وخاص محدود في PlatformStore بنطاق API+member، آمن على الموبايل حتى7 أيام و768KiB، وoutbox≤50. يمسح عند الخروج؛ المتصفح ليس Keychain. لا تقديم/نشر/تغيير حالة أوفلاين. الرسالة الفاشلة تعاد يدوياً بنفس client_id، والرد القديم بعد تبديل الحساب يتجاهل. 401 متوازية تشترك بطلب refresh واحد.

لا مسار لإعلانات AdMob أو impressions مصطنعة. Native بالهوم وبانر مشترك للتفاصيل/الإشعارات بكاشRAM55 دقيقة ومالك واحد. لا إعلانات بالدخول أو التقديم أو الشات أو الشكوى. AdSense غير مفعل. التقييم SDK أصلي بعد7 أيام و3 إجراءات فعلية، وفاصل120 يوماً؛ دون سؤال رضا أو حافز أو ضمان ظهور النافذة. الموقع يبرز تحميل Android؛ iOS «قريباً» حسب المالك.
