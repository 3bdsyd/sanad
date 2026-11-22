import 'package:flutter/foundation.dart';
import 'job_geography.dart';

const jobCities = <String>[
  'دمشق',
  'ريف دمشق',
  'حلب',
  'حمص',
  'حماة',
  'اللاذقية',
  'طرطوس',
  'إدلب',
  'درعا',
  'السويداء',
  'القنيطرة',
  'دير الزور',
  'الرقة',
  'الحسكة',
];

/// The live API stores free-text places such as «دمشق، المزة»; filters and
/// pickers use the governorate it starts with. Unknown places return null.
String? governorateOf(String place) {
  final value = place.trim();
  for (final city in jobCities) {
    if (value == city) return city;
  }
  for (final city in jobCities) {
    if (value.startsWith(city) &&
        !_arabicLetter.hasMatch(value.substring(city.length))) {
      return city;
    }
  }
  return null;
}

final _arabicLetter = RegExp(r'^[\u0621-\u064A]');

/// Some API rows carry the currency as an Arabic label instead of its code.
String normalizeCurrency(Object? value) {
  final text = value?.toString().trim() ?? '';
  final upper = text.toUpperCase();
  if (jobCurrencies.contains(upper)) return upper;
  for (final entry in jobCurrencyNames.entries) {
    if (locationSearchKey(entry.value) == locationSearchKey(text)) {
      return entry.key;
    }
  }
  if (text.contains('ليرة') || text == 'ل.س') return 'SYP';
  if (text.contains('دولار') || text == r'$') return 'USD';
  if (text.contains('درهم')) return 'AED';
  if (text.contains('ريال')) return 'SAR';
  return upper.isEmpty ? 'SYP' : upper;
}

const jobCategories = <String>[
  'تقنية',
  'تصميم',
  'تسويق',
  'مبيعات',
  'مطاعم وضيافة',
  'حِرف ومهن',
  'إدارة ومحاسبة',
  'تعليم',
  'صحة',
];
const jobWorkTypes = <String>['دوام كامل', 'دوام جزئي', 'عمل حر', 'تدريب'];
const jobWorkModes = <String>['في مقر العمل', 'عن بُعد', 'هجين'];
const jobExperienceLevels = <String>[
  'بدون خبرة',
  'مطلوبة',
  'يفضل الخبرة',
  'مبتدئ',
  'متوسط',
  'خبير',
];
const jobExperienceFilterLevels = jobExperienceLevels;
const jobSalaryPeriods = <String>[
  'شهري',
  'أسبوعي',
  'يومي',
  'بالساعة',
  'للمشروع',
];

String normalizeSalaryPeriod(Object? value) {
  final period = value?.toString().trim() ?? '';
  return switch (period) {
    'شهرياً' || 'شهريًا' => 'شهري',
    'أسبوعياً' ||
    'أسبوعيًا' ||
    'اسبوعي' ||
    'اسبوعياً' ||
    'اسبوعيًا' => 'أسبوعي',
    'يومياً' || 'يوميًا' => 'يومي',
    _ => period,
  };
}

String salaryPeriodApiValue(String value) =>
    switch (normalizeSalaryPeriod(value)) {
      'شهري' => 'شهرياً',
      'أسبوعي' => 'أسبوعياً',
      'يومي' => 'يومياً',
      final period => period,
    };

String workModeApiValue(Object? value) {
  final mode = value?.toString().trim() ?? '';
  return switch (mode) {
    'في مقر العمل' ||
    'من المكتب' ||
    'في المكتب' ||
    'من المقر' ||
    'في المقر' => 'في المقر',
    'عن بعد' || 'عن بُعد' => 'عن بُعد',
    _ => mode,
  };
}

String experienceGroup(Object? raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  if (value.isEmpty) return 'unknown';
  if (const {'بدون خبرة', 'غير مطلوبة', 'لا يشترط وجود خبرة'}.contains(value)) {
    return 'none';
  }
  if (value.contains('يفضل') || value.contains('تفضل')) return 'preferred';
  if (value == 'junior' || value.contains('مبتدئ')) return 'beginner';
  if (value.contains('متوسط')) return 'intermediate';
  if (value.contains('خبير')) return 'expert';
  return 'required';
}

