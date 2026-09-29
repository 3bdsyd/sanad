"""Fursa's small WSGI API. Production entry point: app:application."""

import hashlib
import hmac
import ipaddress
import json
import logging
import os
import re
import secrets
import sqlite3
import time
import uuid
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlsplit, urlunsplit

CITIES = ["دمشق", "ريف دمشق", "حلب", "حمص", "حماة", "اللاذقية", "طرطوس", "إدلب", "دير الزور", "الرقة", "الحسكة", "درعا", "السويداء", "القنيطرة"]
CATEGORIES = ["تقنية", "تصميم", "تسويق", "مبيعات", "مطاعم وضيافة", "حِرف ومهن", "إدارة ومحاسبة", "تعليم", "صحة"]
WORK_TYPES = ["دوام كامل", "دوام جزئي", "عمل حر", "تدريب"]
WORK_MODES = ["من المكتب", "عن بُعد", "هجين"]
EXPERIENCES = ["بدون خبرة", "مبتدئ", "متوسط", "خبير"]
SALARY_PERIODS = ["شهري", "بالساعة", "للمشروع"]
STATUSES = ["pending", "published", "rejected"]
UUID_PATTERN = r"[a-f0-9-]{36}"
ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
MAX_BODY = 24_576


class ApiError(Exception):
    def __init__(self, status, code, message, field=None):
        self.status, self.code, self.message, self.field = status, code, message, field


def utc_now():
    return datetime.now(timezone.utc)


def iso(value):
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def contact_keys(job):
    return [token_hash(field + ":" + job[field].strip().lower()) for field in ("phone", "email") if job.get(field)]


def clean_text(value, field, minimum=1, maximum=120):
    if not isinstance(value, str):
        raise ApiError(422, "invalid_field", "يرجى إدخال نص صالح.", field)
    value = value.strip()
    if not minimum <= len(value) <= maximum or any((ord(c) < 32 and c not in "\n\t") or 0xD800 <= ord(c) <= 0xDFFF for c in value):
        raise ApiError(422, "invalid_field", "تحقق من طول النص ومحتواه.", field)
    # Remove invisible bidi overrides that can disguise contact information.
    if any(c in value for c in "\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"):
        raise ApiError(422, "invalid_field", "النص يحتوي على محارف غير مدعومة.", field)
    return value


def enum_value(data, field, options, default=None):
    value = data.get(field, default)
    if value not in options:
        raise ApiError(422, "invalid_field", "اختر قيمة من القائمة.", field)
    return value


def salary_value(value, field):
    if value is None:
        return None
    if type(value) is not int or not 0 <= value <= 1_000_000_000:
        raise ApiError(422, "invalid_salary", "أدخل راتباً صحيحاً وغير سالب.", field)
    return value


def company_website(value):
    field = "companyWebsite"
    message = "أضف رابط موقع صحيحاً يبدأ بـ https:// أو http://، بدون بيانات تسجيل دخول."
    if not isinstance(value, str) or re.search(r"[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\ud800-\udfff\\]", value):
        raise ApiError(422, "invalid_website", message, field)
    value = value.strip()
    if not value:
        return ""
    if re.search(r"\s|%(?:0[0-9a-f]|1[0-9a-f]|7f)", value, re.I):
        raise ApiError(422, "invalid_website", message, field)
    if not re.match(r"^[a-z][a-z0-9+.-]*:", value, re.I):
        value = "https://" + value
    try:
        url = urlsplit(value)
        host = url.hostname or ""
        if (url.scheme.lower() not in ("http", "https") or not url.netloc
                or url.username is not None or url.password is not None
                or "." not in host or len(host) > 253
                or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label, re.I) for label in host.split("."))
                or (url.port is not None and not 1 <= url.port <= 65535)):
            raise ValueError()
        port = f":{url.port}" if url.port is not None and url.port != (443 if url.scheme.lower() == "https" else 80) else ""
        normalized = urlunsplit((url.scheme.lower(), host.lower() + port, url.path, url.query, url.fragment))
        if len(normalized) > 2048:
            raise ValueError()
        return normalized
    except ValueError:
        raise ApiError(422, "invalid_website", message, field)


