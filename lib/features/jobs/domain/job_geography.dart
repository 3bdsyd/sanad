import 'job_geography_data.dart';

// Keep the original backend-supported salary currencies.
const jobCurrencyNames = <String, String>{
  'SYP': 'ليرة سورية',
  'USD': 'دولار أمريكي',
  'AED': 'درهم إماراتي',
  'SAR': 'ريال سعودي',
};

class JobCountry {
  JobCountry(this.code, List<String> values)
    : name = values[0],
      englishName = values[1],
      currency = values[2],
      dialCode = values[3].isEmpty ? '' : '+${values[3]}',
      nationalPrefix = values[4],
      aliases = List.unmodifiable(values.skip(5));

  final String code, name, englishName, currency, dialCode, nationalPrefix;
  final List<String> aliases;
  String get flag =>
      String.fromCharCodes(code.codeUnits.map((c) => 0x1f1e6 + c - 65));
  String? get flagAsset => code == 'SY' ? 'assets/images/flags/sy.png' : null;
  String get isoCode => code;
}

final jobCountries = List<JobCountry>.unmodifiable(
  [
    for (final entry in jobCountryData.entries)
      JobCountry(entry.key, entry.value),
  ]..sort((a, b) => a.name.compareTo(b.name)),
);

/// Product selection for job discovery and publication. The full catalog stays
/// available for parsing existing jobs and international contact numbers.
const supportedJobCountryCodes = <String>{'SY'};
final availableJobCountries = List<JobCountry>.unmodifiable(
  supportedJobCountryCodes.map(
    (code) => jobCountries.firstWhere((country) => country.code == code),
  ),
);

String locationSearchKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[ً-ٰٟـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ');

final _countriesByAlias = <String, JobCountry>{
  for (final country in jobCountries)
    for (final alias in [
      country.code,
      country.name,
      country.englishName,
      ...country.aliases,
    ])
      locationSearchKey(alias): country,
};

JobCountry? countryFor(String? value) =>
    value == null ? null : _countriesByAlias[locationSearchKey(value)];
String countryLabel(String? value) =>
    countryFor(value)?.name ?? value?.trim() ?? 'كل البلدان';
String currencyLabel(String value) =>
    '${jobCurrencyNames[value] ?? value} ($value)';

/// International numbers are preserved. National prefixes differ by country;
/// notably an Italian leading zero is part of the number and must be retained.
String normalizeContactPhone(String raw, JobCountry country) {
  var value = raw.trim();
  for (var i = 0; i < 10; i++) {
    value = value
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
        .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
  }
  value = value.replaceAll(RegExp(r'[\s()\-]'), '');
  if (value.startsWith('+')) return value;
  if (value.startsWith('00')) return '+${value.substring(2)}';
  if (!RegExp(r'^\d+$').hasMatch(value)) return value;
  final prefix = country.nationalPrefix;
  if (prefix.isNotEmpty && value.startsWith(prefix)) {
    value = value.substring(prefix.length);
  }
  return '${country.dialCode}$value';
}
