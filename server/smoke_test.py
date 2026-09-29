"""Small executable API lifecycle check; uses a temporary database, no live services."""

import io
import json
import os
import secrets
import sqlite3
import tempfile
import threading
import urllib.request
from wsgiref.simple_server import WSGIRequestHandler, make_server

os.environ["FURSA_TEST_IMPORT"] = "1"
from app import FursaApp

JOB = {
    "title": "مطور تطبيقات فلتر",
    "company": "شركة تجريبية",
    "companyWebsite": "Example.com/about",
    "city": "دمشق",
    "category": "تقنية",
    "workType": "دوام كامل",
    "workMode": "هجين",
    "experience": "متوسط",
    "salaryMin": 700,
    "salaryMax": 1000,
    "salaryPeriod": "شهري",
    "currency": "USD",
    "description": "نبحث عن مطور تطبيقات للعمل ضمن فريق متعاون في دمشق.",
    "requirements": ["خبرة في تطوير تطبيقات Flutter"],
    "phone": "٠٩٤٤١٢٣٤٥٦",
    "email": "",
    "contactConsent": True,
}


def main():
    checks = 0
    with tempfile.TemporaryDirectory() as directory:
        database = os.path.join(directory, "smoke.sqlite3")
        admin = secrets.token_urlsafe(48)
        app = FursaApp(database, admin, origins=["https://jobs.example.test"])
        call_index = 0

        def request(method, path, body=None, token=None, origin=None, ip=None, raw=None):
            nonlocal call_index
            call_index += 1
            encoded = raw if raw is not None else json.dumps(body).encode() if body is not None else b""
            route, _, query = path.partition("?")
            env = {"REQUEST_METHOD": method, "PATH_INFO": route, "QUERY_STRING": query,
                   "REMOTE_ADDR": ip or f"192.0.2.{call_index % 254 + 1}", "CONTENT_TYPE": "application/json",
                   "CONTENT_LENGTH": str(len(encoded)), "wsgi.input": io.BytesIO(encoded)}
            if token:
                env["HTTP_AUTHORIZATION"] = "Bearer " + token
            if origin:
                env["HTTP_ORIGIN"] = origin
            result = {}

            def start(status, headers):
                result["status"] = int(status.split()[0])
                result["headers"] = dict(headers)

            result["body"] = json.loads(b"".join(app(env, start)))
            return result

        def expect(condition, label):
            nonlocal checks
            assert condition, label
            checks += 1

        expect(request("GET", "/health")["status"] == 200, "database health")
        expect(request("GET", "/v1/jobs")["body"]["total"] == 0, "no production seeds")
        invalid = dict(JOB, contactConsent=False)
        expect(request("POST", "/v1/jobs", invalid)["status"] == 422, "consent required")
        expect(request("POST", "/v1/jobs", dict(JOB, status="published"))["status"] == 422, "cannot self-publish")
        expect(request("POST", "/v1/jobs", dict(JOB, salaryMin=2000))["status"] == 422, "salary bounds")
        expect(request("POST", "/v1/jobs", dict(JOB, phone="invalid", email=""))["status"] == 422, "phone validation")
        expect(request("POST", "/v1/jobs", dict(JOB, expiresInDays=365))["status"] == 422, "duration bounded")
        expect(request("POST", "/v1/jobs", dict(JOB, title="\ud800 bad"))["status"] == 422, "invalid Unicode rejected")
        expect(request("POST", "/v1/jobs", raw=b'{"title":"a","title":"b"}')["status"] == 400, "duplicate JSON keys")
        for website in ["javascript:alert(1)", "file:///tmp/company", "ftp://example.com", "https://user:password@example.com", "https://@example.com", "https://example.com\n", "https://example.com/%0a", "https://example.com:99999", "https://not a host.com", "https://-bad.example.com", "https://example.com\\@evil.example", "https://example.com/\u202e", "https://example.com/\ud800", "https://example.com/" + "a" * 2048, None, 123]:
            invalid_link = request("POST", "/v1/jobs", dict(JOB, companyWebsite=website))
            expect(invalid_link["status"] == 422 and invalid_link["body"]["error"]["field"] == "companyWebsite", "invalid company website rejected")
        created = request("POST", "/v1/jobs", dict(JOB, expiresInDays=7))
        identifier, token = created["body"]["id"], created["body"]["managementToken"]
        expect(created["status"] == 201 and created["body"]["status"] == "pending", "pending by default")
        expect(request("GET", "/v1/jobs")["body"]["total"] == 0, "pending not public")
        expect(request("GET", f"/v1/jobs/{identifier}")["status"] == 404, "pending direct URL hidden")
        expect(request("GET", f"/v1/submissions/{identifier}", token="wrong")["status"] == 404, "private token required")
        managed = request("GET", f"/v1/submissions/{identifier}", token=token)
        from datetime import datetime
        persisted_job = managed["body"]["job"]
        duration = datetime.fromisoformat(persisted_job["expiresAt"].replace("Z", "+00:00")) - datetime.fromisoformat(persisted_job["createdAt"].replace("Z", "+00:00"))
        expect(duration.days == 7, "server owns seven-day expiry")
        expect(managed["body"]["job"]["phone"] == "+963944123456", "Arabic phone normalized")
        expect(persisted_job["companyWebsite"] == "https://example.com/about", "company website normalized and persisted")
        expect("contactConsent" not in managed["body"]["job"], "consent metadata private")
        with sqlite3.connect(database) as db:
            stored = db.execute("SELECT token_hash FROM jobs WHERE id=?", (identifier,)).fetchone()[0]
        expect(stored != token and len(stored) == 64, "only token hash persisted")
        expect(request("GET", "/v1/admin/jobs")["status"] == 401, "admin protected")
        expect(request("GET", "/v1/admin/jobs", token=admin)["body"]["total"] == 1, "moderation queue")
        expect(request("POST", f"/v1/admin/jobs/{identifier}/approve", {}, token=admin)["status"] == 200, "approval")
        published = request("GET", "/v1/jobs")["body"]
        expect(published["total"] == 1 and "managementToken" not in published["jobs"][0], "public published only")
        expect(published["jobs"][0]["companyWebsite"] == "https://example.com/about", "company website available publicly only after approval")
        expect(request("GET", "/v1/jobs?salaryMin=800")["status"] == 422, "salary currency required")
        from urllib.parse import urlencode
        query = urlencode({"q": "فلتر", "salaryMin": 800, "currency": "USD", "salaryPeriod": "شهري"})
        expect(request("GET", "/v1/jobs?" + query)["body"]["total"] == 1, "Arabic search and salary overlap")
        expect(request("GET", "/v1/jobs?pageSize=9999")["status"] == 422, "pagination bounded")
        expect(request("GET", "/v1/jobs?city=not-a-city")["status"] == 422, "filters validated")
        expect(request("GET", "/v1/jobs?unknown=1")["status"] == 422, "unknown filter rejected")
        expect(request("GET", "/v1/jobs?q=%27%20OR%201=1--")["body"]["total"] == 0, "query parameterization")
        expect(request("GET", "/v1/jobs", origin="https://evil.example")["status"] == 403, "CORS closed")
        cors = request("OPTIONS", "/v1/jobs", origin="https://jobs.example.test")
        expect(cors["headers"]["Access-Control-Allow-Origin"] == "https://jobs.example.test", "CORS exact origin")
        expect(request("POST", f"/v1/jobs/{identifier}/report", {"reason": "إعلان وهمي للاختبار"})["status"] == 201, "report accepted")
        expect(len(request("GET", "/v1/admin/reports", token=admin)["body"]["reports"]) == 1, "report reaches moderation")
        # Startup against the same durable file must preserve approved postings.
        app = FursaApp(database, admin, origins=["https://jobs.example.test"])
        expect(request("GET", "/v1/jobs")["body"]["total"] == 1, "survives restart")
        expect(request("GET", f"/v1/jobs/{identifier}")["body"]["job"]["companyWebsite"] == "https://example.com/about", "website survives restart")
        # Simulate an existing v1 payload; startup adds only the optional key.
        with sqlite3.connect(database) as db:
            db.execute("UPDATE jobs SET payload=json_remove(payload, '$.companyWebsite') WHERE id=?", (identifier,))
            db.execute("PRAGMA user_version=1")
        app = FursaApp(database, admin, origins=["https://jobs.example.test"])
        migrated = request("GET", f"/v1/submissions/{identifier}", token=token)["body"]["job"]
        expect(migrated["companyWebsite"] == "" and migrated["title"] == JOB["title"] and migrated["status"] == "published", "v1 migration preserves job and owner token")
        with sqlite3.connect(database) as db:
            expect(db.execute("PRAGMA user_version").fetchone()[0] == 2, "payload schema migration recorded")
        expect(request("DELETE", f"/v1/submissions/{identifier}", token="wrong")["status"] == 404, "unauthorized delete denied")
        expect(request("DELETE", f"/v1/submissions/{identifier}", token=token)["status"] == 200, "owner delete")
        expect(request("GET", "/v1/jobs")["body"]["total"] == 0, "deleted from public")
        expect(request("GET", f"/v1/submissions/{identifier}", token=token)["status"] == 404, "contact data removed")
        expect(len(request("GET", "/v1/admin/reports", token=admin)["body"]["reports"]) == 0, "reports cascade deletion")
        old_client_job = {key: value for key, value in JOB.items() if key != "companyWebsite"}
        created = request("POST", "/v1/jobs", old_client_job)["body"]
        identifier = created["id"]
        expect(request("GET", f"/v1/submissions/{identifier}", token=created["managementToken"])["body"]["job"]["companyWebsite"] == "", "old clients may omit website")
        expect(request("POST", f"/v1/admin/jobs/{identifier}/block", {"reason": "إساءة متكررة"}, token=admin)["status"] == 200, "publisher block")
        expect(request("POST", "/v1/jobs", JOB)["status"] == 403, "blocked contact cannot post")
        for _ in range(5):
            request("POST", "/v1/jobs", {}, ip="198.51.100.99")
        expect(request("POST", "/v1/jobs", {}, ip="198.51.100.99")["status"] == 429, "shared durable posting rate limit")
        spoofed = {"REMOTE_ADDR": "198.51.100.2", "HTTP_X_FORWARDED_FOR": "1.1.1.1"}
        expect(app.client_ip(spoofed) == "198.51.100.2", "untrusted proxy header ignored")
        trusted = FursaApp(database, admin, trusted_proxies=["127.0.0.1/32"])
        expect(trusted.client_ip({"REMOTE_ADDR": "127.0.0.1", "HTTP_X_FORWARDED_FOR": "1.1.1.1, 198.51.100.2"}) == "198.51.100.2", "trusted chain reads rightmost untrusted IP")
        with sqlite3.connect(database) as db:
            db.execute("UPDATE jobs SET status='published',expires_at='2000-01-01T00:00:00Z'")
        expect(request("GET", "/v1/jobs")["body"]["total"] == 0, "expired jobs hidden")

        class QuietHandler(WSGIRequestHandler):
            def log_message(self, *args):
                pass

        with make_server("127.0.0.1", 0, app, handler_class=QuietHandler) as httpd:
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            with urllib.request.urlopen(f"http://127.0.0.1:{httpd.server_port}/health", timeout=3) as response:
                expect(json.load(response)["status"] == "ok", "real HTTP health")
            httpd.shutdown()
            thread.join(timeout=3)
    print(f"PASS: {checks} API checks (temporary SQLite, no external services)")


if __name__ == "__main__":
    main()