def validate_job(data):
    allowed = {"title", "company", "companyWebsite", "city", "category", "workType", "workMode", "experience", "salaryMin", "salaryMax", "salaryPeriod", "currency", "description", "requirements", "phone", "email", "contactConsent", "expiresInDays"}
    if set(data) - allowed:
        raise ApiError(422, "unknown_field", "توجد حقول غير مدعومة.")
    if data.get("contactConsent") is not True:
        raise ApiError(422, "consent_required", "يلزم الموافقة على عرض وسيلة التواصل للباحثين عن عمل.", "contactConsent")
    duration = data.get("expiresInDays", 30)
    if type(duration) is not int or duration not in (7, 14, 30):
        raise ApiError(422, "invalid_duration", "مدة الإعلان يجب أن تكون 7 أو 14 أو 30 يوماً.", "expiresInDays")
    result = {
        "expiresInDays": duration,
        "title": clean_text(data.get("title"), "title", 3, 100),
        "company": clean_text(data.get("company"), "company", 2, 100),
        "companyWebsite": company_website(data.get("companyWebsite", "")),
        "description": clean_text(data.get("description"), "description", 20, 5000),
        "city": enum_value(data, "city", CITIES),
        "category": enum_value(data, "category", CATEGORIES),
        "workType": enum_value(data, "workType", WORK_TYPES),
        "workMode": enum_value(data, "workMode", WORK_MODES),
        "experience": enum_value(data, "experience", EXPERIENCES),
        "currency": enum_value(data, "currency", ["SYP", "USD"], "SYP"),
        "salaryPeriod": enum_value(data, "salaryPeriod", SALARY_PERIODS, "شهري"),
        "salaryMin": salary_value(data.get("salaryMin"), "salaryMin"),
        "salaryMax": salary_value(data.get("salaryMax"), "salaryMax"),
    }
    if result["salaryMin"] is not None and result["salaryMax"] is not None and result["salaryMin"] > result["salaryMax"]:
        raise ApiError(422, "invalid_salary", "الحد الأعلى يجب أن يكون أكبر من الحد الأدنى.", "salaryMax")
    requirements = data.get("requirements", [])
    if not isinstance(requirements, list) or len(requirements) > 12:
        raise ApiError(422, "invalid_field", "أضف حتى 12 متطلباً.", "requirements")
    result["requirements"] = [clean_text(item, "requirements", 2, 200) for item in requirements]
    phone = clean_text(data.get("phone") or "", "phone", 0, 40).translate(ARABIC_DIGITS)
    phone = re.sub(r"[\s()\-]", "", phone)
    if re.fullmatch(r"09[0-9]{8}", phone):
        phone = "+963" + phone[1:]
    if phone.startswith("00"):
        phone = "+" + phone[2:]
    if phone and not re.fullmatch(r"\+[1-9][0-9]{7,14}", phone):
        raise ApiError(422, "invalid_phone", "أدخل رقم موبايل سوري أو رقماً دولياً يبدأ بـ +.", "phone")
    email = clean_text(data.get("email") or "", "email", 0, 254)
    if email and not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\.[A-Za-z]{2,63}", email):
        raise ApiError(422, "invalid_email", "أدخل بريداً إلكترونياً صحيحاً.", "email")
    if not phone and not email:
        raise ApiError(422, "contact_required", "أضف رقم هاتف أو بريداً إلكترونياً.", "phone")
    result.update(phone=phone, email=email)
    return result


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


