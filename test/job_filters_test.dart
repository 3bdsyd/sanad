import 'package:flutter_test/flutter_test.dart';

import 'package:snad/features/jobs/domain/job.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

Job _job({
  String id = '1',
  String title = 'مطور تطبيقات',
  String company = 'شركة النواة',
  String city = 'دمشق',
  String category = 'تقنية',
  String workType = 'دوام كامل',
  String workMode = 'عن بُعد',
  String experience = 'متوسط',
  int? salaryMin = 700,
  int? salaryMax = 900,
  String currency = 'USD',
  String salaryPeriod = 'شهري',
  String status = 'published',
  DateTime? createdAt,
  DateTime? expiresAt,
  List<String> requirements = const ['خبرة في Dart وFlutter'],
}) => Job(
  id: id,
  title: title,
  company: company,
  city: city,
  category: category,
  workType: workType,
  workMode: workMode,
  experience: experience,
  salaryMin: salaryMin,
  salaryMax: salaryMax,
  currency: currency,
  salaryPeriod: salaryPeriod,
  description: 'تطوير تطبيقات عربية.',
  requirements: requirements,
  createdAt: createdAt ?? DateTime.utc(2035, 1, 1),
  expiresAt: expiresAt ?? DateTime.utc(2035, 2, 1),
  status: status,
);

