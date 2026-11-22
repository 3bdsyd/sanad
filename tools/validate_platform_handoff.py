"""Offline structural + example validation for the complete platform handoff.

No HTTP requests or credentials; understands the OpenAPI 3.0 schema constructs
used by this project's generated v2 contract. Not a live backend acceptance test.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/backend-handoff-2026-11-03'


def validate(spec, schema, value, where):
    if value is None and schema.get('nullable'):
        return
    if '$ref' in schema:
        target = spec
        for part in schema['$ref'][2:].split('/'):
            target = target[part]
        return validate(spec, target, value, where)
    kind = schema.get('type')
    types = {'object': dict, 'array': list, 'string': str, 'integer': int, 'number': (int, float), 'boolean': bool}
    if kind and (not isinstance(value, types[kind]) or kind in ['integer', 'number'] and isinstance(value, bool)):
        raise ValueError(f'{where}: expected {kind}, got {type(value).__name__}')
    if 'enum' in schema and value not in schema['enum']:
        raise ValueError(f'{where}: outside enum')
    if kind == 'object':
        for key in schema.get('required', []):
            if key not in value:
                raise ValueError(f'{where}: missing {key}')
        for key, child in value.items():
            definition = schema.get('properties', {}).get(key)
            if definition is None:
                if schema.get('additionalProperties') is False:
                    raise ValueError(f'{where}: unexpected property {key}')
                definition = schema.get('additionalProperties')
            if isinstance(definition, dict):
                validate(spec, definition, child, where + '.' + key)
    elif kind == 'array':
        for index, child in enumerate(value):
            validate(spec, schema['items'], child, f'{where}[{index}]')
    elif kind == 'string':
        if not schema.get('minLength', 0) <= len(value) <= schema.get('maxLength', float('inf')):
            raise ValueError(f'{where}: invalid string length')
        if 'pattern' in schema and re.search(schema['pattern'], value) is None:
            raise ValueError(f'{where}: invalid pattern')
    elif kind in ['integer', 'number']:
        if not schema.get('minimum', -float('inf')) <= value <= schema.get('maximum', float('inf')):
            raise ValueError(f'{where}: outside bounds')


def main():
    spec = json.loads((SOURCE / 'openapi.json').read_text())
    declared = spec['x-inventory']
    paths = spec['paths']
    assert declared['operations'] == sum(len(methods) for methods in paths.values())
    assert declared['paths'] == len(paths)
    assert sum(len(m) for p, m in paths.items() if not p.startswith('/api/v2/')) == 16
    assert declared['platform_operations'] == 54
    ids = []
    checks = 0
    for path, methods in paths.items():
        for method, operation in methods.items():
            ids.append(operation['operationId'])
            if not path.startswith('/api/v2/'):
                continue
            if method != 'get':
                assert any(p['in'] == 'header' and p['name'] == 'Idempotency-Key' and p['required'] for p in operation['parameters'])
            if '/admin/' not in path and '/auth/' not in path and not path.endswith('/capabilities'):
                assert operation['security'] == [{'MemberBearer': []}], path
            body = operation.get('requestBody', {}).get('content', {}).get('application/json')
            if body:
                validate(spec, body['schema'], body['example'], method + ' ' + path + ' request')
                checks += 1
            for code, response in operation['responses'].items():
                for content in response.get('content', {}).values():
                    if 'example' in content:
                        validate(spec, content['schema'], content['example'], method + ' ' + path + ' ' + code)
                        checks += 1
    assert len(ids) == len(set(ids)), 'Duplicate operationId'
    for filename in ['README.md', 'PLATFORM.md', 'SECURITY.md', 'DATA-MODEL.md', 'NOTIFICATION-EVENTS.md', 'CONFIGURATION.md', 'ACCEPTANCE-PLATFORM.md', 'BAYT-REFERENCE.md', 'CLIENT-READINESS.md', 'BACKEND-MESSAGE.txt', 'VERIFICATION.md', 'FLOWS.md']:
        assert (SOURCE / filename).stat().st_size > 300, filename
    print(f'Validated {checks} v2 request/response examples; {declared["operations"]} operations, {declared["paths"]} paths. No server contacted.')


if __name__ == '__main__':
    main()
