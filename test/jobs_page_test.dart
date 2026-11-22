import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snad/features/jobs/data/api_client.dart';
import 'package:snad/features/jobs/domain/job_filters.dart';

Map<String, dynamic> _job(int id, {String status = 'published'}) => {
  'id': id,
  'title': 'محاسب $id',
  'company_name': 'شركة',
  'country': 'سوريا',
  'state': 'دمشق',
  'job_field': {'id': 9, 'name_ar': 'المحاسبة والتدقيق'},
  'job_type': 'دوام كامل',
  'work_type': 'في المقر',
  'experience': 'متوسطة',
  'description': 'وصف واضح للفرصة والمهام.',
  'requirements': 'خبرة سنتين',
  'contact': {'phone': '+963988123456', 'email': ''},
  'salary': {'currency': 'USD', 'period': 'شهرياً', 'min': 300, 'max': 500},
  'listing_duration_days': 30,
  'expires_at': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
  'is_active': true,
  'status': status,
  'created_at': DateTime.now().toIso8601String(),
};

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'jobsPage asks the server for one filtered page and reads meta',
    () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return _json({
          'success': true,
          'data': [_job(1), _job(2)],
          'meta': {
            'current_page': 2,
            'last_page': 5,
            'per_page': 24,
            'total': 110,
          },
        });
      });
      final api = SndApi(
        base: 'https://api.test',
        client: client,
        deviceId: 'd',
      );
      final page = await api.jobsPage(
        search: 'محاسب',
        filters: const JobFilters(
          country: 'SY',
          city: 'دمشق',
          category: 'المحاسبة والتدقيق',
          workMode: 'في مقر العمل',
          experience: 'متوسط',
          currency: 'USD',
          salaryPeriod: 'شهري',
          salaryOnly: true,
          sort: 'salary',
        ),
        categoryId: 9,
        page: 2,
      );
      expect(requested.path, '/api/filterjob');
      expect(requested.queryParameters, {
        'country': 'سوريا',
        'per_page': '24',
        'page': '2',
        'sort': 'salary',
        'search': 'محاسب',
        'job_field_id': '9',
        'state': 'دمشق',
        'work_type': 'في المقر',
        'experience': 'متوسطة',
        'currency': 'USD',
        'salary_period': 'شهرياً',
        'has_salary': '1',
      });
      expect(page.jobs.map((job) => job.id), ['1', '2']);
      expect(page.page, 2);
      expect(page.lastPage, 5);
      expect(page.total, 110);
      client.close();
    },
  );

  test('countJobs reads the total from a one-row page', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['per_page'], '1');
      return _json({
        'success': true,
        'data': [_job(1)],
        'meta': {
          'current_page': 1,
          'last_page': 37,
          'per_page': 1,
          'total': 37,
        },
      });
    });
    final api = SndApi(base: 'https://api.test', client: client, deviceId: 'd');
    expect(
      await api.countJobs(
        search: '',
        filters: const JobFilters(city: 'حلب'),
        categoryId: null,
      ),
      37,
    );
    client.close();
  });

  test(
    'favoriteJobs keeps available saved jobs from the favorites rows',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/favorites');
        expect(request.headers['X-Device-ID'], 'd');
        return _json({
          'success': true,
          'data': [
            {'id': 1, 'job_id': 7, 'job': _job(7)},
            {'id': 2, 'job_id': 8, 'job': null},
            {'id': 3, 'job_id': 9, 'job': _job(9, status: 'pending')},
          ],
        });
      });
      final api = SndApi(
        base: 'https://api.test',
        client: client,
        deviceId: 'd',
      );
      final jobs = await api.favoriteJobs();
      expect(jobs.map((job) => job.id), ['7']);
      client.close();
    },
  );
}