void main() {
  test('Arabic search normalizes hamza, diacritics, and Arabic digits', () {
    expect(normalizeSearch('إِدارة ١٢٣'), 'اداره 123');
    final jobs = [
      _job(title: 'فني 123', requirements: const ['خبرة ميدانية']),
    ];
    expect(JobFilters().apply(jobs, 'فَنِّي ١٢٣'), hasLength(1));
    expect(JobFilters().apply(jobs, 'خبرة ميدانية'), hasLength(1));
    expect(JobFilters().apply(jobs, 'فني مبيعات'), isEmpty);
  });

  test(
    'all discovery filters combine and reject unavailable opportunities',
    () {
      final matching = _job();
      final other = _job(
        id: '2',
        title: 'مصمم جرافيك',
        city: 'حلب',
        category: 'تصميم',
        workType: 'عمل حر',
        workMode: 'من المكتب',
        experience: 'مبتدئ',
      );
      final pending = _job(id: '3', status: 'pending');
      final rejected = _job(id: '4', status: 'rejected');
      final expired = _job(id: '5', expiresAt: DateTime.utc(2020));
      final filters = JobFilters(
        city: 'دمشق',
        category: 'تقنية',
        workType: 'دوام كامل',
        workMode: 'عن بُعد',
        experience: 'متوسط',
        currency: 'USD',
        salaryPeriod: 'شهري',
        salaryOnly: true,
        minSalary: 650,
      );

      expect(filters.apply([matching, other, pending, rejected, expired], ''), [
        matching,
      ]);
      expect(filters.apply([matching], 'Flutter مدينة'), isEmpty);
    },
  );

  test('salary threshold compares only the selected currency and period', () {
    final jobs = [
      _job(id: 'usd-low', salaryMin: 600, salaryMax: 800),
      _job(
        id: 'usd-high',
        salaryMin: 900,
        salaryMax: 1100,
        createdAt: DateTime.utc(2034),
      ),
      _job(
        id: 'syp',
        currency: 'SYP',
        salaryMin: 900000,
        salaryMax: 1200000,
        createdAt: DateTime.utc(2033),
      ),
      _job(
        id: 'hourly',
        salaryPeriod: 'بالساعة',
        createdAt: DateTime.utc(2032),
      ),
      _job(id: 'unlisted', salaryMin: null, salaryMax: null),
    ];
    final filters = JobFilters(
      currency: 'USD',
      salaryPeriod: 'شهري',
      salaryOnly: true,
      minSalary: 850,
      sort: 'salary',
    );

    expect(filters.apply(jobs, '').map((job) => job.id), ['usd-high']);
    final sameCurrencyAndPeriod = JobFilters(
      currency: 'USD',
      salaryPeriod: 'شهري',
    ).apply(jobs, '');
    expect(sameCurrencyAndPeriod, hasLength(3));
    expect(
      sameCurrencyAndPeriod.map((job) => job.id),
      containsAll(['unlisted', 'usd-low', 'usd-high']),
    );
  });

  test('sort by salary stays within the selected currency and period', () {
    final newer = _job(id: 'newer', salaryMax: 800);
    final higher = _job(
      id: 'higher',
      salaryMax: 1200,
      createdAt: DateTime.utc(2034),
    );
    final differentCurrency = _job(
      id: 'syp',
      currency: 'SYP',
      salaryMax: 900000,
      createdAt: DateTime.utc(2033),
    );

    expect(
      JobFilters(
        currency: 'USD',
        salaryPeriod: 'شهري',
        sort: 'salary',
      ).apply([newer, higher, differentCurrency], '').map((job) => job.id),
      ['higher', 'newer'],
    );
  });

  test(
    'API status aliases and terminal states map to correct availability',
    () {
      Map<String, dynamic> response({
        String? status,
        bool? active,
        String expires = '2035-01-31T00:00:00Z',
      }) => {
        'id': 17,
        'title': 'مطور تطبيقات',
        'company_name': 'شركة النواة',
        'state': 'دمشق',
        'job_field': {'name_ar': 'تقنية'},
        'job_type': 'دوام كامل',
        'work_type': 'عن بُعد',
        'experience': 'متوسط',
        'description': 'وصف فرصة صالح للاختبار.',
        'requirements': 'خبرة Dart، Flutter',
        'created_at': '2035-01-01T00:00:00Z',
        'expires_at': expires,
        'status': ?status,
        'is_active': ?active,
      };

      for (final status in ['published', 'active', 'approved', ' ACTIVE ']) {
        expect(Job.fromApi(response(status: status)).isAvailable, isTrue);
      }
      for (final status in ['pending', 'rejected', 'expired', 'withdrawn']) {
        expect(Job.fromApi(response(status: status)).isAvailable, isFalse);
      }
      expect(Job.fromApi(response(active: false)).status, 'inactive');
      expect(Job.fromApi(response(active: true)).isAvailable, isTrue);
      expect(
        Job.fromApi(response(expires: '2020-01-01T00:00:00Z')).isAvailable,
        isFalse,
      );
      expect(Job.fromApi(response()).requirements, ['خبرة Dart', 'Flutter']);
    },
  );

  test('API taxonomy values normalize to visible quick-filter labels', () {
    final job = Job.fromApi({
      'id': 91,
      'title': 'موظف مؤقت',
      'company_name': 'جهة اختبار',
      'country': 'سوريا',
      'state': 'حمص ',
      'job_field': {'name_ar': 'مطاعم '},
      'job_type': 'دوام كامل  ',
      'work_type': 'في المقر ',
      'experience': 'غير مطلوبة  ',
      'currency': ' usd ',
      'salary_period': 'شهري ',
      'description': 'فرصة اختبار.',
      'created_at': '2035-01-01T00:00:00Z',
      'expires_at': '2035-01-31T00:00:00Z',
    });

    expect(job.city, 'حمص');
    expect(job.category, 'مطاعم');
    expect(job.workType, 'دوام كامل');
    expect(job.workMode, 'في مقر العمل');
    expect(job.experience, 'غير مطلوبة');
    expect(job.currency, 'USD');
    expect(job.salaryPeriod, 'شهري');
    expect(
      JobFilters(
        city: 'حمص',
        category: 'مطاعم',
        workType: 'دوام كامل',
        workMode: 'من المكتب',
        experience: 'بدون خبرة',
      ).apply([job], ''),
      [job],
    );
  });

  test('API salary periods normalize and retain matching offers', () {
    Job fromPeriod(String id, String period) => Job.fromApi({
      'id': id,
      'title': 'مهنة اختبار',
      'company_name': 'جهة اختبار',
      'state': 'دمشق',
      'job_field': {'name_ar': 'تقنية'},
      'job_type': 'دوام كامل',
      'work_type': 'في المقر',
      'experience': 'غير مطلوبة',
      'salary': {'min': 1000, 'max': 1500, 'currency': 'SYP', 'period': period},
      'description': 'وصف صالح للاختبار.',
      'created_at': '2035-01-01T00:00:00Z',
      'expires_at': '2035-01-31T00:00:00Z',
    });
    final monthly = fromPeriod('1', 'شهرياً');
    final weekly = fromPeriod('2', 'أسبوعياً');
    final daily = fromPeriod('3', 'يومياً');

    expect(monthly.salaryPeriod, 'شهري');
    expect(monthly.salaryPeriodLabel, 'شهرياً');
    expect(weekly.salaryPeriod, 'أسبوعي');
    expect(weekly.salaryPeriodLabel, 'أسبوعياً');
    expect(daily.salaryPeriod, 'يومي');
    expect(daily.salaryPeriodLabel, 'يومياً');
    expect(_job(salaryMin: null, salaryMax: null).salaryPeriodLabel, isNull);
    expect(JobFilters(salaryPeriod: 'شهري').apply([monthly], ''), [monthly]);
    expect(JobFilters(salaryPeriod: 'أسبوعي').apply([weekly], ''), [weekly]);
    expect(JobFilters(salaryPeriod: 'يومي').apply([daily], ''), [daily]);
  });

  test('experience labels clarify API values and group free-form text', () {
    final required = _job(id: 'required', experience: 'مطلوبة');
    final detailed = _job(
      id: 'detailed',
      experience: 'سنة على الأقل في مجال العمل',
    );
    final none = _job(id: 'none', experience: 'غير مطلوبة');

    expect(required.experienceLabel, 'يشترط وجود خبرة');
    expect(detailed.experienceLabel, 'يشترط وجود خبرة');
    expect(detailed.experienceDetail, 'سنة على الأقل في مجال العمل');
    expect(none.experienceLabel, 'لا يشترط وجود خبرة');
    expect(
      JobFilters(experience: 'مطلوبة').apply([required, detailed, none], ''),
      [required, detailed],
    );
  });

  test('experience values sent to the live API use clear supported terms', () {
    expect(experienceApiValue('بدون خبرة'), 'غير مطلوبة');
    expect(experienceApiValue('مطلوبة'), 'مطلوبة');
    expect(experienceApiValue('متوسط'), 'متوسطة');
    expect(workModeApiValue('في مقر العمل'), 'في المقر');
    expect(workModeApiValue('من المكتب'), 'في المقر');
    expect(workModeApiValue('عن بُعد'), 'عن بُعد');
  });
  test('free-text API places match the governorate filter', () {
    expect(governorateOf('دمشق، المزة'), 'دمشق');
    expect(governorateOf('دمشق ، أبو رمانة'), 'دمشق');
    expect(governorateOf('دمشق – جديدة الشيباني'), 'دمشق');
    expect(governorateOf('ريف دمشق'), 'ريف دمشق');
    expect(governorateOf(' حمص '), 'حمص');
    expect(governorateOf('ريموتلي'), isNull);
    expect(governorateOf('.'), isNull);
    expect(governorateOf('حلبون'), isNull);

    final exact = _job(id: '1', city: 'دمشق');
    final district = _job(id: '2', city: 'دمشق، المزة');
    final countryside = _job(id: '3', city: 'ريف دمشق');
    expect(
      const JobFilters(
        city: 'دمشق',
      ).apply([exact, district, countryside], '').map((job) => job.id),
      ['1', '2'],
    );
    expect(
      const JobFilters(
        city: 'ريف دمشق',
      ).apply([exact, district, countryside], '').map((job) => job.id),
      ['3'],
    );
  });

  test('Arabic currency labels from the API normalize to codes', () {
    expect(normalizeCurrency('ليرة سورية'), 'SYP');
    expect(normalizeCurrency(' usd '), 'USD');
    expect(normalizeCurrency('دولار'), 'USD');
    expect(normalizeCurrency(null), 'SYP');
    final job = Job.fromApi({
      'id': 92,
      'title': 'محاسب',
      'company_name': 'جهة اختبار',
      'state': 'دمشق',
      'job_type': 'دوام كامل',
      'work_type': 'في المقر',
      'experience': 'مطلوبة',
      'salary': {
        'currency': 'ليرة سورية',
        'period': 'شهري',
        'min': 1000000,
        'max': null,
      },
      'description': 'فرصة اختبار.',
      'created_at': '2035-01-01T00:00:00Z',
      'expires_at': '2035-01-31T00:00:00Z',
    });
    expect(job.currency, 'SYP');
    expect(
      const JobFilters(currency: 'SYP', salaryPeriod: 'شهري').apply([job], ''),
      [job],
    );
  });
}
