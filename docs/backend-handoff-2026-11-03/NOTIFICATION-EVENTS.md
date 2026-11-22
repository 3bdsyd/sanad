# أحداث الإشعارات والروابط

السيرفر ينشئ سجل notifications دائم داخل الحساب ثم يرسل FCM حسب تفضيلات الفئة وصلاحيات النظام. لا يُعتبر طلب الإرسال وصولاً للجهاز. الويب لديه صندوق API فقط؛ Web Push غير منفذ. الرسائل لا تحتوي بيانات توظيف حساسة على شاشة القفل افتراضياً.

| الحدث بعد commit | المستلم | الفئة | مثال النص | destination / entity_id |
| --- | --- | --- | --- | --- |
| job.submitted | المعلن | job_moderation | تم استلام إعلانك وهو قيد المراجعة | own_job / job ID |
| job.approved | المعلن | job_moderation | تم نشر فرصة العمل التي أضفتها | own_job / job ID |
| job.rejected | المعلن | job_moderation | تمت مراجعة إعلانك، يرجى الاطلاع على الملاحظات | own_job / job ID |
| job.expiring، مرة قبل24 ساعة | المعلن | job_moderation | تقترب مدة إعلانك من الانتهاء | own_job / job ID |
| job.expired | المعلن | job_moderation | انتهت مدة عرض إعلانك | own_job / job ID |
| job.published.matches | صاحب البحث المحفوظ | saved_search_matches | توفرت فرص جديدة تطابق بحثك المحفوظ | matches / saved-matches |
| application.submitted | مالك الفرصة | applications | وصل طلب تقديم جديد لفرصتك | application / application ID |
| application.status_changed | المتقدم | applications | تم تحديث حالة طلبك | application / application ID |
| application.withdrawn | مالك الفرصة | applications | سحب أحد المتقدمين طلبه | application / application ID |
| conversation.started | المتقدم | messages | بدأ صاحب الفرصة محادثة بشأن طلبك | conversation / conversation ID |
| message.created | الطرف الآخر فقط | messages | لديك رسالة جديدة بشأن إحدى الفرص | conversation / conversation ID |
| complaint.created | المشتكي، وإشارة داخل لوحة الدعم | complaints | تم استلام شكواك | complaint / complaint ID |
| complaint.updated/replied | المشتكي | complaints | يوجد تحديث على شكواك | complaint / complaint ID |
| account.suspended | صاحب الحساب، بريد خدمة إن لم يمكن الدخول | service | تمت مراجعة حالة حسابك، تواصل مع الدعم | صندوق دعم/بريد، لا وجهة خاصة غير مخول بها |

لا push على: كل فتح شاشة، تحميل كاش، كل refresh، حفظ/إزالة مفضلة، فشل دخول، حظر طرف، تعليم رسالة مقروءة، إعادة إرسال عملية idempotent، أو موافقة مكررة على Job. لا ترسل اسم المشتكي أو لقطة الشكوى للمبلّغ عنه. استثناء الحساب الأمني عبر بريد خدمة مستقل، لا تحشر category غير مدعومة ضمن تفضيلات v2.

## payload ثابت وآمن

```json
{
  "event_id": "event-test-1",
  "destination": "conversation",
  "entity_id": "conversation-test-1",
  "recipient_id": "member-test-1"
}
```

كل قيم FCM data نصوص. recipient_id مطلوب في push الخاص للمنصة لمنع عرض إشعار حساب سابق بعد تسجيل الخروج أو تبديل الحساب؛ هو معرف مبهم وليس إذن وصول، ويبقى التحقق على الخادم. destination واحدة من job/own_job/application/conversation/complaint/matches. لا URLs عشوائية أو raw HTML أو phone/email/body للمحادثة أو توكن في payload. عنوان/body عامان في notification، والتفاصيل الخاصة تُجلب عبر Bearer بعد فتح التطبيق والتحقق من الحساب. الحقول job_id القديمة مقبولة لنسخ قديمة، لكن إرسال وجهة conversation لجهاز نسخة قديمة يعرضه كمركز متابعة فقط؛ لا تكسرها.

العميل يعيد المستخدم لشاشة الدخول عند الحاجة ثم يجلب الوجهة بالتفويض. مستخدم آخر على الهاتف لا يرى مورد الحساب السابق، حتى لو وصل push متأخر. GET /conversations/{id} وGET /applications/{id} وGET /me/jobs/{id} تتحقق من الملكية. عند حذف/رفض المورد تعرض وجهة قابلة للفهم أو صندوق الإشعارات، لا crash.

## منع التكرار والضجيج

- معرف حدث ثابت لكل تغيير منطقي/version، UNIQUE(member,event_id) في صندوق التنبيهات، worker يستعمل نفس event_id على retries. FCM messageId/استلام الجهاز ليس حدث أعمال جديداً.
- تطابق البحث فريد member/job حتى لو طابق3 فلاتر. لا إرسال لفرصة قبل published_at أو انتهت/سحبت. تأسيس الفلتر صامت، فلا يعتبر الموجود إعلاناً جديداً.
- جمّع فرص المطابقة لمدة2–5 دقائق في إشعار واحد مع العدد، مع بقاء السجلات الفردية والقائمة كاملة. لا push ذاتي لمالك Job عن تطابق فرصته إلا لو اختارها كبحث وكان ذلك مرغوباً؛ الافتراضي استبعاده.
- رسالة واحدة للطرف الآخر بعد نجاح الحفظ، دون إعادة على retry. collapse_key للمحادثة وthread-id على iOS للمجموعة؛ لا تعتمد عليهما لحذف سجل API أو إثبات القراءة.
- التطبيق يكتم التنبيه المحلي إذا كانت نفس المحادثة ظاهرة ويحدثها؛ الخلفية يستعرضها النظام. لا Notification local ثانٍ لنفس remote message. قراءة المحادثة تقلل unread_count على الخادم.
- سجل token_hash/session_id آخر نشاط. PUT push-device من جلسة جديدة يسحب الرمز من المالك السابق؛ logout/delete/suspend يبطل الربط. UNREGISTERED/INVALID token يحذف من الإرسال. طلب visit القديم لا يعيد ملكية حساب ملغاة.
- Retry أسي مع jitter لأخطاء FCM العابرة و429 مع حد محاولات وطابور ميت. لا تعِد إرسال rejected token أو تكشف توكنات في سجلات الفشل.

اختبار Android وiOS: foreground/background/terminated، حسابان على نفس الهاتف، دخول/خروج، إيقاف فئة واحدة، رفض إذن النظام، تدوير FCM، رسالة في المحادثة المفتوحة، حدث مكرر، وفتح job لم يعد منشوراً. الحساب المجاني لآيفون لا يثبت APNs؛ التسليم يحتاج ملف متجر يدعم push.