class FursaApp:
    def __init__(self, database=None, admin_token=None, origins=None, trusted_proxies=None):
        self.database = database or os.environ.get("DATABASE_PATH", "./data/fursa.sqlite3")
        self.admin_token = admin_token or os.environ.get("ADMIN_TOKEN", "")
        if len(self.admin_token) < 32 or self.admin_token.startswith("replace-"):
            raise RuntimeError("ADMIN_TOKEN must be a unique secret with at least 32 characters.")
        self.origins = set(origins if origins is not None else filter(None, os.environ.get("ALLOWED_ORIGINS", "").split(",")))
        if "*" in self.origins:
            raise RuntimeError("ALLOWED_ORIGINS must contain exact trusted origins, never '*'.")
        self.trusted_proxies = [ipaddress.ip_network(x.strip()) for x in (trusted_proxies if trusted_proxies is not None else filter(None, os.environ.get("TRUSTED_PROXIES", "").split(",")))]
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with closing(self.connect()) as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, status TEXT NOT NULL,
                    created_at TEXT NOT NULL, expires_at TEXT NOT NULL,
                    token_hash TEXT NOT NULL, payload TEXT NOT NULL,
                    contact_consent_at TEXT NOT NULL, rejection_reason TEXT
                );
                CREATE INDEX IF NOT EXISTS jobs_public ON jobs(status, expires_at, created_at);
                CREATE TABLE IF NOT EXISTS reports (
                    id TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
                    reason TEXT NOT NULL, created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS rate_limits (
                    key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS audit (
                    id INTEGER PRIMARY KEY, job_id TEXT NOT NULL, action TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS blocked_contacts (
                    key TEXT PRIMARY KEY, reason TEXT NOT NULL, created_at TEXT NOT NULL
                );
            """)
            # Additive payload migration preserves existing jobs, tokens and
            # moderation states. New clients also accept pre-migration caches.
            if db.execute("PRAGMA user_version").fetchone()[0] < 2:
                db.execute("UPDATE jobs SET payload=json_set(payload, '$.companyWebsite', '') WHERE json_type(payload, '$.companyWebsite') IS NULL")
                db.execute("PRAGMA user_version=2")
            db.commit()
        os.chmod(self.database, 0o600)

    def connect(self):
        db = sqlite3.connect(self.database, timeout=5)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA secure_delete=ON")
        return db

    def client_ip(self, env):
        remote = env.get("REMOTE_ADDR", "unknown")

        def trusted(value):
            try:
                address = ipaddress.ip_address(value)
                return any(address in network for network in self.trusted_proxies)
            except ValueError:
                return False

        if trusted(remote):
            forwarded = env.get("HTTP_X_FORWARDED_FOR", "").split(",")
            for candidate in reversed(forwarded):
                candidate = candidate.strip()
                try:
                    ipaddress.ip_address(candidate)
                except ValueError:
                    break
                remote = candidate
                if not trusted(remote):
                    break
        return remote

    def limit(self, db, env, action, maximum, seconds):
        # Keyed digest avoids persisting raw IPs. All workers share limits in SQLite.
        identity = hmac.new(self.admin_token.encode(), self.client_ip(env).encode(), hashlib.sha256).hexdigest()
        now = int(time.time())
        key = f"{action}:{identity}:{now // seconds}"
        with db:
            db.execute("DELETE FROM rate_limits WHERE expires < ?", (now,))
            db.execute("INSERT INTO rate_limits(key,count,expires) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1", (key, now + seconds))
            count = db.execute("SELECT count FROM rate_limits WHERE key=?", (key,)).fetchone()[0]
        if count > maximum:
            raise ApiError(429, "rate_limited", "وصلت للحد المسموح. جرّب لاحقاً.")

    @staticmethod
    def body(env):
        if env.get("CONTENT_TYPE", "").split(";")[0].strip().lower() != "application/json":
            raise ApiError(415, "json_required", "أرسل البيانات بصيغة JSON.")
        try:
            length = int(env.get("CONTENT_LENGTH", "0"))
        except ValueError:
            raise ApiError(400, "invalid_body", "حجم الطلب غير صحيح.")
        if length < 1:
            raise ApiError(400, "empty_body", "بيانات الطلب فارغة.")
        if length > MAX_BODY:
            raise ApiError(413, "body_too_large", "حجم الطلب كبير جداً.")
        try:
            data = json.loads(env["wsgi.input"].read(length).decode("utf-8"), object_pairs_hook=unique_object)
            if not isinstance(data, dict):
                raise ValueError("object required")
            return data
        except (ValueError, UnicodeError, RecursionError):
            raise ApiError(400, "invalid_json", "بيانات الطلب غير صحيحة.")

    @staticmethod
    def bearer(env):
        authorization = env.get("HTTP_AUTHORIZATION", "")
        if not authorization.startswith("Bearer ") or len(authorization) > 1024:
            raise ApiError(401, "unauthorized", "رمز الإدارة غير صحيح.")
        return authorization[7:]

    def require_admin(self, env):
        if not hmac.compare_digest(self.bearer(env).encode(), self.admin_token.encode()):
            raise ApiError(401, "unauthorized", "رمز الإدارة غير صحيح.")

    @staticmethod
    def view(row, private=False):
        payload = json.loads(row["payload"])
        payload.setdefault("companyWebsite", "")
        status = "expired" if row["status"] in ("pending", "published") and row["expires_at"] <= iso(utc_now()) else row["status"]
        payload.update(id=row["id"], status=status, createdAt=row["created_at"], expiresAt=row["expires_at"])
        payload["employerKey"] = contact_keys(payload)[0]
        if private and row["rejection_reason"]:
            payload["rejectionReason"] = row["rejection_reason"]
        return payload

    @staticmethod
    def integer_query(query, field, default, minimum, maximum):
        try:
            raw = query.get(field, str(default))
            if not re.fullmatch(r"\d+", raw):
                raise ValueError()
            value = int(raw)
            if not minimum <= value <= maximum:
                raise ValueError()
            return value
        except ValueError:
            raise ApiError(422, "invalid_filter", "قيمة الفلتر غير صحيحة.", field)

    def list_jobs(self, db, env, admin=False):
        try:
            raw_query = parse_qs(env.get("QUERY_STRING", ""), max_num_fields=20)
        except ValueError:
            raise ApiError(400, "invalid_query", "عدد الفلاتر كبير جداً.")
        if any(len(values) != 1 for values in raw_query.values()):
            raise ApiError(422, "invalid_filter", "أرسل قيمة واحدة لكل فلتر.")
        query = {key: values[0] for key, values in raw_query.items()}
        permitted = {"page", "pageSize", "sort", "q", "city", "category", "workType", "workMode", "experience", "currency", "salaryMin", "salaryMax", "salaryPeriod"}
        if admin:
            permitted.add("status")
        if set(query) - permitted:
            raise ApiError(422, "invalid_filter", "يوجد فلتر غير مدعوم.")
        page = self.integer_query(query, "page", 1, 1, 10000)
        size = self.integer_query(query, "pageSize", 20, 1, 50)
        clauses, values = [], []
        if admin:
            status = enum_value(query, "status", STATUSES, "pending")
            clauses.append("status=?")
            values.append(status)
        else:
            clauses += ["status='published'", "expires_at > ?"]
            values.append(iso(utc_now()))
        for field, options in [("city", CITIES), ("category", CATEGORIES), ("workType", WORK_TYPES), ("workMode", WORK_MODES), ("experience", EXPERIENCES), ("currency", ["SYP", "USD"]), ("salaryPeriod", SALARY_PERIODS)]:
            if field in query:
                value = enum_value(query, field, options)
                clauses.append(f"json_extract(payload, '$.{field}')=?")
                values.append(value)
        if "q" in query:
            search = clean_text(query["q"], "q", 1, 100).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            clauses.append("(json_extract(payload,'$.title') LIKE ? ESCAPE '\\' OR json_extract(payload,'$.company') LIKE ? ESCAPE '\\' OR json_extract(payload,'$.description') LIKE ? ESCAPE '\\')")
            values.extend([f"%{search}%"] * 3)
        if "salaryMin" in query or "salaryMax" in query or query.get("sort") == "salary":
            if "currency" not in query or "salaryPeriod" not in query:
                raise ApiError(422, "salary_unit_required", "حدد العملة وفترة الراتب عند مقارنة الرواتب.", "currency")
        if "salaryMin" in query:
            clauses.append("COALESCE(json_extract(payload,'$.salaryMax'),json_extract(payload,'$.salaryMin')) >= ?")
            values.append(self.integer_query(query, "salaryMin", 0, 0, 1_000_000_000))
        if "salaryMax" in query:
            clauses.append("COALESCE(json_extract(payload,'$.salaryMin'),json_extract(payload,'$.salaryMax')) <= ?")
            values.append(self.integer_query(query, "salaryMax", 0, 0, 1_000_000_000))
        sort = enum_value(query, "sort", ["newest", "salary"], "newest")
        ordering = "created_at DESC,id DESC" if sort == "newest" else "COALESCE(json_extract(payload,'$.salaryMax'),json_extract(payload,'$.salaryMin')) DESC,created_at DESC,id DESC"
        where = " AND ".join(clauses)
        total = db.execute(f"SELECT COUNT(*) FROM jobs WHERE {where}", values).fetchone()[0]
        rows = db.execute(f"SELECT * FROM jobs WHERE {where} ORDER BY {ordering} LIMIT ? OFFSET ?", values + [size, (page - 1) * size]).fetchall()
        return {"jobs": [self.view(row, admin) for row in rows], "total": total, "page": page, "pageSize": size}

    def dispatch(self, db, env):
        path, method = env.get("PATH_INFO", "/"), env["REQUEST_METHOD"]
        if method == "GET" and path == "/health":
            db.execute("SELECT 1").fetchone()
            return 200, {"status": "ok"}
        if path.startswith("/v1/admin/"):
            self.limit(db, env, "admin", 120, 60)
            self.require_admin(env)
        elif method == "GET":
            self.limit(db, env, "read", 180, 60)
        if path == "/v1/jobs" and method == "GET":
            return 200, self.list_jobs(db, env)
        if path == "/v1/jobs" and method == "POST":
            self.limit(db, env, "post", 5, 3600)
            job = validate_job(self.body(env))
            duration = job.pop("expiresInDays")
            identifier, token, now = str(uuid.uuid4()), secrets.token_urlsafe(32), utc_now()
            with db:
                db.execute("BEGIN IMMEDIATE")
                if any(db.execute("SELECT 1 FROM blocked_contacts WHERE key=?", (key,)).fetchone() for key in contact_keys(job)):
                    raise ApiError(403, "publisher_blocked", "لا يمكن نشر إعلان بوسيلة التواصل هذه. تواصل مع الدعم.")
                db.execute("INSERT INTO jobs VALUES(?,?,?,?,?,?,?,NULL)", (identifier, "pending", iso(now), iso(now + timedelta(days=duration)), token_hash(token), json.dumps(job, ensure_ascii=False), iso(now)))
            return 201, {"id": identifier, "status": "pending", "managementToken": token}
        match = re.fullmatch(rf"/v1/jobs/({UUID_PATTERN})", path)
        if match and method == "GET":
            row = db.execute("SELECT * FROM jobs WHERE id=? AND status='published' AND expires_at>?", (match[1], iso(utc_now()))).fetchone()
            if not row:
                raise ApiError(404, "not_found", "هذه الفرصة غير متاحة.")
            return 200, {"job": self.view(row)}
        match = re.fullmatch(rf"/v1/jobs/({UUID_PATTERN})/report", path)
        if match and method == "POST":
            self.limit(db, env, "report", 20, 3600)
            data = self.body(env)
            if set(data) != {"reason"}:
                raise ApiError(422, "invalid_field", "أرسل سبب البلاغ فقط.")
            reason = clean_text(data.get("reason"), "reason", 5, 1000)
            row = db.execute("SELECT id FROM jobs WHERE id=? AND status='published' AND expires_at>?", (match[1], iso(utc_now()))).fetchone()
            if not row:
                raise ApiError(404, "not_found", "هذه الفرصة غير متاحة.")
            with db:
                db.execute("INSERT INTO reports VALUES(?,?,?,?)", (str(uuid.uuid4()), match[1], reason, iso(utc_now())))
            return 201, {"success": True}
        match = re.fullmatch(rf"/v1/submissions/({UUID_PATTERN})", path)
        if match and method in ("GET", "DELETE"):
            self.limit(db, env, "management", 30, 60)
            supplied = token_hash(self.bearer(env))
            row = db.execute("SELECT * FROM jobs WHERE id=?", (match[1],)).fetchone()
            if row is None or not hmac.compare_digest(supplied, row["token_hash"]):
                raise ApiError(404, "not_found", "الإعلان غير موجود أو رمز إدارته غير صحيح.")
            if method == "GET":
                return 200, {"job": self.view(row, True), "status": self.view(row)["status"]}
            with db:
                db.execute("DELETE FROM jobs WHERE id=?", (match[1],))
                db.execute("INSERT INTO audit(job_id,action,created_at) VALUES(?,?,?)", (match[1], "owner_deleted", iso(utc_now())))
            return 200, {"success": True, "status": "withdrawn"}
        if path == "/v1/admin/jobs" and method == "GET":
            return 200, self.list_jobs(db, env, True)
        if path == "/v1/admin/reports" and method == "GET":
            return 200, {"reports": [dict(row) for row in db.execute("SELECT * FROM reports ORDER BY created_at DESC LIMIT 200").fetchall()]}
        match = re.fullmatch(rf"/v1/admin/jobs/({UUID_PATTERN})/(approve|reject|block)", path)
        if match and method == "POST":
            data = self.body(env)
            if set(data) - {"reason"}:
                raise ApiError(422, "invalid_field", "بيانات المراجعة غير صحيحة.")
            reason = clean_text(data.get("reason", ""), "reason", 0, 500)
            # Serialize moderation with submission and withdrawal to enforce blocks.
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM jobs WHERE id=?", (match[1],)).fetchone()
            if not row:
                raise ApiError(404, "not_found", "الإعلان غير موجود.")
            if match[2] == "block":
                keys = set(contact_keys(json.loads(row["payload"])))
                with db:
                    for key in keys:
                        db.execute("INSERT OR REPLACE INTO blocked_contacts VALUES(?,?,?)", (key, reason, iso(utc_now())))
                    for candidate in db.execute("SELECT id,payload FROM jobs WHERE status IN ('pending','published')").fetchall():
                        if keys.intersection(contact_keys(json.loads(candidate["payload"]))):
                            db.execute("UPDATE jobs SET status='rejected',rejection_reason=? WHERE id=?", (reason, candidate["id"]))
                    db.execute("INSERT INTO audit(job_id,action,created_at) VALUES(?,?,?)", (match[1], "block", iso(utc_now())))
                return 200, {"id": match[1], "status": "rejected", "blocked": True}
            approve = match[2] == "approve"
            if approve and row["status"] != "pending":
                raise ApiError(409, "invalid_transition", "يمكن نشر الإعلانات قيد المراجعة فقط.")
            if approve and row["expires_at"] <= iso(utc_now()):
                raise ApiError(409, "expired", "انتهت صلاحية الإعلان. اطلب إرساله مجدداً.")
            if approve and any(db.execute("SELECT 1 FROM blocked_contacts WHERE key=?", (key,)).fetchone() for key in contact_keys(json.loads(row["payload"]))):
                raise ApiError(409, "publisher_blocked", "وسيلة التواصل هذه محظورة.")
            status = "published" if approve else "rejected"
            with db:
                db.execute("UPDATE jobs SET status=?,rejection_reason=? WHERE id=?", (status, None if approve else reason, match[1]))
                db.execute("INSERT INTO audit(job_id,action,created_at) VALUES(?,?,?)", (match[1], match[2], iso(utc_now())))
            return 200, {"id": match[1], "status": status}
        raise ApiError(404, "not_found", "المسار غير موجود.")

    def __call__(self, env, start_response):
        origin = env.get("HTTP_ORIGIN")
        headers = [("Content-Type", "application/json; charset=utf-8"), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"), ("Vary", "Origin")]
        try:
            if origin:
                if origin not in self.origins:
                    raise ApiError(403, "origin_denied", "هذا المصدر غير مسموح.")
                headers.append(("Access-Control-Allow-Origin", origin))
            if env["REQUEST_METHOD"] == "OPTIONS":
                headers.extend([("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"), ("Access-Control-Allow-Headers", "Content-Type, Authorization"), ("Access-Control-Max-Age", "600")])
                status, payload = 200, {"success": True}
            else:
                with closing(self.connect()) as db:
                    status, payload = self.dispatch(db, env)
        except ApiError as error:
            status, payload = error.status, {"error": {"code": error.code, "message": error.message}}
            if error.field:
                payload["error"]["field"] = error.field
            if status == 429:
                headers.append(("Retry-After", "60"))
        except sqlite3.OperationalError:
            logging.exception("Database unavailable")
            status, payload = 503, {"error": {"code": "unavailable", "message": "الخدمة مشغولة حالياً. حاول مجدداً."}}
        except Exception:
            logging.exception("Unhandled API failure")
            status, payload = 500, {"error": {"code": "internal", "message": "حدث خطأ غير متوقع. حاول مجدداً."}}
        body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
        headers.append(("Content-Length", str(len(body))))
        labels = {200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Content Too Large", 415: "Unsupported Media Type", 422: "Unprocessable Content", 429: "Too Many Requests", 500: "Internal Server Error", 503: "Service Unavailable"}
        start_response(f"{status} {labels[status]}", headers)
        return [body]


# Do not load a permissive fallback: production refuses to start without its secret.
application = FursaApp() if __name__ != "__main__" and os.environ.get("FURSA_TEST_IMPORT") != "1" else None


if __name__ == "__main__":
    from wsgiref.simple_server import make_server

    logging.basicConfig(level=logging.INFO)
    app = FursaApp()
    host = os.environ.get("DEV_HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8080"))
    print(f"Local development only: http://{host}:{port}", flush=True)
    with make_server(host, port, app) as server:
        server.serve_forever()
