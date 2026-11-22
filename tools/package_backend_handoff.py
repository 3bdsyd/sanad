"""Build the reviewable backend handoff; never connects to or deploys a server."""
import hashlib
import json
import re
import shutil
from pathlib import Path
from urllib.parse import quote
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/backend-handoff-2026-11-03'
OUTPUT = ROOT / 'build/review/snad-complete-backend-handoff-20261103.zip'
DELIVERY = ROOT / 'docs/snad-backend-handoff-20261104.zip'


def encoded(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def collection(spec):
    items = []
    for path, methods in spec['paths'].items():
        for method, operation in methods.items():
            url_path = re.sub(r'\{(\w+)\}', r'{{\1}}', path)
            query, headers = [], [{'key': 'Accept', 'value': 'application/json'}]
            security = {key for requirement in operation.get('security', []) for key in requirement}
            if 'MemberBearer' in security:
                headers.append({'key': 'Authorization', 'value': 'Bearer {{accessToken}}'})
            elif 'AdminBearer' in security:
                headers.append({'key': 'Authorization', 'value': 'Bearer {{adminToken}}'})
            elif operation.get('security'):
                headers.append({'key': 'X-Device-ID', 'value': '{{deviceId}}'})
            for parameter in operation.get('parameters', []):
                if parameter['in'] == 'header':
                    header_value = '{{idempotencyKey}}' if parameter['name'] == 'Idempotency-Key' else '{{deviceId}}'
                    if not any(h['key'] == parameter['name'] for h in headers):
                        headers.append({'key': parameter['name'], 'value': header_value})
                if parameter['in'] != 'query':
                    continue
                schema = parameter['schema']
                value = parameter.get('example', (schema.get('enum') or [''])[0])
                if parameter['name'] == 'job_field_id':
                    value = '{{jobFieldId}}'
                query.append({'key': parameter['name'], 'value': str(value), 'disabled': not parameter.get('required', False) and parameter['name'] not in ['page', 'per_page', 'sort']})
            query_text = '&'.join(f"{q['key']}={quote(q['value'], safe='{}')}" for q in query if not q['disabled'])
            raw = '{{baseUrl}}' + url_path + ('?' + query_text if query_text else '')
            request = {'method': method.upper(), 'header': headers, 'url': {'raw': raw, 'host': ['{{baseUrl}}'], 'path': url_path.strip('/').split('/'), 'query': query}, 'description': operation.get('description', operation['summary']) + '\nSee PLATFORM.md (v2) / CONTRACT.md (legacy). Use isolated staging. Set a new idempotencyKey for a NEW logical write; retain it on retry.'}
            if 'requestBody' in operation:
                example = operation['requestBody']['content']['application/json']['example']
                body = encoded(example).replace('contract-test-device-only', '{{deviceId}}').replace('TEST_TOKEN_REPLACE_ON_STAGING', '{{fcmToken}}')
                body = body.replace('"job_id": 970001', '"job_id": {{jobId}}').replace('"job_field_id": 1', '"job_field_id": {{jobFieldId}}')
                body = body.replace('TEST_ONLY_REFRESH_REPLACE_IN_STAGING', '{{refreshToken}}').replace('TEST_ONLY_FIREBASE_ID_TOKEN', '{{firebaseIdToken}}')
                headers.append({'key': 'Content-Type', 'value': 'application/json; charset=utf-8'})
                request['body'] = {'mode': 'raw', 'raw': body, 'options': {'raw': {'language': 'json'}}}
            codes = [int(c) for c in operation['responses'] if c.startswith('2')]
            checks = [
                f"pm.test('HTTP success matches contract', () => pm.expect({json.dumps(codes)}).to.include(pm.response.code));",
                "if (pm.response.code !== 204 && pm.response.text()) {",
                "  const body = pm.response.json();",
                "  pm.test('JSON object response', () => pm.expect(body).to.be.an('object'));",
                "  pm.test('response envelope', () => pm.expect('data' in body || body.success === true).to.eql(true));" if path.startswith('/api/v2/') else "  pm.test('success flag', () => pm.expect(body.success).to.eql(true));",
            ]
            if path in ['/api/v2/auth/email/verify', '/api/v2/auth/social', '/api/v2/auth/refresh']:
                checks.append("  if (pm.response.code === 200 && body.data) { pm.collectionVariables.set('accessToken', body.data.access_token); pm.collectionVariables.set('refreshToken', body.data.refresh_token); }")
            if operation['operationId'] == 'createJob':
                checks += ["  pm.test('Created pending job', () => pm.expect(body.data.status).to.eql('pending'));", "  if (body.data && body.data.id) pm.collectionVariables.set('jobId', String(body.data.id));"]
            if operation['operationId'] == 'toggleFavorite':
                checks.append("  pm.test('Root is_added boolean', () => pm.expect(body.is_added).to.be.a('boolean'));")
            if operation['operationId'] in ['getJobs', 'filterJobs']:
                checks.append("  pm.test('Numeric pagination', () => ['current_page','last_page','per_page','total'].forEach(k => pm.expect(body.meta[k]).to.be.a('number')));")
            checks.append('}')
            examples = []
            for code, response in operation['responses'].items():
                if not code.startswith('2'):
                    continue
                payload = response.get('content', {}).get('application/json', {}).get('example')
                examples.append({'name': f'{code} contract example', 'originalRequest': request, 'code': int(code), 'header': [] if payload is None else [{'key': 'Content-Type', 'value': 'application/json'}], 'body': '' if payload is None else encoded(payload)})
            items.append({'name': method.upper() + ' ' + path + ' — ' + operation['summary'], 'request': request, 'response': examples, 'event': [{'listen': 'test', 'script': {'type': 'text/javascript', 'exec': checks}}]})
    variables = {'baseUrl': 'https://staging.example.test', 'deviceId': 'contract-test-device-only', 'jobId': '970001', 'jobFieldId': '1', 'noticeId': 'notice-test-1', 'fcmToken': 'TEST_TOKEN_REPLACE_ON_STAGING', 'accessToken': '', 'refreshToken': '', 'adminToken': '', 'firebaseIdToken': '', 'idempotencyKey': 'REPLACE_FOR_EACH_NEW_WRITE_KEEP_FOR_RETRY', 'applicationId': 'application-test-1', 'conversationId': 'conversation-test-1', 'memberId': 'member-test-1', 'complaintId': 'complaint-test-1', 'searchId': 'search-test-1'}
    return {'info': {'name': 'Sanad complete API — ' + spec['info']['version'], 'description': 'Read README.md, PLATFORM.md and CONTRACT.md. Isolated staging only. Never export populated tokens into a shared handoff. Run auth and moderation deliberately, not an unattended production collection.', 'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'}, 'variable': [{'key': k, 'value': v} for k, v in variables.items()], 'item': items}


def main():
    spec = json.loads((SOURCE / 'openapi.json').read_text())
    # Check internal references and examples before distributing the contract.
    def check(value):
        if isinstance(value, dict):
            if '$ref' in value:
                reference = value['$ref']
                if not reference.startswith('#/'):
                    raise ValueError('External schema reference: ' + reference)
                target = spec
                for part in reference[2:].split('/'):
                    target = target[part]
            for child in value.values():
                check(child)
        elif isinstance(value, list):
            for child in value:
                check(child)
    check(spec)
    operations = [(path, method) for path, methods in spec['paths'].items() for method in methods]
    inventory = spec['x-inventory']
    if len(operations) != inventory['operations'] or len(spec['paths']) != inventory['paths']:
        raise ValueError('Update handoff inventory before packaging new operations.')
    files = {str(path.relative_to(SOURCE)): path.read_bytes() for path in SOURCE.rglob('*') if path.is_file()}
    files['postman_collection.json'] = encoded(collection(spec)).encode()
    files['catalog/job_regions.json'] = (ROOT / 'server/job_regions.json').read_bytes()
    files['catalog/job-regions-LICENSE.txt'] = (ROOT / 'assets/licenses/job-regions.txt').read_bytes()
    files['catalog/job-geography-LICENSE.txt'] = (ROOT / 'assets/licenses/job-geography.txt').read_bytes()
    patch = ROOT / 'server/production-patches/jobs_20261103_global'
    for path in patch.rglob('*'):
        if path.is_file():
            files['reference/global/' + str(path.relative_to(patch))] = path.read_bytes()
    for relative in ['app/Http/Resources/JobResource.php', 'app/Http/Requests/StoreJobRequest.php', 'app/Http/Requests/UpdateJobRequest.php']:
        files['reference/existing/' + relative] = (ROOT / 'server/production-patches/jobs_20261009' / relative).read_bytes()
    for relative in ['app-ads.txt', 'privacy/index.html', 'info.css', 'icons/Icon-192.png']:
        files['web/' + relative] = (ROOT / 'web' / relative).read_bytes()
    manifest = ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n' for name, data in sorted(files.items()))
    files['FILES.sha256'] = manifest.encode()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, 'w', ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            archive.writestr('snad-backend-handoff-20261103/' + name, data)
    with ZipFile(OUTPUT) as archive:
        if archive.testzip() is not None:
            raise ValueError('Archive failed CRC verification')
    shutil.copyfile(OUTPUT, DELIVERY)
    print(f'Packaged {len(files)} files, {len(operations)} operations: {OUTPUT}')
    print(f'Delivery copy preserved outside build caches: {DELIVERY}')


if __name__ == '__main__':
    main()
