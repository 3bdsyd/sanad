"""Deterministic v2 contract + fixtures. Keeps the reviewed legacy /api intact.

This creates documentation only; it never implements or deploys a backend.
"""
import base64
import struct
import zlib
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/backend-handoff-2026-11-03'


def obj(properties, required=None):
    return {'type': 'object', 'properties': properties, 'required': list(properties) if required is None else required, 'additionalProperties': False}


def string(**kwargs):
    return {'type': 'string', **kwargs}


def ref(name):
    return {'$ref': '#/components/schemas/' + name}


def array(schema):
    return {'type': 'array', 'items': schema}


def envelope(schema):
    return obj({'data': schema})


def tiny_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
    image += chunk(b'IDAT', zlib.compress(b'\x00\x20\x50\x8a\xff')) + chunk(b'IEND', b'')
    return base64.b64encode(image).decode()


def generate():
    source = DEST / 'openapi.json'
    spec = json.loads(source.read_text())
    spec['paths'] = {p: v for p, v in spec['paths'].items() if not p.startswith('/api/v2/')}
    schemas = spec['components']['schemas']
    spec['info'] = {'title': 'Sanad complete API — legacy and account hiring platform', 'version': '2026-11-03.5',
        'description': 'Desired implementation contract, not deployed backend. PLATFORM.md is normative for v2; CONTRACT.md documents backward compatible legacy /api. Client/account workflows use /api/v2; public discovery still uses existing /api. All private state belongs to authenticated user, never X-Device-ID. See SECURITY.md, NOTIFICATION-EVENTS.md and ACCEPTANCE-PLATFORM.md.'}
    spec['components']['securitySchemes']['MemberBearer'] = {'type': 'http', 'scheme': 'bearer', 'description': 'Sanad access token. NOT a Firebase token, device ID, management token or mobile API key.'}
    spec['components']['securitySchemes']['AdminBearer'] = {'type': 'http', 'scheme': 'bearer', 'description': 'Server-issued admin session with moderation permission; never shipped in the app.'}
    identifier = string(minLength=1, maxLength=128, pattern='^[a-zA-Z0-9_-]+$')
    moment = string(format='date-time')
    boolean = {'type': 'boolean'}
    number = {'type': 'integer', 'minimum': 0}
    status = string(enum=['submitted', 'under_review', 'shortlisted', 'accepted', 'rejected', 'withdrawn'])
    user = {'id': 'member-test-1', 'name': 'مستخدم الاختبار', 'email': 'candidate@example.test', 'headline': 'مطور تطبيقات', 'phone': '+963944000000', 'country': 'SY', 'providers': ['email'], 'summary': 'أعمل على تطوير تطبيقات ميسّرة وسريعة مع اهتمام بتجربة الاستخدام.', 'skills': ['Flutter', 'Dart'], 'languages': ['العربية', 'الإنجليزية'], 'experience_years': 3}
    schemas['Member'] = obj({'id': identifier, 'name': string(minLength=2, maxLength=80), 'email': string(format='email', nullable=True), 'headline': string(maxLength=160), 'phone': string(maxLength=16), 'country': string(maxLength=2), 'providers': array(string(enum=['email', 'google', 'apple'])), 'summary': string(maxLength=1000), 'skills': {**array(string(minLength=1, maxLength=40)), 'maxItems': 20, 'uniqueItems': True}, 'languages': {**array(string(minLength=1, maxLength=40)), 'maxItems': 10, 'uniqueItems': True}, 'experience_years': {'type': 'integer', 'nullable': True, 'minimum': 0, 'maximum': 60}})
    schemas['Member']['description'] = 'Own account/session has verified non-null email. Other-party/deleted member projections redact email as null, phone/headline/summary/country as empty, skills/languages/providers as [], experience_years as null unless explicitly shared by application consent. Never expose provider subjects or identity secrets.'
    schemas['PlatformSession'] = obj({'access_token': string(), 'token_type': string(enum=['Bearer']), 'access_expires_at': moment, 'refresh_token': string(), 'refresh_expires_at': moment, 'user': ref('Member')})
    schemas['PlatformError'] = obj({'error': obj({'code': string(), 'message': string(), 'fields': {'type': 'object', 'additionalProperties': array(string())}}, ['code', 'message']), 'request_id': string()}, ['error', 'request_id'])
    schemas['CursorMeta'] = obj({'next_cursor': string(nullable=True), 'unread_count': number}, ['next_cursor'])
    schemas['PlatformCapabilities'] = obj({'platform_enabled': boolean, 'email_login': boolean, 'google_login': boolean, 'apple_login': boolean, 'terms_version': string(), 'minimum_client_contract': string()})
    schemas['Job']['properties'].update({'accepts_applications': boolean, 'applications_count': number, 'rejection_reason': string(nullable=True)})
    if 'withdrawn' not in schemas['Job']['properties']['status']['enum']:
        schemas['Job']['properties']['status']['enum'].append('withdrawn')
    job_platform_description = ' accepts_applications defaults false on legacy/imported jobs. applications_count/rejection_reason only for owner/admin; complete description/contact/salary always returned to owner.'
    schemas['Job']['description'] = schemas['Job'].get('description', '').split(job_platform_description, 1)[0] + job_platform_description
    new_job = copy.deepcopy(schemas['CreateJob'])
    new_job['properties'].pop('device_id', None)
    new_job['required'] = [p for p in new_job['required'] if p != 'device_id']
    new_job['properties'].update({'contact_consent': {'type': 'boolean', 'enum': [True]}, 'accepts_applications': boolean})
    new_job['required'] += ['contact_consent', 'accepts_applications', 'country']
    new_job['required'] = sorted(set(new_job['required']))
    new_job['additionalProperties'] = False
    schemas['CreateAccountJob'] = new_job
    schemas['Application'] = obj({'id': identifier, 'job': ref('Job'), 'applicant': ref('Member'), 'status': status, 'note': string(maxLength=2000),
        'conversation_id': string(nullable=True), 'viewer_role': string(enum=['candidate', 'employer']), 'version': {'type': 'integer', 'minimum': 1}, 'created_at': moment, 'updated_at': moment,
        'history': array(obj({'status': status, 'at': moment, 'note': string(maxLength=500)}, ['status', 'at']))})
    schemas['Message'] = obj({'id': identifier, 'client_id': identifier, 'sender_id': identifier, 'text': string(minLength=1, maxLength=4000), 'created_at': moment,
        'delivery_state': string(enum=['sent', 'delivered', 'read'])})
    schemas['Conversation'] = obj({'id': identifier, 'job_id': {'type': 'integer', 'minimum': 1}, 'application_id': identifier, 'job_title': string(), 'peer': ref('Member'),
        'last_message': {**ref('Message'), 'nullable': True}, 'unread_count': number, 'can_send': boolean, 'blocked_by_me': boolean, 'updated_at': moment})
    schemas['Complaint'] = obj({'id': identifier, 'text': string(minLength=10, maxLength=4000), 'image_url': string(nullable=True), 'conversation_id': string(nullable=True),
        'status': string(enum=['open', 'in_review', 'resolved', 'closed']), 'response': string(), 'created_at': moment, 'updated_at': moment})
    schemas['NotificationPreferences'] = obj({key: boolean for key in ['saved_search_matches', 'job_moderation', 'applications', 'messages', 'complaints']})
    schemas['SavedSearch'] = obj({'id': identifier, 'name': string(minLength=1, maxLength=120), 'query': string(maxLength=200), 'filters': ref('SavedSearchFilters'), 'created_at': moment}, ['id', 'name', 'query', 'filters'])
    schemas['SavedSearchFilters'] = obj({
        'country': string(nullable=True, minLength=2, maxLength=2), 'city': string(nullable=True, maxLength=100), 'category': string(nullable=True, maxLength=100),
        'workType': string(nullable=True), 'workMode': string(nullable=True), 'experience': string(nullable=True),
        'currency': string(nullable=True, minLength=3, maxLength=3), 'salaryPeriod': string(nullable=True),
        'minSalary': {'type': 'integer', 'minimum': 0, 'nullable': True}, 'salaryOnly': boolean, 'sort': string(enum=['newest', 'salary'])}, [])
    schemas['NotificationPayload'] = obj({'event_id': identifier, 'destination': string(enum=['job', 'own_job', 'application', 'conversation', 'complaint', 'matches']), 'entity_id': identifier, 'recipient_id': identifier}, ['destination', 'entity_id'])
    schemas['PlatformNotice'] = obj({'id': identifier, 'title': string(), 'body': string(), 'is_read': boolean, 'created_at': moment, 'read_at': {**moment, 'nullable': True}, 'payload': ref('NotificationPayload')})
    examples = json.loads((DEST / 'examples/responses.json').read_text())
    job = copy.deepcopy(examples['jobsPage']['data'][0])
    job.update({'id': 970001, 'created_at': '2035-01-01T10:00:00Z', 'expires_at': '2035-01-31T10:00:00Z', 'status': 'published', 'accepts_applications': True})
    job.pop('device_id', None)
    own_job = {**job, 'status': 'pending', 'applications_count': 0, 'rejection_reason': None}
    application = {'id': 'application-test-1', 'job': job, 'applicant': user, 'status': 'submitted', 'note': 'أرغب في التقدم لهذه الفرصة.', 'conversation_id': None,
        'viewer_role': 'candidate', 'version': 1, 'created_at': '2035-01-01T11:00:00Z', 'updated_at': '2035-01-01T11:00:00Z', 'history': [{'status': 'submitted', 'at': '2035-01-01T11:00:00Z'}]}
    message = {'id': 'message-test-1', 'client_id': 'client-test-1', 'sender_id': user['id'], 'text': 'مرحباً، يسعدني مناقشة تفاصيل الفرصة.', 'created_at': '2035-01-01T12:00:00Z', 'delivery_state': 'sent'}
    conversation = {'id': 'conversation-test-1', 'job_id': job['id'], 'application_id': application['id'], 'job_title': job['title'],
        'peer': {**user, 'id': 'employer-test-1', 'name': 'صاحب فرصة الاختبار', 'email': 'employer@example.test'}, 'last_message': message, 'unread_count': 0, 'can_send': True, 'blocked_by_me': False, 'updated_at': message['created_at']}
    complaint = {'id': 'complaint-test-1', 'text': 'وصف مشكلة اختبارية لمتابعة الدعم.', 'image_url': None, 'conversation_id': None, 'status': 'open', 'response': '', 'created_at': message['created_at'], 'updated_at': message['created_at']}
    preferences = {key: True for key in schemas['NotificationPreferences']['properties']}
    session = {'access_token': 'TEST_ONLY_ACCESS_REPLACE_IN_STAGING', 'token_type': 'Bearer', 'access_expires_at': '2035-01-01T12:15:00Z', 'refresh_token': 'TEST_ONLY_REFRESH_REPLACE_IN_STAGING', 'refresh_expires_at': '2035-01-31T12:00:00Z', 'user': user}
    search = {'id': 'search-test-1', 'name': 'تقنية في ألمانيا', 'query': 'Flutter', 'filters': {'country': 'DE', 'city': 'برلين', 'sort': 'newest'}}
    notice = {'id': 'notice-test-1', 'title': 'تم تحديث طلبك', 'body': 'طلبك قيد الدراسة لدى جهة العمل.', 'is_read': False, 'read_at': None, 'created_at': message['created_at'],
        'payload': {'event_id': 'event-test-1', 'destination': 'application', 'entity_id': application['id'], 'recipient_id': user['id']}}
    fixtures = {'session': session, 'member': user, 'job': job, 'own_job': own_job, 'application': application, 'conversation': conversation, 'message': message, 'complaint': complaint, 'search': search, 'notice': notice}
    error = {'error': {'code': 'validation_failed', 'message': 'يرجى مراجعة البيانات المدخلة.', 'fields': {'name': ['الاسم مطلوب.']}}, 'request_id': 'request-test-1'}
    schemas['MessagesMeta'] = obj({'next_cursor': string(nullable=True), 'can_send': boolean}, ['next_cursor', 'can_send'])

    def endpoint(method, path, title, data_schema, data_example, body=None, body_example=None, auth=True, code=200, paged=False, admin=False):
        response_schema = envelope(data_schema)
        payload = {'data': data_example}
        if paged:
            response_schema['properties']['meta'] = ref('MessagesMeta' if path.endswith('/messages') else 'CursorMeta')
            response_schema['required'].append('meta')
            payload['meta'] = {'next_cursor': None, **({'can_send': True} if path.endswith('/messages') else {})}
        operation = {'operationId': method.lower() + ''.join(part.title().replace('{', '').replace('}', '').replace('-', '') for part in path.split('/') if part),
            'summary': title, 'tags': ['Platform moderation' if admin else 'Account platform'], 'security': [{'AdminBearer' if admin else 'MemberBearer': []}] if auth else [],
            'responses': {str(code): {'description': 'Success; server authority', 'content': {'application/json': {'schema': response_schema, 'example': payload}}}}}
        for part in path.split('/'):
            if part.startswith('{'):
                operation.setdefault('parameters', []).append({'name': part[1:-1], 'in': 'path', 'required': True, 'schema': identifier, 'example': '970001' if part == '{jobId}' else part[1:-1] + '-test-1'})
        if method != 'GET':
            operation.setdefault('parameters', []).append({'name': 'Idempotency-Key', 'in': 'header', 'required': True, 'schema': string(minLength=16, maxLength=128), 'example': 'staging-unique-operation-key-0001'})
        if paged:
            operation.setdefault('parameters', []).extend([{'name': 'cursor', 'in': 'query', 'schema': string(), 'description': 'Opaque next_cursor from the previous page. Messages: older history; all other collections: next page.'}, {'name': 'per_page', 'in': 'query', 'schema': {'type': 'integer', 'default': 50, 'minimum': 1, 'maximum': 50}}])
        if body is not None:
            operation['requestBody'] = {'required': True, 'content': {'application/json': {'schema': body, 'example': body_example or {}}}}
        for status_code in ([401, 403, 404, 409, 422, 429, 503] if auth else [400, 401, 409, 410, 422, 429, 503]):
            operation['responses'][str(status_code)] = {'description': 'See PLATFORM.md error codes; no traces or secrets.', 'content': {'application/json': {'schema': ref('PlatformError'), 'example': error}}}
            if status_code == 429:
                operation['responses']['429']['headers'] = {'Retry-After': {'schema': {'type': 'integer'}, 'description': 'Seconds before another request.'}}
        spec['paths'].setdefault('/api/v2' + path, {})[method.lower()] = operation

    ok = obj({'success': {'type': 'boolean', 'enum': [True]}})
    empty = obj({})
    endpoint('GET', '/capabilities', 'جاهزية المنصة وطرق الدخول', ref('PlatformCapabilities'), {'platform_enabled': True, 'email_login': True, 'google_login': True, 'apple_login': True, 'terms_version': '2026-11-03', 'minimum_client_contract': '2026-11-03.5'}, auth=False)
    challenge_schema = obj({'challenge_id': identifier, 'retry_after': {'type': 'integer', 'minimum': 1}, 'expires_in': {'type': 'integer', 'minimum': 1}})
    challenge = {'challenge_id': 'challenge-test-1', 'retry_after': 60, 'expires_in': 300}
    endpoint('POST', '/auth/email/challenge', 'إرسال رمز الدخول بالبريد', challenge_schema, challenge, obj({'email': string(format='email', maxLength=254), 'locale': string(enum=['ar'])}), {'email': user['email'], 'locale': 'ar'}, auth=False)
    endpoint('POST', '/auth/email/verify', 'التحقق وإنشاء الحساب أو فتحه', ref('PlatformSession'), session,
        obj({'challenge_id': identifier, 'code': string(pattern='^[0-9]{6}$'), 'name': string(minLength=2, maxLength=80), 'terms_version': string(enum=['2026-11-03'])}, ['challenge_id', 'code', 'terms_version']), {'challenge_id': challenge['challenge_id'], 'code': '123456', 'name': user['name'], 'terms_version': '2026-11-03'}, auth=False)
    endpoint('POST', '/auth/social', 'تبادل Firebase ID token الموثق بجلسة سند', ref('PlatformSession'), session,
        obj({'firebase_id_token': string(), 'provider': string(enum=['google', 'apple']), 'terms_version': string(enum=['2026-11-03'])}), {'firebase_id_token': 'TEST_ONLY_FIREBASE_ID_TOKEN', 'provider': 'google', 'terms_version': '2026-11-03'}, auth=False)
    rotated = {key: value for key, value in session.items() if key != 'user'}
    endpoint('POST', '/auth/refresh', 'تدوير رمز التجديد بذات مفتاح المحاولة', obj({key: value for key, value in schemas['PlatformSession']['properties'].items() if key != 'user'}), rotated, obj({'refresh_token': string()}), {'refresh_token': session['refresh_token']}, auth=False)
    endpoint('POST', '/auth/logout', 'إلغاء الجلسة وربط إشعارها', ok, {'success': True}, obj({'refresh_token': string()}), {'refresh_token': session['refresh_token']})
    endpoint('POST', '/auth/reauth/email/challenge', 'رمز تحقق جديد لحذف الحساب', challenge_schema, challenge, empty)
    endpoint('POST', '/auth/reauth/verify', 'إثبات حديث للهوية لا يتجاوز خمس دقائق', obj({'reauth_ticket': string(), 'expires_in': {'type': 'integer', 'enum': [300]}}), {'reauth_ticket': 'TEST_ONLY_SINGLE_USE_TICKET', 'expires_in': 300}, obj({'challenge_id': identifier, 'code': string(pattern='^[0-9]{6}$')}), {'challenge_id': challenge['challenge_id'], 'code': '123456'})
    endpoint('GET', '/me', 'الملف المهني للحساب الحالي', ref('Member'), user)
    profile = obj({key: schemas['Member']['properties'][key] for key in ['name', 'headline', 'phone', 'summary', 'skills', 'languages', 'experience_years']})
    endpoint('PATCH', '/me', 'تحديث ملف مهني دون تغيير البريد أو الملكية', ref('Member'), user, profile, {key: user[key] for key in ['name', 'headline', 'phone', 'summary', 'skills', 'languages', 'experience_years']})
    endpoint('DELETE', '/me', 'حذف الحساب وإلغاء كل الجلسات', ok, {'success': True}, obj({'reauth_ticket': string()}), {'reauth_ticket': 'TEST_ONLY_SINGLE_USE_TICKET'})
    endpoint('GET', '/me/favorite-ids', 'كل معرّفات المحفوظة لعلامة القلب بلا تكرار الطلبات', array(identifier), ['970001'])
    endpoint('GET', '/me/favorites', 'صفحات المحفوظة بما فيها فرص توقفت', array(ref('Job')), [job], paged=True)
    endpoint('PUT', '/me/favorites/{jobId}', 'حفظ الفرصة بشكل idempotent', ref('Job'), job)
    endpoint('DELETE', '/me/favorites/{jobId}', 'إزالة الفرصة بشكل idempotent', ok, {'success': True})
    endpoint('GET', '/me/jobs', 'إعلانات المالك بكامل التفاصيل', array(ref('Job')), [own_job], paged=True)
    endpoint('GET', '/me/jobs/{jobId}', 'تفاصيل إعلان المالك حتى وهو غير منشور', ref('Job'), own_job)
    create_example = copy.deepcopy(examples.get('createJobRequest', {}))
    if not create_example:
        create_example = {'title': job['title'], 'company_name': job['company_name'], 'country': 'سوريا', 'state': 'دمشق', 'job_field_id': 1, 'job_type': 'دوام كامل', 'work_type': 'عن بُعد', 'experience': 'مطلوبة', 'description': 'وصف فرصة اختبارية طويل بما يكفي للتحقق.', 'phone': '+963944000000', 'currency': 'USD', 'salary_period': 'شهري', 'listing_duration_days': 30}
    create_example.pop('device_id', None)
    create_example.update({'contact_consent': True, 'accepts_applications': True})
    endpoint('POST', '/jobs', 'إنشاء فرصة مملوكة للحساب وقيد المراجعة', ref('Job'), own_job, ref('CreateAccountJob'), create_example, code=201)
    endpoint('POST', '/jobs/{jobId}/withdraw', 'سحب إعلان ومنع التقديم الجديد', ref('Job'), {**own_job, 'status': 'withdrawn'}, empty)
    endpoint('GET', '/me/applications', 'طلبات المتقدم مع الحالة والتاريخ', array(ref('Application')), [application], paged=True)
    endpoint('POST', '/jobs/{jobId}/applications', 'التقديم مرة واحدة للفرصة', ref('Application'), application, obj({'note': string(maxLength=2000)}), {'note': application['note']}, code=201)
    endpoint('GET', '/jobs/{jobId}/applications', 'المتقدمون للمالك فقط', array(ref('Application')), [{**application, 'viewer_role': 'employer'}], paged=True)
    for collection in ['/me/applications', '/jobs/{jobId}/applications']:
        spec['paths']['/api/v2' + collection]['get']['parameters'].extend([
            {'name': 'status', 'in': 'query', 'schema': status, 'description': 'Exact status; omitted means all. Applied before cursor pagination.'},
            {'name': 'q', 'in': 'query', 'schema': string(maxLength=200), 'description': 'Trimmed Unicode search. Candidate: job title/company. Owner: applicant name/headline/skills. Always restricted to authorized records before searching.'},
            {'name': 'sort', 'in': 'query', 'schema': string(enum=['newest', 'oldest'], default='newest'), 'description': 'created_at plus id tie-breaker. Cursor bound to member, collection, q, status and sort; mismatched cursor returns 422 invalid_cursor.'},
        ])
    endpoint('GET', '/applications/{applicationId}', 'الطلب للطرف المخول فقط', ref('Application'), application)
    endpoint('PATCH', '/applications/{applicationId}', 'تحديث الحالة وفق الدور والانتقالات', ref('Application'), {**application, 'status': 'under_review', 'version': 2}, obj({'status': status, 'note': string(maxLength=500), 'expected_version': {'type': 'integer', 'minimum': 1}}, ['status', 'note', 'expected_version']), {'status': 'under_review', 'note': '', 'expected_version': 1})
    endpoint('POST', '/applications/{applicationId}/conversation', 'يفتح المالك المحادثة والمتقدم يسترجع الموجودة', ref('Conversation'), conversation, empty, code=201)
    endpoint('GET', '/conversations', 'قائمة المحادثات حسب آخر رسالة', array(ref('Conversation')), [conversation], paged=True)
    endpoint('GET', '/conversations/{conversationId}', 'الطرفان فقط بلا كشف وجود محادثة أخرى', ref('Conversation'), conversation)
    endpoint('GET', '/conversations/{conversationId}/messages', 'آخر 50 رسالة تصاعدياً وcursor للسجل الأقدم', array(ref('Message')), [message], paged=True)
    endpoint('POST', '/conversations/{conversationId}/messages', 'إرسال مع client_id ثابت يمنع التكرار', ref('Message'), message, obj({'client_id': identifier, 'text': string(minLength=1, maxLength=4000)}), {'client_id': message['client_id'], 'text': message['text']}, code=201)
    endpoint('PUT', '/conversations/{conversationId}/read', 'تحديث آخر رسالة مقروءة بشكل تزايدي', ok, {'success': True}, obj({'message_id': identifier}), {'message_id': message['id']})
    endpoint('GET', '/me/blocks', 'المستخدمون المحظورون', array(ref('Member')), [conversation['peer']], paged=True)
    endpoint('PUT', '/me/blocks/{memberId}', 'منع التواصل في الاتجاهين', ok, {'success': True})
    endpoint('DELETE', '/me/blocks/{memberId}', 'إلغاء حظر المستخدم من جهتي', ok, {'success': True})
    upload = obj({'purpose': string(enum=['complaint']), 'mime_type': string(enum=['image/jpeg', 'image/png', 'image/webp']), 'content_base64': string(maxLength=6990508)})
    endpoint('POST', '/uploads', 'صورة شكوى خاصة حتى 5MiB بعد فك Base64', obj({'id': identifier, 'expires_at': moment}), {'id': 'upload-test-1', 'expires_at': '2035-01-02T12:00:00Z'}, upload, {'purpose': 'complaint', 'mime_type': 'image/png', 'content_base64': tiny_png()}, code=201)
    endpoint('POST', '/complaints', 'شكوى بنص وصورة اختيارية', ref('Complaint'), complaint, obj({'text': string(minLength=10, maxLength=4000), 'image_id': identifier, 'conversation_id': identifier}, ['text']), {'text': complaint['text']}, code=201)
    endpoint('GET', '/me/complaints', 'الشكاوى وحالتها ورد الدعم للمبلّغ فقط', array(ref('Complaint')), [complaint], paged=True)
    endpoint('GET', '/me/notification-preferences', 'تفضيلات إشعارات الهاتف', ref('NotificationPreferences'), preferences)
    endpoint('PUT', '/me/notification-preferences', 'تحديث تفضيلات الهاتف دون إسقاط سجل التنبيهات', ref('NotificationPreferences'), preferences, ref('NotificationPreferences'), preferences)
    endpoint('PUT', '/me/push-device', 'ربط رمز FCM بالجلسة الحالية وفصله عن الحساب السابق', ok, {'success': True}, obj({'fcm_token': string(maxLength=4096), 'platform': string(enum=['ios', 'android'])}), {'fcm_token': 'TEST_ONLY_FCM_TOKEN', 'platform': 'ios'})
    endpoint('GET', '/me/saved-searches', 'البحث المحفوظ على السيرفر للحساب', array(ref('SavedSearch')), [search], paged=True)
    endpoint('POST', '/me/saved-searches', 'حفظ فلتر وبداية مطابقة صامتة دون اعتبار القديم جديداً', ref('SavedSearch'), search, obj({'name': string(minLength=1, maxLength=120), 'query': string(maxLength=200), 'filters': ref('SavedSearchFilters')}), {key: search[key] for key in ['name', 'query', 'filters']}, code=201)
    endpoint('DELETE', '/me/saved-searches/{searchId}', 'حذف البحث وإيقاف المطابقة المستقبلية', ok, {'success': True})
    match_schema = copy.deepcopy(schemas['Job'])
    match_schema['properties'].update({'is_new': boolean, 'announced': boolean})
    match_schema['required'] += ['is_new', 'announced']
    schemas['SavedSearchMatch'] = match_schema
    endpoint('GET', '/me/saved-search-matches', 'فرص المطابقة غير المقروءة وحالة رسالة العودة', array(ref('SavedSearchMatch')), [{**job, 'is_new': True, 'announced': False}], paged=True)
    job_ids = obj({'job_ids': {'type': 'array', 'items': identifier, 'minItems': 1, 'maxItems': 100}})
    endpoint('PUT', '/me/saved-search-matches/read', 'تعليم الفرص التي فتحها المستخدم كمقروءة', ok, {'success': True}, job_ids, {'job_ids': ['970001']})
    endpoint('PUT', '/me/saved-search-matches/acknowledge', 'منع تكرار رسالة العودة دون اعتبارها قراءة للتفاصيل', ok, {'success': True}, job_ids, {'job_ids': ['970001']})
    endpoint('GET', '/me/notifications', 'صندوق إشعارات السيرفر مع وجهة كل حدث', array(ref('PlatformNotice')), [notice], paged=True)
    endpoint('PUT', '/me/notifications/{noticeId}/read', 'تحديد إشعار مملوك كمقروء', ok, {'success': True})
    endpoint('POST', '/me/identities', 'ربط Google أو Apple من حساب قائم ببريد مطابق ومثبت', ref('Member'), {**user, 'providers': ['email', 'google']}, obj({'provider': string(enum=['google', 'apple']), 'firebase_id_token': string()}), {'provider': 'google', 'firebase_id_token': 'TEST_ONLY_FIREBASE_ID_TOKEN'})
    endpoint('GET', '/admin/jobs', 'طابور مراجعة الفرص مع بيانات الملكية الخاصة للمشرف', array(ref('Job')), [own_job], paged=True, admin=True)
    endpoint('POST', '/admin/jobs/{jobId}/approve', 'اعتماد الفرصة وإطلاق حدث النشر والمطابقة مرة واحدة', ref('Job'), {**own_job, 'status': 'published'}, empty, admin=True)
    endpoint('POST', '/admin/jobs/{jobId}/reject', 'رفض مع سبب خاص للمالك فقط', ref('Job'), {**own_job, 'status': 'rejected', 'rejection_reason': 'يرجى توضيح مهام الوظيفة.'}, obj({'reason': string(minLength=5, maxLength=500)}), {'reason': 'يرجى توضيح مهام الوظيفة.'}, admin=True)
    endpoint('GET', '/admin/complaints', 'الشكاوى الخاصة للمشرف المخول', array(ref('Complaint')), [complaint], paged=True, admin=True)
    endpoint('PATCH', '/admin/complaints/{complaintId}', 'متابعة الشكوى وإرسال الرد', ref('Complaint'), {**complaint, 'status': 'resolved', 'response': 'تمت مراجعة المشكلة.'}, obj({'status': schemas['Complaint']['properties']['status'], 'response': string(maxLength=4000)}), {'status': 'resolved', 'response': 'تمت مراجعة المشكلة.'}, admin=True)
    endpoint('POST', '/admin/members/{memberId}/suspend', 'تعليق الحساب وسحب محتواه وإبطال جلساته بعد المراجعة', ok, {'success': True}, obj({'reason': string(minLength=5, maxLength=500)}), {'reason': 'مخالفة شروط النشر.'}, admin=True)
    # Retries of committed operations return the same resource with 200/201.
    for path in ['/jobs/{jobId}/applications', '/applications/{applicationId}/conversation']:
        operation = spec['paths']['/api/v2' + path]['post']
        operation['responses']['200'] = copy.deepcopy(operation['responses']['201'])
        operation['responses']['200']['description'] = 'Existing resource, same unique user/job or application/conversation.'
    for path in ['/uploads', '/complaints']:
        for code in [413, 415]:
            spec['paths']['/api/v2' + path]['post']['responses'][str(code)] = {'description': 'Image/body limit or unsupported format', 'content': {'application/json': {'schema': ref('PlatformError'), 'example': error}}}
    total = sum(len(methods) for methods in spec['paths'].values())
    spec['x-platform-client-operations'] = [{'method': method.upper(), 'path': path} for path, methods in spec['paths'].items() if path.startswith('/api/v2/') and '/admin/' not in path for method in methods]
    spec['x-inventory'] = {'operations': total, 'paths': len(spec['paths']), 'legacy_operations': 16, 'platform_operations': total - 16}
    source.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + '\n')
    (DEST / 'examples/platform.json').write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + '\n')
    print(f'Generated {total - 16} platform + 16 legacy operations ({len(spec["paths"])} paths).')


if __name__ == '__main__':
    generate()
