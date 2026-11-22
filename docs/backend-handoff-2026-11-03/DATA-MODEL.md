# نموذج البيانات والمعاملات

مرجع تصميم migrations على Laravel/قاعدة الباك الحالية، وليس SQL للاستبدال الأعمى. راجع أنواع jobs.id والفهارس الموجودة قبل أي تعديل. توسع بنهج expand/migrate/contract مع backup قابل للاستعادة وstaging؛ لا DROP للقديم ولا reset لقاعدة الإنتاج.

| الجدول | الحقول الأساسية والقيود |
| --- | --- |
| members | id UUID/معرف نصي، normalized_email UNIQUE، name، headline، phone، country، summary (≤1000)، skills JSON (≤20×40)، languages JSON (≤10×40)، experience_years nullable (0–60)، status(active/suspended/deleted)، terms_version/accepted_at، timestamps |
| identities | member_id، provider، provider_subject/Firebase UID؛ UNIQUE(provider,subject)، verified_email، created_at؛ لا JWT خام |
| email_challenges | id عشوائي، email/member_id، purpose(login/reauth)، code_hmac، attempts، expires_at، used_at، rate-limit keys؛ تنظيف قصير |
| sessions | id/family_id/member_id، access_hash UNIQUE، access_expires_at، refresh_hash UNIQUE، refresh_expires_at، revoked_at، created_at |
| refresh_replays | old_refresh_hash، request_key UNIQUE ضمن الجلسة، encrypted_response، expires_at؛ حذف بعد مهلة الاستعادة |
| jobs إضافات | owner_user_id nullable INDEX، accepts_applications=false افتراضياً للقديم، moderation_status، reviewed_by/at، rejection_reason خاص، published_at INDEX؛ حافظ على الحقول والـIDs الموجودة |
| member_favorites | member_id/job_id UNIQUE، created_at؛ حذف الحفظ لا يحذف الوظيفة |
| saved_searches | id/member_id، name/query، normalized_filter_json/hash، watermark/published_cursor، created_at؛ UNIQUE(member_id,filter_hash) |
| search_matches | member_id/job_id UNIQUE، first_matched_at، read_at، announced_at؛ علاقة متعددة بالفلاتر اختياري لمنع فقد تطابق بعد حذف واحد |
| applications | id UUID، job_id/applicant_id UNIQUE، immutable profile_snapshot، note، status، version، created/updated_at؛ INDEX(job_id,created_at,id)، INDEX(applicant_id,updated_at,id) |
| application_events | id/application_id، old/new status، actor_id، public_note، version، created_at؛ append-only |
| conversations | id، application_id UNIQUE، job_id، employer_id، candidate_id، last_message_id/last_activity، status؛ participants من الخادم |
| conversation_reads | conversation_id/member_id UNIQUE، last_read_message_id/sequence، updated_at؛ تقدم فقط |
| messages | id/sequence، conversation_id/sender_id/client_id UNIQUE، body، created_at، moderation_state؛ INDEX(conversation_id,sequence) |
| blocks | blocker_id/blocked_id UNIQUE، created_at؛ CHECK ليست الذات؛ فحص الاتجاهين في إرسال الرسالة |
| uploads | id/member_id، purpose، object_key خاص، mime/size/width/height/hash، expires_at، complaint_id nullable، state |
| complaints | id/member_id، conversation_id اختياري، text، upload_id اختياري، status، response، assigned_admin، created/updated_at |
| notification_preferences | member_id UNIQUE وخمس booleans من OpenAPI |
| push_devices | id/session_id/member_id nullable، fcm_token مشفر أو محمي، token_hash UNIQUE، platform، last_seen_at/revoked_at؛ لا أكثر من مالك فعال للرمز |
| notifications | id/member_id/event_id UNIQUE، category/title/body، destination/entity_id، read_at/created_at؛ INDEX(member_id,created_at,id) |
| domain_outbox | event_id UNIQUE، event_type، entity_id/version، payload_minimal، created_at/attempts/available_at/processed_at؛ لا أسرار |
| idempotency | actor_scope/method/path/key UNIQUE، request_hash، state(in_progress/completed)، resource_id، response_status/encrypted_response، expires_at |
| moderation_audit | id/admin_id/action/entity_id، reason، request_id، time؛ وصول محدود، لا OTP أو توكن |
| deletion_tombstones | member_id/identities_hash، performed_at، retention exceptions، backup replay marker؛ لمنع إحياء المحذوف بالاستعادة |

