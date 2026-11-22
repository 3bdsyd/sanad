import 'job_geography.dart';
import 'job_regions_data.dart';

class JobRegion {
  const JobRegion(this.code, this.name, this.englishName, this.isoName);
  final String code, name, englishName, isoName;
}

List<JobRegion> regionsFor(String? country) => [
  for (final row
      in jobRegionData[countryFor(country)?.code] ?? <List<String>>[])
    JobRegion(row[0], row[1], row[2], row[3]),
]..sort((a, b) => a.name.compareTo(b.name));

String regionLabel(String? country) => switch (countryFor(country)?.code) {
  'AE' => 'الإمارة',
  'DE' || 'US' || 'AU' || 'BR' || 'MY' || 'SD' || 'DZ' || 'TN' => 'الولاية',
  'CA' || 'IE' || 'CH' => 'المقاطعة',
  'SA' || 'MA' || 'FR' || 'GB' || 'ID' => 'الإقليم',
  'VA' || 'XK' => 'مكان العمل',
  _ => 'المحافظة',
};

/// Only known aliases are canonicalized; never guess a legacy city's province.
String? canonicalRegion(String? country, String? value) {
  if (value == null || value.isEmpty) return null;
  final key = locationSearchKey(value);
  for (final region in regionsFor(country)) {
    if ([
      region.code,
      region.name,
      region.englishName,
      region.isoName,
    ].any((candidate) => locationSearchKey(candidate) == key)) {
      return region.name;
    }
  }
  return null;
}
