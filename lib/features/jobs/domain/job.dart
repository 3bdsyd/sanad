import 'package:flutter/foundation.dart';

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
const jobWorkModes = <String>['من المكتب', 'عن بُعد', 'هجين'];
const jobExperienceLevels = <String>['بدون خبرة', 'مبتدئ', 'متوسط', 'خبير'];
const jobSalaryPeriods = <String>['شهري', 'بالساعة', 'للمشروع'];

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

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
  String get locationLabel {
    final place = city.trim();
    final nation = country.trim();
    if (nation.isEmpty || nation == place || nation == 'سوريا') return place;
    return '$place · $nation';
  }

  bool get isAvailable => status == 'published' && !isExpired;
  bool get hasSalary => salaryMin != null || salaryMax != null;
  String get currencyLabel => currency == 'USD' ? '\$' : 'ل.س';
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
    currency: json['currency'] as String? ?? 'SYP',
    salaryPeriod: json['salaryPeriod'] as String? ?? 'شهري',
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
    var status = explicit is String && explicit.isNotEmpty
        ? (explicit == 'active' || explicit == 'approved'
              ? 'published'
              : explicit)
        : active == false
        ? 'inactive'
        : 'published';
    if (fromCatalog && status == 'pending' && active != false) {
      status = 'published';
    }
    return Job(
      id: '${json['id']}',
      title: (json['title'] as String? ?? '').trim(),
      company: (json['company_name'] ?? json['company'] ?? '')
          .toString()
          .trim(),
      city: (json['state'] ?? json['city'] ?? '').toString().trim(),
      country: (json['country'] as String? ?? 'سوريا').trim(),
      category: (fieldMap['name_ar'] ?? json['category'] ?? 'غير محدد')
          .toString(),
      jobFieldId:
          (fieldMap['id'] as num?)?.toInt() ??
          (json['job_field_id'] as num?)?.toInt(),
      workType: (json['job_type'] ?? json['workType'] ?? '').toString(),
      workMode: (json['work_type'] ?? json['workMode'] ?? '').toString(),
      experience: (json['experience'] as String? ?? '').toString(),
      salaryMin:
          ((salaryMap['min'] ?? json['salary_min'] ?? json['salaryMin'])
                  as num?)
              ?.toInt(),
      salaryMax:
          ((salaryMap['max'] ?? json['salary_max'] ?? json['salaryMax'])
                  as num?)
              ?.toInt(),
      currency: (salaryMap['currency'] ?? json['currency'] ?? 'SYP').toString(),
      salaryPeriod:
          (salaryMap['period'] ??
                  json['salary_period'] ??
                  json['salaryPeriod'] ??
                  'شهري')
              .toString(),
      description: (json['description'] as String? ?? '').trim(),
      requirements: _readRequirements(json['requirements']),
      phone: (contactMap['phone'] ?? json['phone'] ?? '').toString(),
      email: (contactMap['email'] ?? json['email'] ?? '').toString(),
      createdAt: created,
      expiresAt: expires,
      status: status,
      employerKey:
          json['device_id'] as String? ?? json['employerKey'] as String?,
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
  };

  Job copyWith({String? id, String? status, bool? isDemo}) => Job(
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