String experienceDisplayLabel(Object? raw) => switch (experienceGroup(raw)) {
  'unknown' => 'غير محددة',
  'none' => 'لا يشترط وجود خبرة',
  'preferred' => 'تُفضّل الخبرة',
  'beginner' => 'خبرة مبتدئة',
  'intermediate' => 'خبرة متوسطة',
  'expert' => 'خبرة متقدمة',
  _ => 'يشترط وجود خبرة',
};

String experienceApiValue(String value) => switch (value.trim()) {
  'بدون خبرة' || 'لا يشترط وجود خبرة' => 'غير مطلوبة',
  'مطلوبة' || 'خبرة مطلوبة' || 'يشترط وجود خبرة' => 'مطلوبة',
  'يفضل الخبرة' || 'تُفضّل الخبرة' => 'يفضل الخبرة',
  'متوسط' || 'خبرة متوسطة' => 'متوسطة',
  'خبير' || 'خبرة متقدمة' => 'خبير',
  final experience => experience,
};
final jobCurrencies = List<String>.unmodifiable(jobCurrencyNames.keys);

String _apiWorkMode(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (const {
    'في مقر العمل',
    'في المقر',
    'من المقر',
    'في المكتب',
    'من المكتب',
  }.contains(text)) {
    return 'في مقر العمل';
  }
  if (const {'عن بعد', 'عن بُعد'}.contains(text)) return 'عن بُعد';
  return text;
}

