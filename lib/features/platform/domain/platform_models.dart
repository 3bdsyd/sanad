import '../../jobs/domain/job.dart';

typedef Json = Map<String, dynamic>;

Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(Object? value) =>
    value is List ? value.whereType<Map>().map(object).toList() : [];
String textOf(Object? value) => value?.toString() ?? '';

List<String> profileLabels(String value) => value
    .split(RegExp(r'[,،\n]'))
    .map((v) => v.trim())
    .where((v) => v.isNotEmpty)
    .toSet()
    .toList();
String? validateProfileLabels(String value, int limit) {
  final labels = profileLabels(value);
  if (labels.length > limit) return 'الحد الأقصى $limit عناصر.';
  if (labels.any((v) => v.length > 40)) return 'استخدم حتى 40 حرفاً لكل عنصر.';
  return null;
}

int? profileYears(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  var normalized = value.trim();
  for (var i = 0; i < 10; i++) {
    normalized = normalized
        .replaceAll(arabic[i], '$i')
        .replaceAll(persian[i], '$i');
  }
  return int.tryParse(normalized);
}

class Member {
  const Member(this.data);
  final Json data;
  String get id => textOf(data['id']);
  String get name => textOf(data['name']);
  String get email => textOf(data['email']);
  String get headline => textOf(data['headline']);
  String get phone => textOf(data['phone']);
  String get country => textOf(data['country']);
  String get summary => textOf(data['summary']);
  int? get experienceYears => (data['experience_years'] as num?)?.toInt();
  List<String> get skills => _labels(data['skills']);
  List<String> get languages => _labels(data['languages']);
  Map<String, bool> get profileSteps => {
    'الاسم': name.trim().length >= 2,
    'المسمى المهني': headline.trim().isNotEmpty,
    'نبذة مهنية': summary.trim().isNotEmpty,
    'المهارات': skills.isNotEmpty,
    'اللغات': languages.isNotEmpty,
    'سنوات الخبرة': experienceYears != null,
  };
  int get completedSteps => profileSteps.values.where((v) => v).length;
}

List<String> _labels(Object? value) => value is List
    ? value.whereType<String>().where((v) => v.trim().isNotEmpty).toList()
    : [];

class ApplicationRecord {
  const ApplicationRecord(this.data);
  final Json data;
  String get id => textOf(data['id']);
  Job get job => Job.fromApi(object(data['job']));
  Member get applicant => Member(object(data['applicant']));
  String get status => textOf(data['status']);
  String get note => textOf(data['note']);
  String get conversationId => textOf(data['conversation_id']);
  String get updatedAt => textOf(data['updated_at']);
  String get createdAt => textOf(data['created_at']);
  List<Json> get history => objects(data['history']);
  int get version => (data['version'] as num?)?.toInt() ?? 1;
}

const applicationLabels = {
  'submitted': 'تم إرسال الطلب',
  'under_review': 'قيد الدراسة',
  'shortlisted': 'مرشّح للمقابلة',
  'accepted': 'مقبول',
  'rejected': 'لم يتم الاختيار',
  'withdrawn': 'تم سحب الطلب',
};
const applicationTransitions = {
  'submitted': ['under_review', 'shortlisted', 'accepted', 'rejected'],
  'under_review': ['shortlisted', 'accepted', 'rejected'],
  'shortlisted': ['accepted', 'rejected'],
};
const postingLabels = {
  'pending': 'قيد المراجعة',
  'published': 'منشورة',
  'rejected': 'تحتاج إلى تعديل',
  'expired': 'انتهت المدة',
  'withdrawn': 'مسحوبة',
  'closed': 'مغلقة',
};

class Conversation {
  const Conversation(this.data);
  final Json data;
  String get id => textOf(data['id']);
  String get title => textOf(data['job_title']);
  String get jobId => textOf(data['job_id']);
  Member get peer => Member(object(data['peer']));
  String get preview => textOf(object(data['last_message'])['text']);
  int get unread => (data['unread_count'] as num?)?.toInt() ?? 0;
  bool get canSend => data['can_send'] == true;
  bool get blocked => data['blocked_by_me'] == true;
}

class ChatMessage {
  const ChatMessage(this.data);
  final Json data;
  String get id => textOf(data['id']);
  String get clientId => textOf(data['client_id']);
  String get senderId => textOf(data['sender_id']);
  String get text => textOf(data['text']);
  String get state => textOf(data['delivery_state']);
  String get sentAt => textOf(data['created_at']);
  bool get pending => data['local_state'] == 'pending';
  bool get failed => data['local_state'] == 'failed';
}

class PlatformFailure implements Exception {
  const PlatformFailure(
    this.message, {
    this.status,
    this.code,
    this.uncertain = false,
  });
  final String message;
  final int? status;
  final String? code;
  final bool uncertain;
  @override
  String toString() => message;
}
