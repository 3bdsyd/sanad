import 'package:flutter_test/flutter_test.dart';
import 'package:snad/features/jobs/domain/job.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';
import 'package:snad/features/jobs/domain/job_geography.dart';

Job sampleJob(String country, String city, {String currency = 'USD'}) => Job(
  id: '$country-$city',
  title: 'محاسب',
  company: 'جهة تجريبية',
  country: country,
  city: city,
  category: 'تقنية',
  workType: 'دوام كامل',
  workMode: 'عن بُعد',
  experience: 'متوسط',
  description: 'وصف فرصة تجريبية فقط',
  requirements: const [],
  salaryMin: 100,
  currency: currency,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2035),
);

void main() {
  test(
    'offline catalog covers countries across regions with stable aliases',
    () {
      expect(jobCountries.length, greaterThanOrEqualTo(249));
      expect(
        jobCountries.map((c) => c.code).toSet().length,
        jobCountries.length,
      );
      for (final code in [
        'SY',
        'AE',
        'EG',
        'MA',
        'DE',
        'US',
        'CA',
        'BR',
        'JP',
        'AU',
        'ZA',
        'IN',
      ]) {
        final country = countryFor(code)!;
        expect(country.name, isNotEmpty);
        expect(countryFor(country.name), same(country));
        expect(countryFor(country.englishName), same(country));
        if (code == 'SY') expect(jobCurrencyNames, contains(country.currency));
      }
      expect(countryFor('الإمارات العربية المتحدة')?.code, 'AE');
      expect(countryFor('سورية')?.code, 'SY');
    },
  );

  test('country and city cannot mix cross-border results or saved filters', () {
    final jobs = [
      sampleJob('سوريا', 'طرابلس'),
      sampleJob('لبنان', 'طرابلس'),
      sampleJob('ليبيا', 'طرابلس'),
    ];
    expect(const JobFilters().apply(jobs, ''), hasLength(1));
    expect(
      const JobFilters(
        country: 'LB',
        city: 'طرابلس',
      ).apply(jobs, '').single.country,
      'سوريا',
    );
    const filters = JobFilters(country: 'SY', city: 'دمشق', category: 'تقنية');
    final changed = filters.copyWith(country: 'AE');
    expect(changed.city, isNull);
    expect(changed.category, 'تقنية');
    expect(JobFilters.fromJson(changed.toJson()).country, 'SY');
    expect(JobFilters.fromJson({'city': 'دمشق'}).country, 'SY');
    expect(JobFilters.fromJson(const JobFilters().toJson()).country, 'SY');
    final longCity = List.filled(100, 'أ').join();
    expect(
      JobFilters.fromJson(
        JobFilters(country: 'AE', city: longCity).toJson(),
      ).city,
      longCity,
    );
  });

  test(
    'foreign city search and salary labels retain their country and currency',
    () {
      final egypt = sampleJob('مصر', 'الإسكندرية', currency: 'EGP');
      final uae = sampleJob(
        'United Arab Emirates',
        'دبي، المارينا',
        currency: 'AED',
      );
      expect(
        const JobFilters(country: 'AE', city: 'دبي').apply([egypt, uae], ''),
        isEmpty,
      );
      expect(const JobFilters().apply([egypt, uae], 'مصر'), isEmpty);
      expect(egypt.locationLabel, contains('مصر'));
      expect(egypt.salaryLabel, contains('EGP'));
      expect(egypt.salaryLabel, isNot(contains('ل.س')));
      expect(
        JobFilters.fromJson({'country': 'EG', 'currency': 'EGP'}).currency,
        isNull,
      );
      expect(normalizeCurrency('TRY'), 'TRY');
    },
  );

  test('international and national phone prefixes are country-specific', () {
    expect(
      normalizeContactPhone('٠٩٤٤١٢٣٤٥٦', countryFor('SY')!),
      '+963944123456',
    );
    expect(
      normalizeContactPhone('050 123 4567', countryFor('AE')!),
      '+971501234567',
    );
    expect(
      normalizeContactPhone('02 12345678', countryFor('IT')!),
      '+390212345678',
    );
    expect(
      normalizeContactPhone('06 1 2345678', countryFor('HU')!),
      '+3612345678',
    );
    expect(
      normalizeContactPhone('+49 151 23456789', countryFor('AE')!),
      '+4915123456789',
    );
    expect(
      normalizeContactPhone('00971 50 1234567', countryFor('SY')!),
      '+971501234567',
    );
  });
}