@immutable
class Job {
  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.city,
    required this.category,
    required this.workType,
    required this.workMode,
    required this.experience,
    required this.description,
    required this.requirements,
    required this.createdAt,
    required this.expiresAt,
    this.phone = '',
    this.email = '',
    this.companyWebsite = '',
    this.salaryMin,
    this.salaryMax,
    this.currency = 'SYP',
    this.salaryPeriod = 'شهري',
    this.status = 'published',
    this.isDemo = false,
    this.employerKey,
    this.country = 'سوريا',
    this.jobFieldId,
    this.viewsCount = 0,
    this.acceptsApplications = false,
    this.rejectionReason = '',
  });

  final String id;
  final String title;
  final String company;
  final String city;
  final String category;
  final String workType;
  final String workMode;
  final String experience;
  final int? salaryMin;
  final int? salaryMax;
  final String currency;
  final String salaryPeriod;
  final String description;
  final List<String> requirements;
  final String phone;
  final String email;
  final String companyWebsite;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;
  final bool isDemo;
  final String? employerKey;
  final String country;
  final int? jobFieldId;
  final int viewsCount;
  final bool acceptsApplications;
  final String rejectionReason;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
  String get locationLabel {
    final place = city.trim();
    final nation = countryLabel(country);
    if (nation.isEmpty || nation == place) return place;
    return '$place · $nation';
  }

  bool get isAvailable => status == 'published' && !isExpired;
  bool get hasSalary => salaryMin != null || salaryMax != null;
  String get experienceLabel => experienceDisplayLabel(experience);
  String? get experienceDetail {
    const standard = {
      'بدون خبرة',
      'غير مطلوبة',
      'لا يشترط وجود خبرة',
      'مطلوبة',
      'خبرة مطلوبة',
      'يشترط وجود خبرة',
      'يفضل الخبرة',
      'تُفضّل الخبرة',
      'مبتدئ',
      'junior',
      'متوسط',
      'متوسطة',
      'خبير',
    };
    final value = experience.trim();
    return value.isEmpty || standard.contains(value.toLowerCase())
        ? null
        : value;
  }

  String? get salaryPeriodLabel {
    if (!hasSalary) return null;
    final period = normalizeSalaryPeriod(salaryPeriod);
    return switch (period) {
      'شهري' => 'شهرياً',
      'أسبوعي' => 'أسبوعياً',
      'يومي' => 'يومياً',
      'بالساعة' => 'بالساعة',
      'للمشروع' => 'للمشروع',
      '' || 'غير محدد' => hasSalary ? 'الفترة غير محددة' : null,
      _ => 'تفاصيل الراتب: $period',
    };
  }

  String get currencyLabel => switch (currency) {
    'SYP' => 'ل.س',
    'USD' => '\$',
    'AED' => 'د.إ',
    'SAR' => 'ر.س',
    _ => currency,
  };
  String get salaryLabel {
    if (!hasSalary) return 'الراتب عند التواصل';
    final low = salaryMin;
    final high = salaryMax;
    if (low != null && high != null && low != high) {
      return '${formatAmount(low)} – ${formatAmount(high)} $currencyLabel';
    }
    return '${low == null
            ? 'حتى '
            : high == null
            ? 'من '
            : ''}'
        '${formatAmount(low ?? high!)} $currencyLabel';
  }

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String,
    title: json['title'] as String,
    company: json['company'] as String,
    city: json['city'] as String,
    category: json['category'] as String,
    workType: json['workType'] as String,
    workMode: json['workMode'] as String,
    experience: json['experience'] as String,
    salaryMin: (json['salaryMin'] as num?)?.toInt(),
    salaryMax: (json['salaryMax'] as num?)?.toInt(),
    currency: normalizeCurrency(json['currency']),
    salaryPeriod: normalizeSalaryPeriod(json['salaryPeriod'] ?? 'شهري'),
    description: json['description'] as String,
    requirements: List<String>.unmodifiable(
      (json['requirements'] as List<dynamic>? ?? []).cast<String>(),
    ),
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    companyWebsite: json['companyWebsite'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    status: json['status'] as String? ?? 'published',
    isDemo: json['isDemo'] as bool? ?? false,
    employerKey: json['employerKey'] as String?,
    country: json['country'] as String? ?? 'سوريا',
    jobFieldId: (json['jobFieldId'] as num?)?.toInt(),
    viewsCount: (json['viewsCount'] as num?)?.toInt() ?? 0,
    acceptsApplications: json['acceptsApplications'] == true,
    rejectionReason: json['rejectionReason'] as String? ?? '',
  );

  /// Accepts the public catalog shape and the flatter favorite/owner shape.
  factory Job.fromApi(Map<String, dynamic> json, {bool fromCatalog = false}) {
    final field = json['job_field'];
    final fieldMap = field is Map
        ? Map<String, dynamic>.from(field)
        : const <String, dynamic>{};
    final contact = json['contact'];
    final contactMap = contact is Map
        ? Map<String, dynamic>.from(contact)
        : const <String, dynamic>{};
    final salary = json['salary'];
    final salaryMap = salary is Map
        ? Map<String, dynamic>.from(salary)
        : const <String, dynamic>{};
    final created = DateTime.parse(
      (json['created_at'] ?? json['createdAt']) as String,
    );
    final expiresRaw = json['expires_at'] ?? json['expiresAt'];
    final duration = (json['listing_duration_days'] as num?)?.toInt() ?? 30;
    final expires = expiresRaw is String
        ? DateTime.parse(expiresRaw)
        : created.add(Duration(days: duration));
    final explicit = json['status'];
    final active = json['is_active'];
    final normalizedStatus = explicit is String
        ? explicit.trim().toLowerCase()
        : '';
    final status = normalizedStatus.isNotEmpty
        ? (normalizedStatus == 'active' || normalizedStatus == 'approved'
              ? 'published'
              : normalizedStatus)
        : active == false
        ? 'inactive'
        : 'published';
    return Job(
      id: '${json['id']}',
      title: (json['title'] as String? ?? '').trim(),
      company: (json['company_name'] ?? json['company'] ?? '')
          .toString()
          .trim(),
      city: (json['state'] ?? json['city'] ?? '').toString().trim(),
      country: (json['country'] as String? ?? 'سوريا').trim(),
      category: (fieldMap['name_ar'] ?? json['category'] ?? 'غير محدد')
          .toString()
          .trim(),
      jobFieldId:
          (fieldMap['id'] as num?)?.toInt() ??
          (json['job_field_id'] as num?)?.toInt(),
      workType: (json['job_type'] ?? json['workType'] ?? '').toString().trim(),
      workMode: _apiWorkMode(json['work_type'] ?? json['workMode']),
      experience: (json['experience'] as String? ?? '').trim(),
      salaryMin:
          ((salaryMap['min'] ?? json['salary_min'] ?? json['salaryMin'])
                  as num?)
              ?.toInt(),
      salaryMax:
          ((salaryMap['max'] ?? json['salary_max'] ?? json['salaryMax'])
                  as num?)
              ?.toInt(),
      currency: normalizeCurrency(salaryMap['currency'] ?? json['currency']),
      salaryPeriod: normalizeSalaryPeriod(
        salaryMap['period'] ??
            json['salary_period'] ??
            json['salaryPeriod'] ??
            'شهري',
      ),
      description: (json['description'] as String? ?? '').trim(),
      requirements: _readRequirements(json['requirements']),
      phone: (contactMap['phone'] ?? json['phone'] ?? '').toString(),
      email: (contactMap['email'] ?? json['email'] ?? '').toString(),
      companyWebsite: (json['url'] ?? json['companyWebsite'] ?? '')
          .toString()
          .trim(),
      createdAt: created,
      expiresAt: expires,
      status: status,
      acceptsApplications: json['accepts_applications'] == true,
      rejectionReason: json['rejection_reason'] as String? ?? '',
      // Device IDs authorize owner actions; never retain them in public cache.
      employerKey: json['employerKey'] as String?,
      viewsCount:
          (json['views_count'] as num?)?.toInt() ??
          (json['viewsCount'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'company': company,
    'city': city,
    'category': category,
    'workType': workType,
    'workMode': workMode,
    'experience': experience,
    'salaryMin': salaryMin,
    'salaryMax': salaryMax,
    'currency': currency,
    'salaryPeriod': salaryPeriod,
    'description': description,
    'requirements': requirements,
    'phone': phone,
    'email': email,
    'companyWebsite': companyWebsite,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'status': status,
    'isDemo': isDemo,
    'employerKey': employerKey,
    'country': country,
    'jobFieldId': jobFieldId,
    'viewsCount': viewsCount,
    'acceptsApplications': acceptsApplications,
    'rejectionReason': rejectionReason,
  };

  Job copyWith({
    String? id,
    String? status,
    bool? isDemo,
    int? viewsCount,
    bool? acceptsApplications,
  }) => Job(
    id: id ?? this.id,
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
    description: description,
    requirements: requirements,
    phone: phone,
    email: email,
    companyWebsite: companyWebsite,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    isDemo: isDemo ?? this.isDemo,
    employerKey: employerKey,
    country: country,
    jobFieldId: jobFieldId,
    viewsCount: viewsCount ?? this.viewsCount,
    acceptsApplications: acceptsApplications ?? this.acceptsApplications,
    rejectionReason: rejectionReason,
  );
}

List<String> _readRequirements(Object? raw) {
  if (raw is List) {
    return List<String>.unmodifiable(
      raw.map((item) => '$item'.trim()).where((item) => item.isNotEmpty),
    );
  }
  if (raw is String) {
    return List<String>.unmodifiable(
      raw
          .split(RegExp(r'[\n,،]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }
  return const [];
}

String formatAmount(int amount) => amount.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

/// The management token deliberately never enters this serializable model.
@immutable
class Submission {
  const Submission({required this.job, required this.createdAt});

  final Job job;
  final DateTime createdAt;
  String get id => job.id;
  String get status => job.status;
  bool get isDemo => job.isDemo;

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
    job: Job.fromJson(Map<String, dynamic>.from(json['job'] as Map)),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'job': job.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
