import 'job_filters.dart';

const _titles = <String, List<String>>{
  'تقنية': [
    'مطور تطبيقات Flutter',
    'مطور مواقع',
    'مهندس برمجيات',
    'فني دعم تقني',
    'محلل بيانات',
    'Flutter Developer',
    'Web Developer',
    'Software Engineer',
    'IT Support',
    'Data Analyst',
  ],
  'تصميم': [
    'مصمم غرافيك',
    'مصمم واجهات وتجربة مستخدم',
    'مصمم موشن غرافيك',
    'Graphic Designer',
    'UI/UX Designer',
    'Motion Designer',
  ],
  'تسويق': [
    'مسؤول تسويق رقمي',
    'مدير وسائل التواصل الاجتماعي',
    'كاتب محتوى',
    'Digital Marketing Specialist',
    'Social Media Manager',
    'Content Writer',
  ],
  'مبيعات': [
    'مندوب مبيعات',
    'مسؤول مبيعات',
    'موظف خدمة عملاء',
    'Sales Representative',
    'Sales Manager',
    'Customer Service Agent',
  ],
  'مطاعم وضيافة': [
    'باريستا',
    'طباخ',
    'مساعد شيف',
    'نادل',
    'موظف استقبال',
    'Barista',
    'Chef',
    'Waiter',
    'Receptionist',
  ],
  'حِرف ومهن': [
    'فني كهرباء',
    'فني صيانة',
    'نجار',
    'خياط',
    'سائق توصيل',
    'Electrician',
    'Maintenance Technician',
    'Carpenter',
    'Delivery Driver',
  ],
  'إدارة ومحاسبة': [
    'محاسب',
    'مساعد إداري',
    'مدير مكتب',
    'مسؤول موارد بشرية',
    'Accountant',
    'Administrative Assistant',
    'Office Manager',
    'HR Specialist',
  ],
  'تعليم': [
    'مدرس لغة إنجليزية',
    'مدرس رياضيات',
    'معلم صف',
    'مدرب مهني',
    'English Teacher',
    'Math Teacher',
    'Classroom Teacher',
    'Trainer',
  ],
  'صحة': [
    'ممرض',
    'صيدلي',
    'مساعد طبيب أسنان',
    'فني مخبر',
    'Nurse',
    'Pharmacist',
    'Dental Assistant',
    'Lab Technician',
  ],
};

/// Local, curated suggestions; typed text always remains freely editable.
List<String> suggestJobTitles(String input, String category) {
  final query = normalizeSearch(input).trim();
  if (query.isEmpty) return const [];
  final candidates = <String>{
    ...?_titles[category],
    ..._titles.values.expand((v) => v),
  };
  final words = query.split(RegExp(r'\s+'));
  return candidates
      .where((title) {
        final normalized = normalizeSearch(title);
        return normalized != query && words.every(normalized.contains);
      })
      .take(4)
      .toList(growable: false);
}
