import 'package:flutter_test/flutter_test.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';
import 'package:snad/features/jobs/domain/job_geography.dart';

void main() {
  test(
    'discovery and publishing offer Syria and original backend currencies',
    () {
      expect(availableJobCountries.map((c) => c.code), ['SY']);
      expect(jobCurrencyNames.keys, ['SYP', 'USD', 'AED', 'SAR']);
    },
  );
  test('restored foreign and all-country searches cannot escape Syria', () {
    final restored = JobFilters.fromJson({'country': 'DE', 'city': 'Berlin'});
    expect(restored.country, 'SY');
    expect(restored.city, isNull);
    expect(const JobFilters().copyWith(country: null).country, 'SY');
    expect(const JobFilters(country: 'AE').country, 'SY');
    expect(const JobFilters().activeCount, 0);
    expect(JobFilters.fromJson({'city': 'دمشق'}).city, 'دمشق');
  });
}
