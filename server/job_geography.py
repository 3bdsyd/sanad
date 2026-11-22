"""Offline country/currency snapshot shared with Flutter; see geography-LICENSES.txt."""
import json
import re
from pathlib import Path

CATALOG = json.loads(Path(__file__).with_name('job_geography.json').read_text())
CURRENCIES = ['SYP', 'USD', 'AED', 'SAR']


def location_key(value):
    value = re.sub('[ً-ٰٟـ]', '', value.strip().lower())
    value = re.sub('[أإآٱ]', 'ا', value).replace('ى', 'ي')
    return re.sub(r'\s+', ' ', value)


COUNTRIES = {location_key(alias): country['name']
             for country in CATALOG['countries'] if country['code'] == 'SY'
             for alias in [country['code'], country['name'], *country['aliases']]}


def country_name(value):
    if not isinstance(value, str):
        raise ValueError('country')
    name = COUNTRIES.get(location_key(value))
    if not name:
        raise ValueError('country')
    return name
