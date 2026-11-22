import 'package:flutter/foundation.dart';

import 'job.dart';
import 'job_geography.dart';

const _unchanged = Object();

@immutable
class JobFilters {
  const JobFilters({
    String? country = 'SY',
    this.city,
    this.category,
    this.workType,
    this.workMode,
    this.experience,
    this.salaryOnly = false,
    this.minSalary,
    this.currency,
    this.salaryPeriod,
    this.sort = 'newest',
  }) : country = 'SY';

  /// Product scope is Syria, including restored filters from older builds.
  final String? country;
  final String? city;
  final String? category;
  final String? workType;
  final String? workMode;
  final String? experience;
  final bool salaryOnly;
  final int? minSalary;
  final String? currency;
  final String? salaryPeriod;
  final String sort;
  String get locationLabel => [countryLabel(country), ?city].join(' · ');

  Map<String, dynamic> toJson() => {
    'country': country,
    'city': city,
    'category': category,
    'workType': workType,
    'workMode': workMode,
    'experience': experience,
    'salaryOnly': salaryOnly,
    'minSalary': minSalary,
    'currency': currency,
    'salaryPeriod': salaryPeriod,
    'sort': sort,
  };
  factory JobFilters.fromJson(Map<String, dynamic> json) {
    String? text(String key, {int maxLength = 80}) {
      final value = json[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.length > maxLength) return null;
      return trimmed;
    }

    return JobFilters(
      country: 'SY',
      city:
          (text('country') == null || countryFor(text('country'))?.code == 'SY')
          ? text('city', maxLength: 100)
          : null,
      category: text('category'),
      workType: text('workType'),
      workMode: text('workMode'),
      experience: text('experience'),
      salaryOnly: json['salaryOnly'] == true,
      currency: jobCurrencyNames.containsKey(text('currency'))
          ? text('currency')
          : null,
      salaryPeriod:
          jobSalaryPeriods.contains(normalizeSalaryPeriod(text('salaryPeriod')))
          ? normalizeSalaryPeriod(text('salaryPeriod'))
          : null,
      minSalary:
          json['minSalary'] is int &&
              json['minSalary'] >= 0 &&
              json['minSalary'] <= 1000000000
          ? json['minSalary'] as int
          : null,
      sort: json['sort'] == 'salary' ? 'salary' : 'newest',
    );
  }

  int get activeCount => [
    city,
    category,
    workType,
    workMode,
    experience,
    currency,
    salaryPeriod,
    if (salaryOnly) true,
    if (minSalary != null) minSalary,
  ].where((value) => value != null).length;

  JobFilters copyWith({
    Object? country = _unchanged,
    Object? city = _unchanged,
    Object? category = _unchanged,
    Object? workType = _unchanged,
    Object? workMode = _unchanged,
    Object? experience = _unchanged,
    bool? salaryOnly,
    Object? minSalary = _unchanged,
    Object? currency = _unchanged,
    Object? salaryPeriod = _unchanged,
    String? sort,
  }) => JobFilters(
    country: identical(country, _unchanged) ? this.country : country as String?,
    city: identical(city, _unchanged)
        ? (!identical(country, _unchanged) && country != this.country
              ? null
              : this.city)
        : city as String?,
    category: identical(category, _unchanged)
        ? this.category
        : category as String?,
    workType: identical(workType, _unchanged)
        ? this.workType
        : workType as String?,
    workMode: identical(workMode, _unchanged)
        ? this.workMode
        : workMode as String?,
    experience: identical(experience, _unchanged)
        ? this.experience
        : experience as String?,
    salaryOnly: salaryOnly ?? this.salaryOnly,
    minSalary: identical(minSalary, _unchanged)
        ? this.minSalary
        : minSalary as int?,
    currency: identical(currency, _unchanged)
        ? this.currency
        : currency as String?,
    salaryPeriod: identical(salaryPeriod, _unchanged)
        ? this.salaryPeriod
        : salaryPeriod as String?,
    sort: sort ?? this.sort,
  );

  bool matches(Job job, String query) => _matches(job, _searchWords(query));

  static List<String> _searchWords(String query) => normalizeSearch(
    query,
  ).split(' ').where((word) => word.isNotEmpty).toList();

  bool _matches(Job job, List<String> words) {
    if (!job.isAvailable) return false;
    if (country != null &&
        countryFor(country)?.code != countryFor(job.country)?.code) {
      return false;
    }
    if (city != null && !matchesJobCity(job, city!)) {
      return false;
    }
    if (category != null && category != job.category) return false;
    if (workType != null && workType != job.workType) return false;
    if (workMode != null &&
        workModeApiValue(workMode) != workModeApiValue(job.workMode)) {
      return false;
    }
    if (experience != null) {
      if (experienceGroup(experience!) != experienceGroup(job.experience)) {
        return false;
      }
    }
    if (currency != null && currency != job.currency) return false;
    if (salaryPeriod != null && salaryPeriod != job.salaryPeriod) return false;
    if (salaryOnly && !job.hasSalary) return false;
    // A numeric salary has no comparable meaning without its currency.
    if (minSalary != null &&
        currency != null &&
        salaryPeriod != null &&
        ((job.salaryMax ?? job.salaryMin) == null ||
            (job.salaryMax ?? job.salaryMin)! < minSalary!)) {
      return false;
    }
    if (words.isEmpty) return true;
    final haystack = _searchText[job] ??= normalizeSearch(
      [
        job.title,
        job.company,
        countryLabel(job.country),
        job.city,
        job.category,
        job.workType,
        job.workMode,
        job.description,
        ...job.requirements,
      ].join(' '),
    );
    return words.every(haystack.contains);
  }

  /// Normalizing every description is costly; jobs are immutable, so each
  /// instance keeps its searchable text for the lifetime of the object.
  static final _searchText = Expando<String>('searchText');

  List<Job> apply(Iterable<Job> jobs, String query) {
    final words = _searchWords(query);
    final result = jobs.where((job) => _matches(job, words)).toList();
    result.sort((a, b) {
      // Never rank dissimilar currencies or salary periods numerically.
      if (sort == 'salary' && currency != null && salaryPeriod != null) {
        final comparison = (b.salaryMax ?? b.salaryMin ?? -1).compareTo(
          a.salaryMax ?? a.salaryMin ?? -1,
        );
        if (comparison != 0) return comparison;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }
}

bool matchesJobCity(Job job, String city) {
  final selected = locationSearchKey(city), place = locationSearchKey(job.city);
  if (selected == place) return true;
  if (countryFor(job.country)?.code == 'SY' &&
      selected == locationSearchKey(governorateOf(job.city) ?? '')) {
    return true;
  }
  return place.startsWith('$selected،') ||
      place.startsWith('$selected,') ||
      place.startsWith('$selected -') ||
      place.startsWith('$selected ');
}

String normalizeSearch(String value) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  var normalized = value
      .toLowerCase()
      .replaceAll(RegExp('[ً-ٰٟـ]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
  for (var index = 0; index < 10; index++) {
    normalized = normalized
        .replaceAll(arabicDigits[index], '$index')
        .replaceAll(persianDigits[index], '$index');
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}