## المعاملات المطلوبة

- إنشاء حساب وتحدي: قفل challenge، تحقق/استهلاك، إنشاء أو قراءة الحساب، session وidempotency response في معاملة؛ إرسال البريد عبر queue بعد commit دون تعطيل API أو تسريب الرمز في logs.
- تدوير session: اقفل family/refresh الحالي، اكتب الزوج الجديد وبصماته وreplay المشفر، وابطل القديم. لا تكتب رمزاً جديداً ثم تفشل قبل حفظ الـreplay.
- إضافة وظيفة: تحقق ملكية الجلسة والمدخلات، Job pending، idempotency resource وحدث job.submitted في معاملة.
- النشر: قفل Job pending، تحقق صلاحيتها، published_at وحالة منشورة وoutbox event واحد بمعرّف ثابت مشتق من job/version. المطابقة من published_at/sequence، لا created_at فقط.
- تقديم: قفل/تحقق صلاحية Job، UNIQUE(applicant,job)، snapshot من الملف، application event وoutbox؛ لا ترسل push قبل commit.
- تحديث حالة: expected_version مع قفل وتفويض الفاعل، انتقال مسموح، history وevent؛ تحديث متنافس409.
- محادثة: إنشاء ذري UNIQUE(application_id)، مشاركون مشتقون من الطلب والفرصة. رسالة: فحص membership والحظر وحالة الحساب، unique client_id، last_message وoutbox معاً. لا حدث ثانٍ على إعادة المحاولة.
- شكوى: اربط upload ملك المشتكي ضمن المعاملة، حالتها open، حدث دعم، ثم queue إشعار التأكيد. لا صورة قابلة لإعادة الاستخدام بحساب آخر.
- حذف الحساب: تعطيل سريع للجلسات/المحتوى والـpush فوراً، ثم job تنظيف idempotent للبيانات الثقيلة. أعد نجاح DELETE بعد إبطال الوصول؛ لا تفشل واجهة المستخدم بسبب تنظيف لاحق قابل للاستعادة.

## تشغيل ومراقبة

Queue workers مع backoff وجداول failed/dead-letter، scheduler للتنظيف/انتهاء الوظائف، Redis أو حدود مشتركة بين العمال؛ لا rate limit ذاكرة عامل واحد. اقتراح مبدئي: قراءات الحساب120/دقيقة، رسائل30/دقيقة، تقديم20/ساعة، إنشاء5/ساعة، صور10/ساعة، شكاوى5/ساعة، وحدود بريد منفصلة. عدّل على القياس مع Retry-After، ولا تعتبر NAT شخصاً واحداً دائماً.

كل تغيير يكتب domain_outbox داخل المعاملة؛ workers يرسلونه at-least-once مع dedup event_id على notifications وFCM jobs. لا يمكن ضمان exactly-once من FCM؛ العميل/الخادم يمنعان إعادة بناء الحدث وتكرار العرض قدر الإمكان. راقب زمن الرد، queue lag، نسب401/429/5xx، فشل البريد/FCM، مساحة الصور، دون محتوى محادثات في monitoring.

## ترحيل قابل للرجوع

1. استعادة backup في staging ومطابقة counts وحالات jobs والأجهزة والمحفوظات.
2. إضافة الجداول والحقول nullable/defaults دون تغيير القديم؛ backfill آمن للبلدان والمحافظات من REGIONS.md.
3. تفعيل v2 على staging فقط، ثم اختبارات كل الدورين والمشرف.
4. الإنتاج: capabilities=false حتى اكتمال إعدادات الهوية والـqueues، ثم تفعيل بعد اعتماد التسليم.
5. الرجوع يعطل v2 عبر capabilities ولا يسقط الجداول/البيانات الجديدة أو يكسر API القديم. لا تربط التراجع بحذف حسابات أنشأها مستخدمون.

## فهارس البحث والتصفية في الطلبات

أضف فهارس `(applicant_id,status,created_at,id)` و`(job_id,status,created_at,id)` بحسب خطة استعلام قاعدة الإنتاج. الطلب يحتفظ بلقطة الملف المهنية وقت التقديم؛ تعديل الملف لاحقاً لا يغير الطلبات القديمة أو يعيد ترتيب المرشحين سراً. البحث بالاسم/المهارات محصور بطلبات المالك، مع query plan وميزانية زمنية معقولة. لا public talent search بهذا الإصدار.
