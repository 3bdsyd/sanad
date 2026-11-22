"""Create the standalone agent handoff and the Arabic product-flow PDF. No builds/network."""
import base64
import hashlib
import io
import json
import re
import textwrap
from pathlib import Path
from zipfile import ZipFile

import arabic_reshaper
from bidi.algorithm import get_display
from reportlab.lib.colors import HexColor, Color, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/backend-handoff-2026-11-03'
ARCHIVE = ROOT / 'docs/snad-backend-handoff-20261104.zip'
MD = ROOT / 'docs/SNAD-BACKEND-AGENT.md'
PDF = ROOT / 'output/pdf/SNAD-APP-FLOWS.pdf'


def markdown():
    payload = ARCHIVE.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    with ZipFile(io.BytesIO(payload)) as archive:
        assert archive.testzip() is None
        for path in SOURCE.rglob('*'):
            if path.is_file():
                assert archive.read('snad-backend-handoff-20261103/' + str(path.relative_to(SOURCE))) == path.read_bytes(), path
        spec = json.loads(archive.read('snad-backend-handoff-20261103/openapi.json'))
        count = sum(len(v) for v in spec['paths'].values())
        assert count == 70
    sections = [f'''# سند | ملف التنفيذ الكامل لأيجنت الباك إند

تاريخ التجميع: 4 نوفمبر 2026. العقد: {spec['info']['version']}.

هذا **ملف واحد مستقل**: التعليمات والفلوات والمواصفات مكتوبة هنا، وفي نهايته نسخة كاملة قابلة للاستخراج من جميع ملفات العقد والأمثلة وOpenAPI وPostman والكتالوج ومراجع Laravel. لا تحتاج ZIP منفصلاً أو مجلد سند عند تسليمه إلى أيجنت الباك.

## 0. المهمة التي تنفذها

أنت أيجنت يعمل داخل مستودع باك سند القائم. افحص قواعده وبنيته ثم نفذ هذا العقد بدقة في الباك القائم. لا تعِد إنشاء المشروع ولا تستبدل قاعدة الإنتاج بخادم Python المرجعي. الواجهة مجهزة محلياً؛ هذا لا يعني أن المنصة الجديدة منشورة أو أن الخدمات الخارجية معدّة.

1. ابدأ بقراءة هذا التمهيد ثم استخرج المرفقات بالبرنامج أدناه، واقرأ PLATFORM وSECURITY وDATA-MODEL وOpenAPI. لا تدخل كتلة Base64 الضخمة كاملة في سياق النموذج؛ استخرجها بأداة الملفات ثم اقرأ الملفات المطلوبة تدريجياً.
2. طبّق 70 عملية: 16 قديمة متوافقة و54 للمنصة، منها 6 للإدارة. لا تستبدل مسارات `/api` القديمة بـ`/api/v2`؛ لكل منها دوره المحدد في العقد.
3. نفذ migrations إضافية آمنة، المصادقة، التفويض، مراجعة النشر، الطلبات، المحادثات، الشكاوى، البحث المحفوظ والإشعارات، بالأنواع والمفاتيح وأكواد HTTP المحددة تماماً.
4. اختبر التدفقات والصلاحيات والتزامن وقطع الاتصال والـidempotency. لا تعد استجابة UI ناجحة دليلاً على عمل البريد أو Google/Apple أو FCM.
5. جهز staging وتقرير التنفيذ والقيم العامة المطلوبة. لا تنشر إنتاجاً ولا ترسل للمتاجر أو تبنِ Android/iOS من هذه المهمة. لا تغيّر تطبيق Flutter لتغطية اختلاف عقد غير معلن.

## 1. أولوية المراجع والنطاق

- PLATFORM وSECURITY وDATA-MODEL وNOTIFICATION-EVENTS تحدد سلوك الأعمال والأمان، وOpenAPI يحدد الطرق والمسارات والأسماء والأنواع والحدود والأمثلة. يجب تحقيقهما معاً. عند تعارض فعلي لا تختر تخميناً: وثق التعارض المحدد قبل تغيير العقد.
- CONTRACT وREGIONS وACCEPTANCE تخص توافق API القديم والبلدان. الإشارات التاريخية إلى غياب الحساب والشات تخص القديم فقط؛ المطلوب الجديد مكتوب في PLATFORM.
- ملفات Laravel المرجعية رقعة دول ومراجع حقول قديمة، وليست باك v2 كاملاً ولا أمراً باستبدال controllers الخاصة بالمشروع دون مراجعة.
- BAYT-REFERENCE يميز ميزات هذا الإصدار عن توسع مستقبلي. أفكار الشركة الموثقة والمقابلات والتوصيات ليست جزءاً مطلوباً من هذا العقد.
- أمثلة الرموز والمعرفات اختبارية، ليست مفاتيح دخول فعلية. لا تضف secrets إلى Flutter أو ملفات التسليم.
- التصفح العام بلا حساب. الحساب الواحد يتقدم وينشر. الدخول مطلوب للمحفوظات والنشر والتقديم والشات والبحث المحفوظ والشكاوى.
- لا CV ولا اختيار دور عند التسجيل ولا محادثات عشوائية. المعلن يبدأ المحادثة من طلب حقيقي؛ المتقدم يسترجع الموجودة.
- حساب الإعلان القديم لا يثبت عبر device_id المكشوف. لا ترحيل ملكية أو بيانات جهاز إلى عضو بلا إثبات وموافقة وفق SECURITY.

## 2. ترتيب التنفيذ والتسليم

| المرحلة | العمل | شرط الإغلاق |
| --- | --- | --- |
| اكتشاف | افحص routes/schema/auth/jobs/queues والإصدارات والتوافق القديم | خطة تغييرات ونسخة احتياطية قابلة للاستعادة على staging |
| أساس | migrations وفهارس وملكية وidempotency وoutbox وأخطاء موحدة | لا تسريب بيانات، ولا تغيير كاسر للقديم |
| دخول | capabilities وOTP وFirebase Admin والجلسات والتجديد والحذف | اختبارات رمز/مزود/replay/logout/حسابين |
| بيانات | ملف وحفظ وبحث محفوظ وبلدان ونشر ومراجعة | بيانات كاملة للمالك، وعدم ظهور pending للعامة |
| توظيف | تقديم وsnapshot وحالات ومتقدمون وبحث وقوائم | uniqueness وصلاحيات وexpected_version وتاريخ ثابت |
| تواصل ودعم | محادثة ورسائل وقراءة وحظر وصورة شكوى خاصة | منع التكرار والتسريب وقيود الصورة والتنظيف |
| إشعارات وتشغيل | أحداث بعد commit وFCM وتفضيلات وجدولة وتنظيف | dedup وlogout/token rotation وworkers قابلة للمراقبة |
| قبول | جميع ACCEPTANCE وACCEPTANCE-PLATFORM وتقرير حقيقي | staging وقيم عامة ونتائج ودليل دون أسرار |

لا تعتبر أي مرحلة مكتملة بمجرد إنشاء routes أو إرجاع fixtures. اشتراطات OAuth/Apple/APNs/SMTP التي تحتاج إعداد حساب خارجي تُسجل بوضوح، وتكون capabilities=false لها حتى تعمل فعلياً.

## 3. طريقة استخراج المرفقات من هذا الملف وحده

احفظ هذا الملف باسم `SNAD-BACKEND-AGENT.md` في مستودع الباك. شغّل الكود التالي باستخدام Python 3 من جذر مستودع الباك. ينشئ مجلد مرجع مستقل ولا يكتب فوق كود التطبيق ولا ينفذ رقعة Laravel تلقائياً. لا حاجة إلى تنزيل حزم Python.

```python
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import base64, hashlib, io

source = Path('SNAD-BACKEND-AGENT.md')
text = source.read_text(encoding='utf-8')
start = '<!-- SNAD_' + 'PAYLOAD_BASE64_BEGIN -->'
end = '<!-- SNAD_' + 'PAYLOAD_BASE64_END -->'
blob = text.split(start, 1)[1].split(end, 1)[0]
blob = blob.replace('```base64', '').replace('```', '')
raw = base64.b64decode(''.join(blob.split()), validate=True)
assert hashlib.sha256(raw).hexdigest() == '{digest}', 'Payload SHA256 mismatch'
target = Path('snad-backend-reference-20261104')
target.mkdir(exist_ok=False)  # لا تستبدل مجلداً قائماً
with ZipFile(io.BytesIO(raw)) as archive:
    assert archive.testzip() is None
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        assert not path.is_absolute() and '..' not in path.parts
        assert not entry.is_dir()
    archive.extractall(target)
root = target / 'snad-backend-handoff-20261103'
for line in (root / 'FILES.sha256').read_text().splitlines():
    expected, relative = line.split('  ', 1)
    path = PurePosixPath(relative)
    assert not path.is_absolute() and '..' not in path.parts
    assert hashlib.sha256((root / relative).read_bytes()).hexdigest() == expected, relative
print('Verified reference:', root.resolve())
```

المرفق يحوي 45 ملفاً مع فهرس SHA256، يشمل JSON الكامل بكل schemas والأمثلة وجميع المراجع. المسارات النسبية وأسماء الملفات داخل النصوص التالية تشير إلى هذا المرجع المستخرج. لا تتطلب مستودع Flutter أو إرسال ملفات أخرى.

## 4. فهرس جميع العمليات

''']
    sections.append('| # | الطريقة والمسار | العملية | الحماية |\n| --- | --- | --- | --- |\n')
    operations = []
    for path, methods in spec['paths'].items():
        for method, op in methods.items():
            security = ', '.join(sorted({k for x in op.get('security', []) for k in x})) or 'عام'
            operations.append((path, method, op))
            sections.append(f'| {len(operations)} | `{method.upper()} {path}` | {op["summary"]} | {security} |\n')
    sections.append('\n## 5. المواصفات والفلوات وقواعد التشغيل كاملة\n\n')
    order = ['README.md', 'FLOWS.md', 'PLATFORM.md', 'SECURITY.md', 'DATA-MODEL.md',
             'NOTIFICATION-EVENTS.md', 'REGIONS.md', 'CONTRACT.md', 'CONFIGURATION.md',
             'CLIENT-EXPERIENCE.md', 'CLIENT-READINESS.md', 'ACCEPTANCE-PLATFORM.md',
             'ACCEPTANCE.md', 'DELIVERY-REPORT.md', 'BAYT-REFERENCE.md',
             'REFERENCE-NOTES.md', 'NEXT-CHANGE-TEMPLATE.md', 'VERIFICATION.md']
    for index, name in enumerate(order, 1):
        sections.append(f'\n---\n\n### 5.{index} | {name}\n\n')
        content = (SOURCE / name).read_text()
        sections.append(re.sub(r'^(#{1,6}) ', lambda m: '#' * min(len(m[1]) + 3, 6) + ' ', content, flags=re.M))
    sections.append('\n---\n\n## 6. أمثلة الطلبات والردود لكل عملية\n\nالأمثلة أدناه للقراءة وليست كل حدود الحقول. المرجع الآلي الكامل `openapi.json` داخل المرفق، بما فيه schemas وrequired وenums وأمثلة الأخطاء. بعض العمليات لها أكثر من مثال؛ استعمل الملف الكامل لفحوص القبول. body لا يتضمن أسراراً فعلية.\n')
    for index, (path, method, op) in enumerate(operations, 1):
        sections.append(f'\n### 6.{index} | {method.upper()} {path}\n\n{op["summary"]}\n\n')
        if op.get('description'):
            sections.append(op['description'] + '\n\n')
        params = op.get('parameters', [])
        if params:
            sections.append('معاملات المسار والاستعلام والترويسات:\n\n```json\n' + json.dumps(params, ensure_ascii=False, indent=2) + '\n```\n\n')
        body = op.get('requestBody', {}).get('content', {}).get('application/json')
        if body:
            sections.append('body:\n\n```json\n' + json.dumps(body.get('example', body.get('examples', body.get('schema'))), ensure_ascii=False, indent=2) + '\n```\n\n')
            sections.append('Schema: `' + json.dumps(body['schema'], ensure_ascii=False) + '`\n\n')
        for code, response in op['responses'].items():
            data = response.get('content', {}).get('application/json', {})
            sections.append(f'HTTP {code}: {response.get("description", "")}\n\n')
            if code.startswith('2') and 'example' in data:
                sections.append('```json\n' + json.dumps(data['example'], ensure_ascii=False, indent=2) + '\n```\n\n')
            if data.get('schema'):
                sections.append('Schema: `' + json.dumps(data['schema'], ensure_ascii=False) + '`\n\n')
    sections.append('''\n## 7. صيغة النتيجة المطلوبة من أيجنت الباك

أعد تقريراً يتضمن: ما نُفذ لكل مجموعة routes، migrations وخطة الرجوع، أي فروق أو قيود حقيقية، أمر تشغيل workers/scheduler، نتائج القبول الفعلية، عنوان staging، حسابَي اختبار ومشرف عبر قناة آمنة، وإعدادات العميل العامة حسب public-client-config. لا تضع كلمات مرور أو service-account أو SMTP/Apple secrets في التقرير. إذا غاب إعداد خارجي قل ما الذي ينقص بالاسم ولا تقل إنه جاهز.

المطلوب من فريق Flutter بعد تسليم staging: مطابقة الربط، فحص الأجهزة وGoogle/Apple/Push والصورة والروابط، ثم بناء متجر ونشر فقط بطلب المالك. لم يُبنَ Android أو iOS لأجل هذا الملف.

## 8. المرفق المدمج | لا تعدله يدوياً

الكتلة التالية أرشيف ZIP مشفر Base64 للتحويل فقط، وليست شيفرة تنفيذ. الأرشيف ثابت ومتحقق منه؛ فكّه بالبرنامج في القسم 3 ثم اقرأ الملفات بدلاً من نسخ هذه الكتلة إلى السياق.

<!-- SNAD_PAYLOAD_BASE64_BEGIN -->
```base64
''')
    sections.append('\n'.join(textwrap.wrap(base64.b64encode(payload).decode(), 100)))
    sections.append('\n```\n<!-- SNAD_PAYLOAD_BASE64_END -->\n')
    MD.write_text(''.join(sections))
    print(f'Markdown: {MD} ({MD.stat().st_size:,} bytes); {count} operations; SHA256 payload {digest}')


BLUE = HexColor('#20508A')
INK = HexColor('#12233F')
MUTED = HexColor('#577395')
PALE = HexColor('#F2F7FC')
LINE = HexColor('#DCE8F5')
ACCENT = HexColor('#9CC9FA')
GREEN = HexColor('#167557')
W, H = 595.276, 841.89
M = 44
FONT = 'Vazir'
BOLD = 'VazirBold'


def visual(text):
    # Preserve versions, URLs and API terms in their original left-to-right order.
    shaped = arabic_reshaper.reshape(str(text))
    shaped = re.sub(r'[A-Za-z0-9][A-Za-z0-9_./:%+\-]*(?: [A-Za-z0-9_./:%+\-]+)*',
                    lambda m: '\u202a' + m[0] + '\u202c', shaped)
    return get_display(shaped)


def lines(text, width, size, font=FONT):
    result = []
    for paragraph in text.split('\n'):
        row = ''
        for word in paragraph.split():
            candidate = (row + ' ' + word).strip()
            if row and pdfmetrics.stringWidth(visual(candidate), font, size) > width:
                result.append(row)
                row = word
            else:
                row = candidate
        result.append(row)
    return result


class FlowPDF:
    def __init__(self):
        PDF.parent.mkdir(parents=True, exist_ok=True)
        pdfmetrics.registerFont(TTFont(FONT, str(ROOT / 'assets/fonts/Vazirmatn-Regular.ttf')))
        pdfmetrics.registerFont(TTFont(BOLD, str(ROOT / 'assets/fonts/Vazirmatn-Bold.ttf')))
        self.c = canvas.Canvas(str(PDF), pagesize=(W, H), pageCompression=1)
        self.c.setTitle('سند | دليل رحلات التطبيق ومنصة التوظيف')
        self.c.setAuthor('سند - Snad')
        self.page = 0
        self.records = []

    def text(self, text, x, y, size=12, color=INK, bold=False, align='right'):
        self.c.setFillColor(color)
        self.c.setFont(BOLD if bold else FONT, size)
        getattr(self.c, {'right': 'drawRightString', 'left': 'drawString', 'center': 'drawCentredString'}[align])(x, y, visual(text))
        self.records.append((self.page, text))

    def paragraph(self, text, top, width=W-2*M, x=W-M, size=11.5, color=MUTED, leading=20):
        rows = lines(text, width, size)
        for row in rows:
            self.text(row, x, top, size, color)
            top -= leading
        return top

    def start(self, title, subtitle, label='رحلات التطبيق'):
        if self.page:
            self.c.showPage()
        self.page += 1
        self.c.bookmarkPage(f'page-{self.page}')
        self.c.addOutlineEntry(title, f'page-{self.page}', level=0, closed=False)
        self.c.setFillColor(PALE)
        self.c.rect(0, 0, W, H, fill=1, stroke=0)
        self.c.setFillColor(BLUE)
        self.c.rect(0, H-8, W, 8, fill=1, stroke=0)
        self.text('سند', W-M, H-45, 16, BLUE, True)
        self.text(label, M, H-43, 9.5, MUTED, align='left')
        self.text(title, W-M, H-95, 23, INK, True)
        self.paragraph(subtitle, H-124, size=10.5, leading=18)
        self.c.setStrokeColor(LINE)
        self.c.line(M, 43, W-M, 43)
        self.text('4 نوفمبر 2026 | العقد 2026-11-03.5', W-M, 27, 8, MUTED)
        self.text(f'{self.page:02}', M, 27, 9, BLUE, True, 'left')

    def card(self, top, title, body, number=None, color=BLUE):
        body_rows = lines(body, W-2*M-40, 11.4)
        height = 51 + 19 * len(body_rows)
        bottom = top-height
        if bottom < 62:
            raise ValueError(f'Page {self.page}: card overflow {title}: {bottom}')
        self.c.setFillColor(white)
        self.c.setStrokeColor(LINE)
        self.c.roundRect(M, bottom, W-2*M, height, 15, stroke=1, fill=1)
        title_x = W-M-18
        if number is not None:
            self.c.setFillColor(color)
            self.c.circle(W-M-29, top-26, 12, fill=1, stroke=0)
            self.text(str(number), W-M-29, top-30, 10, white, True, 'center')
            title_x -= 33
        self.text(title, title_x, top-30, 13.5, color, True)
        self.paragraph(body, top-54, W-2*M-40, W-M-20, size=11.4, color=INK, leading=19)
        return bottom-13

    def note(self, top, text):
        rows = lines(text, W-2*M-28, 10.3)
        height = 21 + 17*len(rows)
        assert top-height > 60, (self.page, text)
        self.c.setFillColor(HexColor('#E7F0FA'))
        self.c.roundRect(M, top-height, W-2*M, height, 12, fill=1, stroke=0)
        self.paragraph(text, top-22, W-2*M-28, W-M-14, size=10.3, color=BLUE, leading=17)
        return top-height-13

    def flow(self, top, stages):
        # Vector sequence, ordered right to left. Not a product screenshot.
        gap = 20
        width = (W-2*M-gap*(len(stages)-1))/len(stages)
        for i, (title, detail) in enumerate(stages):
            x = W-M-(i+1)*width-i*gap
            self.c.setFillColor(BLUE if i == 0 else white)
            self.c.setStrokeColor(LINE)
            self.c.roundRect(x, top-85, width, 85, 12, fill=1, stroke=1)
            self.text(title, x+width/2, top-29, 12, white if i == 0 else BLUE, True, 'center')
            for j, row in enumerate(lines(detail, width-16, 9.4)):
                self.text(row, x+width/2, top-48-15*j, 9.4, white if i == 0 else MUTED, align='center')
            if i < len(stages)-1:
                self.c.setStrokeColor(BLUE)
                y = top-42
                self.c.line(x-3, y, x-gap+3, y)
                self.c.line(x-gap+3, y, x-gap+8, y+4)
                self.c.line(x-gap+3, y, x-gap+8, y-4)
        return top-105

    def end(self):
        self.c.save()
        print(f'PDF: {PDF} ({self.page} pages)')


def pdf():
    d = FlowPDF()
    d.start('منصة توظيف تبدأ بخطوة واضحة', 'دليل المنتج والفلوات لفريق الباك والتطبيق', 'دليل رحلات سند')
    d.c.drawImage(str(ROOT/'assets/images/sanad-logo.png'), M, 606, 74, 74, mask='auto', preserveAspectRatio=True)
    d.text('من تصفح الفرصة إلى متابعة الطلب', W-M, 653, 18, BLUE, True)
    d.paragraph('حساب بسيط، نشر تحت المراجعة، تقديم منظم، ومحادثة مرتبطة بفرصة حقيقية.', 624, 390, W-M, size=13, leading=23)
    y = d.flow(557, [('اكتشف', 'ابحث واختر البلد'), ('قدّم', 'شارك ملفك بموافقة'), ('تابع', 'حالة الطلب والمحادثة')])
    y = d.card(y, 'ما الذي يشرحه هذا الدليل؟', 'رحلة الزائر والمتقدم والمعلن والمشرف، شاشات الحساب والطلبات والدعم، وقواعد البيانات والإشعارات التي تحقق التجربة.')
    y = d.card(y, 'حالة الإصدار', 'الواجهات والربط محضرة محلياً. تنفيذ الباك الجديد وإعداد البريد والدخول الاجتماعي والإشعارات واختبار التكامل ما زالت مطلوبة.')
    d.note(y, 'هذا دليل سلوك وفلو، وليس صوراً فعلية للشاشات. المرجع التنفيذي الدقيق: ملف Markdown الموحّد. لا بناء Android أو iOS ولا نشر ضمن هذا التسليم.')

    d.start('خريطة التطبيق والصلاحيات', 'ثلاث وجهات رئيسية، وحساب واحد يستطيع التقديم والنشر.')
    y = d.flow(660, [('الفرص', 'بحث وتفاصيل ومشاركة'), ('المحفوظة', 'فرص محفوظة بحساب'), ('إعلاناتك', 'نشر وإدارة ومتابعة')])
    for title, body in [
        ('الزائر', 'يختار البلد ويتصفح ويبحث ويفتح التفاصيل ويتواصل خارجياً مع إعلان متاح. لا يُطلب الدخول لمجرد قراءة الفرص.'),
        ('المستخدم المسجل', 'يحفظ الفرص والبحث، يضيف فرصة، يتقدم، يتابع طلباته، ويراجع الحساب والمحادثات والشكاوى والإشعارات.'),
        ('صاحب الفرصة', 'يرى تفاصيل إعلانه وحالته، ثم طلبات المتقدمين وملفاتهم المسموح بها. يحدّث الحالة ويبدأ محادثة من الطلب.'),
        ('المشرف والدعم', 'يراجع الإعلان وينشره أو يرفضه، ويتابع الشكاوى وتعليق الحساب ضمن صلاحيات منفصلة وسجل تدقيق.')]:
        y = d.card(y, title, body)

    d.start('أول دخول واستئناف الإجراء', 'التصفح متاح فوراً؛ الدخول يظهر عند الحاجة إلى إجراء مرتبط بالحساب.')
    y = 660
    for n, title, body in [
        (1, 'الترحيب واختيار البلد', 'تظهر شاشة الترحيب في البداية، مع «ابدأ الاستخدام» و«تسجيل الدخول أو إنشاء حساب». يختار المستخدم بلد البحث ويمكنه تغييره لاحقاً.'),
        (2, 'الرئيسية والبحث', 'يعرض التطبيق الفرص حسب البحث والمكان. يبقى شريط الشعار والأزرار ثابتاً، ويختفي البحث عند النزول ويعود عند الصعود ويثبت أثناء الكتابة.'),
        (3, 'إجراء يحتاج حساباً', 'إذا ضغط حفظ أو إضافة أو تقديم أو إجراء محمي آخر، تُفتح صفحة دخول واحدة مع الاحتفاظ بالإجراء والوجهة المطلوبة.'),
        (4, 'بعد نجاح الدخول', 'يرجع المستخدم إلى نفس الرحلة ويستأنف الإجراء. لا يرجع إلى بداية التطبيق ولا يضطر لإعادة إدخال ما كتبه بلا داعٍ.')]:
        y = d.card(y, title, body, n)
    d.note(y, 'رفض الدخول أو عدم توفر مزود لا يمنع التصفح. capabilities من الباك تحدد طرق الدخول المتاحة فعلياً.')

    d.start('دخول بسيط وحساب آمن', 'لا كلمة مرور ولا اختيار دور بين باحث عن عمل ومعلن.')
    y = d.flow(660, [('البريد', 'إرسال رمز تحقق'), ('التحقق', 'رمز من ست خانات'), ('الحساب', 'جلسة سند واستئناف')])
    for title, body in [
        ('بريد ورمز', 'يرسل الخادم الرمز إلى البريد دون كشف وجود حساب. الصلاحية خمس دقائق وخمس محاولات، وإعادة الإرسال بعد دقيقة. للحساب الجديد يطلب الاسم بعد إثبات الرمز.'),
        ('الدخول بحساب غوغل أو آبل', 'ينفّذ SDK الدخول ثم يرسل Firebase ID token لباك سند. يتحقق Firebase Admin من الهوية والمشروع والمزود، ثم يصدر الخادم جلسة سند.'),
        ('جلسة مستقلة لكل جهاز', 'رمز وصول قصير لمدة 15 دقيقة ورمز تجديد لمدة 30 يوماً مع تدوير آمن. الخروج يبطل جلسة الجهاز وربط إشعاراتها فوراً.'),
        ('ربط وحذف', 'ربط مزود بحساب قائم يحتاج إثباتاً صحيحاً ولا يدمج حسابات تلقائياً. حذف الحساب يحتاج تحققاً حديثاً ويلغي الوصول والبيانات الخاصة وفق السياسة.')]:
        y = d.card(y, title, body)

    d.start('البحث والبلدان والفرص الجديدة', 'نتائج خادمية واضحة، والموجود سابقاً لا يتحول إلى إشعار «جديد».')
    y = 660
    for title, body in [
        ('المكان المناسب', 'اختيار بلد ثم محافظة أو ولاية من الكتالوج، مع الأعلام وبحث بالأسماء. لا حقل منطقة حر. بلد الوظيفة مستقل عن بلد رقم التواصل.'),
        ('تصفية دقيقة', 'البحث والمجال والدوام والخبرة والراتب تدعم النتائج عبر الخادم. مقارنة الراتب تكون ضمن العملة والفترة نفسها، والعملة المقترحة حسب بلد الوظيفة.'),
        ('حفظ البحث', 'المستخدم المسجل يحفظ الفلتر بحسابه. يبدأ الخادم بخط أساس صامت حتى لا يعتبر فرصاً قديمة نتائج جديدة.'),
        ('العودة للتطبيق', 'عند وجود فرص جديدة مطابقة فقط تظهر رسالة بعددها وزر «عرض الفرص». تأكيد الرسالة يوقف تكرارها، وقراءة تفاصيل فرصة إجراء مستقل.'),
        ('لا نتائج أو لا إنترنت', 'القائمة الفارغة حالة عادية مع إجراء لتعديل البحث. المحتوى المحفوظ يُقرأ عند الانقطاع مع توضيح قدمه؛ لا ندّعي أن طلباً جديداً نُفّذ.')]:
        y = d.card(y, title, body)

    d.start('إضافة فرصة ومراجعتها', 'المالك يرى إعلاناً كاملاً، والعامة ترى المنشور الساري فقط.')
    y = d.flow(660, [('النموذج', 'تفاصيل ثم تواصل'), ('مراجعة', 'حالة pending'), ('قرار', 'نشر أو رفض بسبب')])
    for title, body in [
        ('خطوتان واضحتان', 'المسمى والوصف والمتطلبات والمجال والمكان والراتب، ثم التواصل والمدة والموافقة. تتخفى خطوات النموذج عند النزول وتعود بسلاسة عند الصعود.'),
        ('الإرسال', 'الدخول مطلوب. الخادم يستنتج المالك من الجلسة، ويبدأ الإعلان قيد المراجعة دائماً. تاريخ النشر والصلاحية من الخادم، والمدة 7 أو 14 أو 30 يوماً.'),
        ('إعلاناتك', 'حالة فارغة تشرح إضافة أول فرصة، ثم بطاقات بتفاصيل مفهومة وحالة وتاريخ. للمالك الوصف والمكان والراتب والتواصل وسبب الرفض، بلا بطاقات ناقصة.'),
        ('قرار المشرف', 'الموافقة تنشر وتطلق أحداث المطابقة مرة واحدة. الرفض يعرض سبباً خاصاً للمالك. السحب أو الانتهاء يوقف الظهور والتقديم الجديد ويحفظ السجلات المخولة.')]:
        y = d.card(y, title, body)

    d.start('التقديم من جهة المتقدم', 'المستخدم يعرف ما أرسله، ومتى أرسله، وأين وصل طلبه.')
    y = 660
    for n, title, body in [
        (1, 'افتح فرصة متاحة', 'تعرض التفاصيل عنواناً متمركزاً ووصفاً كاملاً. يتاح التقديم عندما تكون الفرصة منشورة وسارية وتقبل الطلبات، ولا تكون ملك المستخدم نفسه.'),
        (2, 'راجع الملف ووافق', 'يظهر الملف الذي سيُشارك مع المعلن ورسالة تقديم اختيارية. لا رفع CV. لا مشاركة للملف دون موافقة المستخدم.'),
        (3, 'أرسل مرة واحدة', 'الخادم يحفظ طلباً واحداً لكل مستخدم وفرصة، ويلتقط نسخة ثابتة من الملف عند التقديم. إعادة المحاولة لا تنشئ طلباً جديداً.'),
        (4, 'تابع من «طلباتي»', 'تاريخ وحالة وسجل تحديثات، وبحث وتصفية وترتيب من الخادم. يمكن سحب الطلب النشط، وفتح المحادثة بعد أن يبدأها المعلن.')]:
        y = d.card(y, title, body, n)
    d.note(y, 'الفرص القديمة غير المرتبطة بمالك حساب تبقى للتواصل الخارجي ولا تقبل التقديم الداخلي حتى إثبات الملكية.')

    d.start('حالات الطلب وإجراءات المعلن', 'تغيير الحالة قرار صريح، وليس أثراً لفتح ملف أو قراءة رسالة.')
    y = d.flow(660, [('تم الإرسال', 'submitted'), ('قيد المراجعة', 'under_review'), ('مرشح', 'shortlisted')])
    for title, body in [
        ('المراجعة من داخل الفرصة', 'يرى المالك المتقدمين لفرصته فقط، ويبحث بالاسم أو المسمى أو مهارات لقطة الملف. لا يوجد بحث عام في حسابات المستخدمين.'),
        ('الانتقالات المسموحة', 'من «تم الإرسال»: مراجعة أو ترشيح أو قبول أو رفض. من «قيد المراجعة»: ترشيح أو قبول أو رفض. من «مرشح»: قبول أو رفض.'),
        ('حالات نهائية', 'مقبول ومرفوض ومنسحب حالات نهائية. المتقدم يستطيع الانسحاب من الحالات النشطة فقط. القبول لا يغلق الفرصة تلقائياً ولا يمثل عقد توظيف.'),
        ('تحديث موثوق', 'كل تعديل يتحقق من الصلاحية ونسخة الطلب، ويضيف سجلاً وإشعاراً مرة واحدة. عند تعارض تحديثين يطلب الخادم قراءة جديدة بدلاً من الكتابة فوق قرار أحدث.')]:
        y = d.card(y, title, body)

    d.start('محادثة مرتبطة بطلب حقيقي', 'سجل مقروء وحالة إرسال واضحة، مع تحكم بالحظر والإبلاغ.')
    y = d.flow(660, [('المعلن', 'يفتح طلباً صحيحاً'), ('يبدأ المحادثة', 'واحدة لكل طلب'), ('الطرفان', 'رسائل وقراءة')])
    for title, body in [
        ('بداية منظمة', 'صاحب الفرصة يبدأ المحادثة من الطلب؛ المتقدم يسترجع الموجودة ويرد. لا شات عشوائي ولا إظهار معلومات أشخاص غير مخولين.'),
        ('رسالة واحدة رغم انقطاع الشبكة', 'الرسالة تحمل معرف عميل ثابتاً، وتظهر حالة الإرسال أو الفشل. إعادة المحاولة اليدوية تستعمل المعرف والمفتاح نفسيهما دون تكرار.'),
        ('قراءة وتحديث', 'تُجلب أحدث 50 رسالة ثم الأقدم عند الطلب. التحديث كل ثماني ثوانٍ للمحادثة الظاهرة فقط ويتوقف بالخلفية. لا «متصل الآن» أو «تم التسليم» دون دليل فعلي.'),
        ('الحظر والإبلاغ', 'حظر أي طرف يمنع الرسائل في الاتجاهين دون تنبيه المحظور. الإبلاغ ينتقل إلى شكوى خاصة. لا صور أو صوت داخل الشات ولا ادعاء تشفير من طرف لطرف.')]:
        y = d.card(y, title, body)

    d.start('الحساب والخصوصية والدعم', 'بيانات مهنية مختصرة، ومشاركة محدودة، وشكوى يسهل تتبعها.')
    y = 660
    for title, body in [
        ('الملف المهني', 'الاسم والمسمى والهاتف، ونبذة ومهارات ولغات وسنوات خبرة اختيارية. مؤشر الاكتمال يحسب البيانات المحفوظة فقط ولا يمثل فرصة القبول.'),
        ('ما يراه المعلن', 'لقطة البيانات التي وافق المتقدم على مشاركتها وقت الطلب. تعديل الملف لاحقاً لا يغير الطلبات السابقة، ولا يجعل الملف عاماً.'),
        ('الشكوى', 'نص واضح وصورة اختيارية مع معاينة، وربط بمحادثة عند الحاجة. يرفع الخادم الصورة في تخزين خاص، ثم يحفظ الشكوى وحالتها ورد الدعم.'),
        ('حدود الصورة', 'JPG أو PNG أو WebP حتى 5 ميغابايت، فحص محتوى وأبعاد وإزالة بيانات الصورة. لا رابط عام دائم ولا إظهار الأدلة للطرف المبلغ عنه.'),
        ('الخروج والحذف', 'الخروج يمسح الكاش الخاص بالجهاز. الحذف بعد تحقق حديث يسحب الفرص ويلغي الجلسات والطلبات النشطة ويخفي الهوية، مع سياسة احتفاظ معلنة.')]:
        y = d.card(y, title, body)

    d.start('الإشعارات: الحدث والمستلم', 'ينشأ الحدث بعد حفظ العملية، ثم صندوق الحساب وإشعار الهاتف حسب الإعدادات.')
    y = 660
    for title, body in [
        ('للمعلن', 'استلام الإعلان، الموافقة أو الرفض، قرب انتهاء الإعلان وانتهاؤه. كذلك وصول طلب تقديم جديد أو انسحاب متقدم.'),
        ('للمتقدم', 'تغيير حالة طلبه، بدء المعلن محادثة بشأنه، ورسالة جديدة من الطرف الآخر. لا نص رسالة خاص على شاشة القفل افتراضياً.'),
        ('لصاحب البحث والشكوى', 'فرص منشورة جديدة تطابق بحثاً محفوظاً، واستلام الشكوى وتحديثها أو رد الدعم. فرص البحث القديمة لا تطلق تنبيهاً جديداً.'),
        ('فتح الوجهة الصحيحة', 'الإشعار يحمل وجهة ومعرف مورد ومستلم دون أسرار. يتحقق التطبيق من الحساب ويطلب الدخول عند الحاجة ثم يجلب المورد بصلاحياته.'),
        ('دون ضجيج أو تكرار', 'لا إشعار لكل تحديث أو حفظ أو إعادة محاولة. تجميع المطابقات، ومنع تكرار الحدث. المحادثة المفتوحة تتحدث دون إشعار محلي ثانٍ. الويب صندوق API فقط.')]:
        y = d.card(y, title, body)

    d.start('سرعة التطبيق والعمل دون اتصال', 'الخادم هو المرجع، والكاش يجعل القراءة أسرع دون اختراع نجاح عملية.')
    y = 660
    for title, body in [
        ('مصدر تحكم واحد', 'بيانات المنصة والجلسة والطلبات تمر عبر مخزن مركزي. النقل الأصلي يستخدم URLSession على iOS وCronet على Android، والمتصفح على الويب.'),
        ('آخر نسخة ثم تحديث', 'تعرض الواجهة آخر بيانات آمنة ثم تحدثها من الخادم. الكاش الخاص مفصول بالحساب والخدمة، حتى سبعة أيام و768 كيلوبايت، ويُمسح عند الخروج.'),
        ('كتابة موثوقة', 'لا ادعاء نشر أو تقديم أو تغيير حالة دون اتصال. عند ضياع الرد تستخدم العملية المفتاح نفسه. رسائل الشات الفاشلة تبقى واضحة لإعادة محاولة صريحة.'),
        ('حماية تبديل الحساب', 'رد بطيء لحساب سابق لا يظهر في الحساب الجديد. الطلبات المتطابقة تندمج، وتجديد الجلسة المتزامن ينفذ مرة واحدة، والخادم يفرض الملكية دائماً.'),
        ('قوائم قابلة للنمو', 'بحث وتصفية وترتيب قبل تقسيم الصفحات في الخادم. لا تحميل لكل الرسائل أو حساب إجماليات مصطنعة من أول صفحة.')]:
        y = d.card(y, title, body)

    d.start('الإعلانات والتقييم والويب', 'مساحات الإعلان منفصلة عن الأفعال، والمهام الحساسة تبقى واضحة.')
    y = 660
    for title, body in [
        ('داخل الهاتف', 'إعلان Native ضمن قائمة الفرص، وبانر مشترك لتفاصيل الفرصة والإشعارات غير الفارغة. لا بانر ثابت في الرئيسية ولا إعلان يغطي أزراراً قابلة للضغط.'),
        ('كاش الإعلانات', 'مخزون مركزي في الذاكرة بمالك عرض واحد للبانر وعمر 55 دقيقة. إعادة بناء الشاشة لا تطلب إعلاناً جديداً تلقائياً، ولا تحفظ الإعلانات على القرص.'),
        ('أين لا تظهر الإعلانات؟', 'لا إعلان في الدخول أو التقديم أو المحادثة أو الشكوى. لا تسجيل ظهور مصطنع ولا وعد بدخل محدد؛ الربح يعتمد على المزاد والتفاعل الحقيقي.'),
        ('تقييم المتجر', 'نافذة النظام الأصلية بعد سبعة أيام وثلاثة إجراءات فعلية، مرة في الجلسة وفاصل 120 يوماً. النظام يقرر الظهور، بلا مكافأة أو سؤال رضا مسبق.'),
        ('تحميل التطبيق على الويب', 'طبقة بارزة تغطي المحتوى وقابلة للإغلاق وتحفظ وجهة الفرصة. رابط Google Play حقيقي وiOS «قريباً». إعلانات الويب تنتظر موافقة وكود AdSense.')]:
        y = d.card(y, title, body)

    d.start('ماذا ينفذ الباك الآن؟', 'نفس المفاتيح والردود والمسارات المجهزة بالعميل، مع الحفاظ على النسخ القديمة.')
    y = 660
    for n, title, body in [
        (1, 'حفظ التوافق وتوسيع البيانات', '16 عملية قديمة تبقى مستقرة، ويضاف عقد المنصة الجديد: 54 عملية منها ست للإدارة. migrations آمنة وبلدان ومحافظات وفهارس وصلاحيات.'),
        (2, 'المصادقة والتوظيف والدعم', 'OTP وFirebase Admin وجلسات، ملف وحفظ وبحث، مراجعة إعلان، تقديم ولقطة ملف وحالات، محادثات وحظر، وشكاوى وصور خاصة.'),
        (3, 'تشغيل الأحداث', 'outbox داخل المعاملات، workers وجدولة انتهاء وتنظيف، إشعارات بتفضيلات ومنع تكرار، وربط FCM بالجلسة والمستخدم الصحيح.'),
        (4, 'تسليم تكامل حقيقي', 'staging وحسابات اختبار، إعداد بريد وGoogle وApple وAPNs، وقيم عامة بلا أسرار، وتقرير نتائج القبول والفروق الفعلية.')]:
        y = d.card(y, title, body, n)
    d.note(y, 'المواصفات الكاملة وأمثلة كل عملية وOpenAPI وPostman والكتالوج والمراجع موجودة داخل ملف Markdown الواحد وقابلة للاستخراج منه.')

    d.start('رحلة قبول واحدة من البداية للنهاية', 'ثلاث هويات اختبار: متقدم، معلن، ومشرف. التنفيذ على staging.')
    y = 660
    for n, title, body in [
        (1, 'جهّز وانشر', 'المعلن يدخل ويضيف فرصة ببلد ومحافظة وعملة مناسبة؛ يراها كاملة وهي معلقة. المشرف يوافق فتظهر للعامة وتصل التنبيهات مرة واحدة.'),
        (2, 'قدّم وتابع', 'المتقدم يحفظ بحثاً ويقدم بموافقة وملف مختصر؛ يرى الحالة والتاريخ. المعلن يجد الطلب ويحدّثه؛ يصل التحديث للمتقدم.'),
        (3, 'راسل وجرّب الفشل', 'المعلن يبدأ المحادثة. تُختبر القراءة وقطع الشبكة وإعادة الإرسال دون تكرار والحظر، ثم شكوى بصورة ورد دعم.'),
        (4, 'اختبر الخصوصية والأجهزة', 'حسابان وجهازان، خروج وتبديل وحذف، مورد غير مملوك، تحديثات متزامنة، Push بالخلفية، وصورة وGoogle وApple على توقيع مناسب.')]:
        y = d.card(y, title, body, n)
    d.note(y, 'فحوص العقد الحالية لا تستبدل الاختبار المتكامل. المرجع يتضمن 32 سيناريو قبول للمنصة وفحوصاً إضافية للقديم والبلدان.')

    d.start('حدود الإصدار والخطوة التالية', 'واجهة محضرة + باك مطابق + خدمات فعلية + اختبار أجهزة = تكامل قابل للمراجعة.')
    y = 660
    for title, body in [
        ('الجاهز في المصدر', 'رحلات الحساب والنشر والمراجعة من جهة العميل، التقديم والمتابعة والمحادثات والدعم، الكاش والإشعارات والبلدان وتصميم الحالات الفارغة. ليست خدمة باك منشورة.'),
        ('العمل المتبقي للتفعيل', 'تنفيذ الباك حسب العقد، ضبط الخدمات الخارجية وتشغيل العمال، ثم فحص staging والأجهزة والخصوصية وإصلاح أي اختلاف قبل إصدار متجر.'),
        ('مؤجل لإصدار لاحق', 'جهات موثقة ومتابعتها، توصيات مفسرة، مواعيد مقابلات، ولوحات أرقام فعلية. لا AI ranking أو شارات تحقق أو إحصائيات وهمية في الإصدار الحالي.'),
        ('مصادر الأفكار', 'أفكار عامة من الصفحة العربية في Bayt وشرحهم الرسمي لمتابعة الطلبات. تطبيق سند له هويته وعقده؛ لم تُفحص لوحات Bayt الخاصة ولم يُنسخ محتواها.')]:
        y = d.card(y, title, body)
    y = d.note(y, 'التسليم المطلوب من الباك: بيئة staging وتقرير نتائج وقيم عامة مؤكدة. بعد المطابقة، يُبنى إصدار المتجر ويُنشر فقط عندما يطلب المالك ذلك.')
    d.text('www.bayt.com/ar/', W-M-10, y-8, 9, MUTED)
    d.text('bayt.com/en/blog/32432/', W-M-10, y-27, 9, MUTED)
    d.end()
    (ROOT/'tmp/pdfs').mkdir(parents=True, exist_ok=True)
    (ROOT/'tmp/pdfs/flow-text.json').write_text(json.dumps(d.records, ensure_ascii=False))


if __name__ == '__main__':
    markdown()
    pdf()
