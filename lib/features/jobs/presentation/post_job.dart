import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';

import '../../../core/adaptive_text_field.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/web_layout.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/company_website.dart';
import '../domain/job_title_suggestions.dart';

class _PhoneCountry {
  const _PhoneCountry(this.name, this.flag, this.dialCode);

  final String name;
  final String flag;
  final String dialCode;

  String get isoCode => switch (dialCode) {
    '+963' => 'SY',
    '+961' => 'LB',
    '+962' => 'JO',
    '+970' => 'PS',
    '+964' => 'IQ',
    '+90' => 'TR',
    '+966' => 'SA',
    '+971' => 'AE',
    '+974' => 'QA',
    '+965' => 'KW',
    '+973' => 'BH',
    '+968' => 'OM',
    '+967' => 'YE',
    '+20' => 'EG',
    '+49' => 'DE',
    '+44' => 'GB',
    '+33' => 'FR',
    '+46' => 'SE',
    '+31' => 'NL',
    '+43' => 'AT',
    '+32' => 'BE',
    '+41' => 'CH',
    '+39' => 'IT',
    '+34' => 'ES',
    '+47' => 'NO',
    '+45' => 'DK',
    '+358' => 'FI',
    '+48' => 'PL',
    '+7' => 'RU',
    '+1' => name == 'كندا' ? 'CA' : 'US',
    '+52' => 'MX',
    '+55' => 'BR',
    '+61' => 'AU',
    '+64' => 'NZ',
    '+91' => 'IN',
    '+92' => 'PK',
    '+880' => 'BD',
    '+81' => 'JP',
    '+82' => 'KR',
    '+86' => 'CN',
    '+98' => 'IR',
    '+27' => 'ZA',
    _ => 'SY',
  };
}

const _phoneCountries = [
  _PhoneCountry('سوريا', '🇸🇾', '+963'),
  _PhoneCountry('لبنان', '🇱🇧', '+961'),
  _PhoneCountry('الأردن', '🇯🇴', '+962'),
  _PhoneCountry('فلسطين', '🇵🇸', '+970'),
  _PhoneCountry('العراق', '🇮🇶', '+964'),
  _PhoneCountry('تركيا', '🇹🇷', '+90'),
  _PhoneCountry('السعودية', '🇸🇦', '+966'),
  _PhoneCountry('الإمارات', '🇦🇪', '+971'),
  _PhoneCountry('قطر', '🇶🇦', '+974'),
  _PhoneCountry('الكويت', '🇰🇼', '+965'),
  _PhoneCountry('البحرين', '🇧🇭', '+973'),
  _PhoneCountry('عُمان', '🇴🇲', '+968'),
  _PhoneCountry('اليمن', '🇾🇪', '+967'),
  _PhoneCountry('مصر', '🇪🇬', '+20'),
  _PhoneCountry('ألمانيا', '🇩🇪', '+49'),
  _PhoneCountry('المملكة المتحدة', '🇬🇧', '+44'),
  _PhoneCountry('فرنسا', '🇫🇷', '+33'),
  _PhoneCountry('السويد', '🇸🇪', '+46'),
  _PhoneCountry('هولندا', '🇳🇱', '+31'),
  _PhoneCountry('النمسا', '🇦🇹', '+43'),
  _PhoneCountry('بلجيكا', '🇧🇪', '+32'),
  _PhoneCountry('سويسرا', '🇨🇭', '+41'),
  _PhoneCountry('إيطاليا', '🇮🇹', '+39'),
  _PhoneCountry('إسبانيا', '🇪🇸', '+34'),
  _PhoneCountry('النرويج', '🇳🇴', '+47'),
  _PhoneCountry('الدنمارك', '🇩🇰', '+45'),
  _PhoneCountry('فنلندا', '🇫🇮', '+358'),
  _PhoneCountry('بولندا', '🇵🇱', '+48'),
  _PhoneCountry('روسيا', '🇷🇺', '+7'),
  _PhoneCountry('الولايات المتحدة', '🇺🇸', '+1'),
  _PhoneCountry('كندا', '🇨🇦', '+1'),
  _PhoneCountry('المكسيك', '🇲🇽', '+52'),
  _PhoneCountry('البرازيل', '🇧🇷', '+55'),
  _PhoneCountry('أستراليا', '🇦🇺', '+61'),
  _PhoneCountry('نيوزيلندا', '🇳🇿', '+64'),
  _PhoneCountry('الهند', '🇮🇳', '+91'),
  _PhoneCountry('باكستان', '🇵🇰', '+92'),
  _PhoneCountry('بنغلادش', '🇧🇩', '+880'),
  _PhoneCountry('اليابان', '🇯🇵', '+81'),
  _PhoneCountry('كوريا الجنوبية', '🇰🇷', '+82'),
  _PhoneCountry('الصين', '🇨🇳', '+86'),
  _PhoneCountry('إيران', '🇮🇷', '+98'),
  _PhoneCountry('جنوب أفريقيا', '🇿🇦', '+27'),
];

Future<void> showPostJob(BuildContext context, JobsStore store) =>
    openPage<void>(context, PostJobPage(store: store));

class PostJobPage extends StatefulWidget {
  const PostJobPage({super.key, required this.store});
  final JobsStore store;

  @override
  State<PostJobPage> createState() => _PostJobPageState();
}

class _PostJobPageState extends State<PostJobPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final forms = [GlobalKey<FormState>(), GlobalKey<FormState>()];
  final scroll = ScrollController();
  final consentKey = GlobalKey();
  final Map<TextEditingController, GlobalKey<FormFieldState<String>>>
  fieldKeys = {};
  final Map<TextEditingController, FocusNode> focusNodes = {};
  final title = TextEditingController();
  final company = TextEditingController();
  final companyWebsite = TextEditingController();
  final description = TextEditingController();
  final requirements = TextEditingController();
  final phone = TextEditingController();
  final countrySearch = TextEditingController();
  final email = TextEditingController();
  final minSalary = TextEditingController();
  final maxSalary = TextEditingController();
  late final AnimationController stepAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  Timer? revealTimer;
  String city = jobCities.first;
  String category = jobCategories.first;
  String workType = jobWorkTypes.first;
  String workMode = jobWorkModes.first;
  String experience = jobExperienceLevels.first;
  String currency = 'SYP';
  String period = 'شهري';
  _PhoneCountry phoneCountry = _phoneCountries.first;
  String? expandedChoice, error;
  int step = 0, days = 30;
  bool tried = false;
  bool consent = false, consentError = false;
  bool saving = false, changed = false, confirmingExit = false;
  bool completed = false, submissionRecorded = false, allowExit = false;
  bool showSalary = false;
  bool showTitleSuggestions = true;

  String _shown(String value, List<String> options) =>
      options.contains(value) ? value : options.first;

  void _alignChoices() {
    if (!mounted || completed || saving) return;
    final nextCategory = _shown(category, widget.store.categoryOptions);
    final nextCity = _shown(city, widget.store.placeOptions);
    final nextWorkType = _shown(workType, widget.store.workTypeOptions);
    final nextWorkMode = _shown(workMode, widget.store.workModeOptions);
    final nextExperience = _shown(experience, widget.store.experienceOptions);
    if (nextCategory == category &&
        nextCity == city &&
        nextWorkType == workType &&
        nextWorkMode == workMode &&
        nextExperience == experience) {
      return;
    }
    setState(() {
      category = nextCategory;
      city = nextCity;
      workType = nextWorkType;
      workMode = nextWorkMode;
      experience = nextExperience;
    });
  }

  List<TextEditingController> get controllers => [
    title,
    company,
    companyWebsite,
    description,
    requirements,
    phone,
    email,
    minSalary,
    maxSalary,
  ];

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_alignChoices);
    WidgetsBinding.instance.addObserver(this);
    for (final controller in controllers) {
      final node = FocusNode();
      focusNodes[controller] = node;
      fieldKeys[controller] = GlobalKey<FormFieldState<String>>();
      node.addListener(() {
        if (node.hasFocus) scheduleReveal(controller);
      });
    }
  }

  @override
  void didChangeMetrics() {
    for (final entry in focusNodes.entries) {
      if (entry.value.hasFocus) {
        scheduleReveal(entry.key);
        break;
      }
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_alignChoices);
    WidgetsBinding.instance.removeObserver(this);
    revealTimer?.cancel();
    stepAnimation.dispose();
    scroll.dispose();
    for (final controller in controllers) {
      controller.dispose();
    }
    countrySearch.dispose();
    for (final node in focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void scheduleReveal(TextEditingController controller) {
    revealTimer?.cancel();
    // Scaffold is the only owner of keyboard insets. Wait for its viewport to
    // settle before revealing the focused field, including with hardware Next.
    revealTimer = Timer(const Duration(milliseconds: 330), () {
      if (!mounted) return;
      final target = fieldKeys[controller]?.currentContext;
      if (target != null) revealTarget(target);
    });
  }

  Future<void> revealTarget(BuildContext target) => Scrollable.ensureVisible(
    target,
    alignment: .16,
    duration: motionDuration(context, 260),
    curve: Curves.easeOutCubic,
  );

  void revealInvalid() {
    for (final controller in controllers) {
      if (fieldKeys[controller]?.currentState?.hasError ?? false) {
        focusNodes[controller]?.requestFocus();
        scheduleReveal(controller);
        return;
      }
    }
  }

  String normalizeDigits(String raw) {
    var value = raw.trim();
    for (var i = 0; i < 10; i++) {
      value = value
          .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], '$i')
          .replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], '$i');
    }
    return value;
  }

  String normalizedPhone(String raw) {
    final value = normalizeDigits(
      raw.trim(),
    ).replaceAll(RegExp(r'[\s()\-]'), '');
    if (value.startsWith('+')) return value;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${phoneCountry.dialCode}$national';
  }

  int? number(TextEditingController controller) =>
      int.tryParse(normalizeDigits(controller.text));

  String? validate(
    TextEditingController controller,
    String? raw, {
    required bool required,
    required bool numeric,
  }) {
    final value = raw?.trim() ?? '';
    if (controller == phone && value.isEmpty && email.text.trim().isEmpty) {
      return 'أضف رقم واتساب أو إيميل للتواصل.';
    }
    if (required && value.isEmpty) return 'هالحقل مطلوب.';
    if (controller == title && value.length < 3) {
      return 'اكتب مسمّى من ٣ أحرف على الأقل.';
    }
    if (controller == company && value.length < 2) {
      return 'اكتب اسم الجهة من حرفين على الأقل.';
    }
    if (controller == companyWebsite &&
        normalizeCompanyWebsite(raw ?? '') == null) {
      return 'أضف رابط موقع صحيح، مثل example.com، بدون اسم مستخدم أو كلمة مرور.';
    }
    if (controller == description && value.length < 20) {
      return 'اكتب وصفاً واضحاً من ٢٠ حرفاً على الأقل.';
    }
    if (controller == requirements && value.isNotEmpty) {
      final items = value
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (items.length > 12 ||
          items.any((s) => s.length < 2 || s.length > 200)) {
        return 'حتى ١٢ متطلباً، كل سطر بين ٢ و٢٠٠ حرف.';
      }
    }
    if (numeric &&
        value.isNotEmpty &&
        (number(controller) == null ||
            number(controller)! < 0 ||
            number(controller)! > 1000000000)) {
      return 'اكتب مبلغاً صحيحاً من ٠ إلى مليار.';
    }
    if (controller == maxSalary &&
        number(controller) != null &&
        number(minSalary) != null &&
        number(controller)! < number(minSalary)!) {
      return 'الحد الأعلى لازم يكون أكبر من أو يساوي الأدنى.';
    }
    if (controller == email &&
        value.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'تأكد من صيغة البريد، مثال: name@example.com';
    }
    if (controller == phone &&
        value.isNotEmpty &&
        !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone(value))) {
      return 'تأكد من الرقم ورمز البلد، مثال: 09xxxxxxxx أو +49…';
    }
    return null;
  }

  Widget field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    int lines = 1,
    int max = 140,
    bool required = true,
    bool numeric = false,
    TextInputType? keyboard,
    Widget? countrySelector,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: AdaptiveFieldDirection(
      controller: controller,
      forceLtr:
          controller == phone ||
          controller == email ||
          controller == companyWebsite ||
          numeric,
      builder: (context, direction) => TextFormField(
        key: fieldKeys[controller],
        focusNode: focusNodes[controller],
        controller: controller,
        onTap: () => scheduleReveal(controller),
        enabled: !saving && !submissionRecorded,
        scrollPadding: const EdgeInsets.all(24),
        autovalidateMode: tried
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        textInputAction: lines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
        maxLength: max,
        maxLines: lines,
        inputFormatters: controller == phone
            ? [
                PhoneInputFormatter(
                  defaultCountryCode: phoneCountry.isoCode,
                  allowEndlessPhone: true,
                ),
              ]
            : null,
        textDirection: direction,
        textAlign: direction == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
        autocorrect: controller != email && controller != companyWebsite,
        enableSuggestions: controller != email && controller != companyWebsite,
        keyboardType:
            keyboard ??
            (numeric
                ? TextInputType.number
                : lines > 1
                ? TextInputType.multiline
                : TextInputType.text),
        onChanged: (_) {
          if (controller == title && !showTitleSuggestions) {
            setState(() => showTitleSuggestions = true);
          }
          if (!changed) setState(() => changed = true);
          if (tried && (controller == email || controller == phone)) {
            fieldKeys[phone]?.currentState?.validate();
            fieldKeys[email]?.currentState?.validate();
          }
          if (tried && controller == minSalary) {
            fieldKeys[maxSalary]?.currentState?.validate();
          }
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          errorMaxLines: 3,
          counterText: '',
          alignLabelWithHint: lines > 1,
          suffixIcon: countrySelector,
          suffixIconConstraints: countrySelector == null
              ? null
              : const BoxConstraints(
                  minWidth: 116,
                  maxWidth: 132,
                  minHeight: 52,
                ),
        ),
        validator: (value) =>
            validate(controller, value, required: required, numeric: numeric),
      ),
    ),
  );

  Widget titleSuggestions() => ListenableBuilder(
    listenable: title,
    builder: (context, _) {
      final suggestions = showTitleSuggestions && !saving && !submissionRecorded
          ? suggestJobTitles(title.text, category)
          : const <String>[];
      return MotionSize(
        duration: motionDuration(context, 180),
        alignment: Alignment.topCenter,
        child: suggestions.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مسميات مقترحة',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.sanad.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final suggestion in suggestions)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () {
                              title.value = TextEditingValue(
                                text: suggestion,
                                selection: TextSelection.collapsed(
                                  offset: suggestion.length,
                                ),
                              );
                              setState(() {
                                changed = true;
                                showTitleSuggestions = false;
                              });
                              if (tried) {
                                fieldKeys[title]?.currentState?.validate();
                              }
                              focusNodes[company]?.requestFocus();
                            },
                            child: Text(
                              suggestion,
                              textDirection: textDirectionFor(suggestion),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
      );
    },
  );

  String choiceLabel(String value) => switch (value) {
    'SYP' => 'ليرة سورية',
    'USD' => 'دولار أمريكي',
    _ => value,
  };

  Widget phoneCountryButton() => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: context.sanad.tint.withValues(alpha: .55),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: saving || submissionRecorded
            ? null
            : () {
                FocusScope.of(context).unfocus();
                setState(() {
                  expandedChoice = expandedChoice == 'phoneCountry'
                      ? null
                      : 'phoneCountry';
                  countrySearch.clear();
                });
              },
        child: SizedBox(
          width: 116,
          height: 52,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(phoneCountry.flag, style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 5),
                Text(
                  phoneCountry.dialCode,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: context.sanad.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                AppIcon(
                  expandedChoice == 'phoneCountry'
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  color: context.sanad.secondary,
                  size: 13,
                ),
                const SizedBox(width: 9),
                Container(width: 1, height: 26, color: context.sanad.border),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget phoneCountryOptions() {
    if (expandedChoice != 'phoneCountry') {
      return const SizedBox(width: double.infinity);
    }
    final query = normalizeDigits(countrySearch.text.trim()).toLowerCase();
    final countries = _phoneCountries
        .where(
          (country) =>
              country.name.toLowerCase().contains(query) ||
              country.dialCode.contains(query),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: context.sanad.background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.sanad.border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: AdaptiveFieldDirection(
                controller: countrySearch,
                builder: (context, direction) => TextField(
                  controller: countrySearch,
                  textDirection: direction,
                  textAlign: direction == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن بلد أو رمز',
                    prefixIcon: Icon(CupertinoIcons.search),
                    isDense: true,
                  ),
                ),
              ),
            ),
            if (countries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'ما لقينا هالبلد أو الرمز.',
                  style: TextStyle(color: context.sanad.secondary),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: context.sanad.tint.withValues(alpha: .55),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: countries.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: context.sanad.border,
                      indent: 14,
                      endIndent: 14,
                    ),
                    itemBuilder: (context, index) {
                      final country = countries[index];
                      final selected = country == phoneCountry;
                      return ListTile(
                        minTileHeight: 52,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        leading: Text(
                          country.flag,
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: Text(country.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              country.dialCode,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(color: context.sanad.secondary),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 8),
                              AppIcon(
                                CupertinoIcons.checkmark,
                                color: context.sanad.primary,
                                size: 17,
                              ),
                            ],
                          ],
                        ),
                        onTap: saving || submissionRecorded
                            ? null
                            : () {
                                setState(() {
                                  phoneCountry = country;
                                  expandedChoice = null;
                                  changed = true;
                                  if (phone.text.isNotEmpty) {
                                    final currentValue = phone.value;
                                    phone.value =
                                        PhoneInputFormatter(
                                          defaultCountryCode: country.isoCode,
                                          allowEndlessPhone: true,
                                        ).formatEditUpdate(
                                          TextEditingValue.empty,
                                          currentValue,
                                        );
                                  }
                                });
                                if (tried) {
                                  fieldKeys[phone]?.currentState?.validate();
                                }
                              },
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget picker(
    String label,
    String value,
    List<String> values,
    ValueChanged<String> changedValue,
  ) {
    final isOpen = expandedChoice == label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: isOpen,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashFactory: NoSplash.splashFactory,
              highlightColor: context.sanad.tint.withValues(alpha: .55),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: 16,
              title: Text(label, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                choiceLabel(value),
                style: TextStyle(
                  color: context.sanad.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: AnimatedRotation(
                turns: isOpen ? .5 : 0,
                duration: motionDuration(context, 180),
                child: AppIcon(
                  CupertinoIcons.chevron_down,
                  color: context.sanad.secondary,
                  size: 17,
                ),
              ),
              onTap: saving || submissionRecorded
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      setState(() => expandedChoice = isOpen ? null : label);
                    },
            ),
          ),
        ),
        MotionSize(
          duration: motionDuration(context, 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final item in values)
                          Semantics(
                            selected: item == value,
                            child: OutlinedButton(
                              onPressed: saving || submissionRecorded
                                  ? null
                                  : () {
                                      changed = true;
                                      setState(() {
                                        changedValue(item);
                                        expandedChoice = null;
                                      });
                                    },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                foregroundColor: item == value
                                    ? context.sanad.primary
                                    : context.sanad.ink,
                                backgroundColor: item == value
                                    ? context.sanad.tint
                                    : context.sanad.surface,
                                side: BorderSide(
                                  color: item == value
                                      ? context.sanad.primary
                                      : context.sanad.border,
                                ),
                              ),
                              child: Text(
                                choiceLabel(item),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget section(
    String label,
    List<Widget> children, {
    String? subtitle,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: context.sanad.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.sanad.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.sanad.tint,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: context.sanad.primary.withValues(alpha: .12),
                      ),
                    ),
                    child: AppIcon(
                      icon,
                      color: context.sanad.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    ),
  );

  void changeStep(int value) {
    FocusScope.of(context).unfocus();
    revealTimer?.cancel();
    setState(() {
      step = value;
      tried = false;
      consentError = false;
      error = null;
      expandedChoice = null;
      confirmingExit = false;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    if (MediaQuery.disableAnimationsOf(context)) {
      stepAnimation.value = 1;
    } else {
      stepAnimation.forward(from: 0);
    }
  }

  Future<void> next() async {
    if (saving || completed || submissionRecorded || confirmingExit) return;
    FocusScope.of(context).unfocus();
    setState(() => tried = true);
    if (!(forms[step].currentState?.validate() ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revealInvalid();
      });
      return;
    }
    if (step == 0) {
      changeStep(1);
      return;
    }
    if (!consent) {
      setState(() => consentError = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = consentKey.currentContext;
        if (mounted && target != null) revealTarget(target);
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final existingIds = widget.store.submissions.map((s) => s.id).toSet();
    try {
      final now = DateTime.now();
      final job = Job(
        id: '',
        title: title.text.trim(),
        company: company.text.trim(),
        companyWebsite: normalizeCompanyWebsite(companyWebsite.text)!,
        city: _shown(city, widget.store.placeOptions),
        category: _shown(category, widget.store.categoryOptions),
        jobFieldId: widget.store.fieldIdFor(
          _shown(category, widget.store.categoryOptions),
        ),
        workType: _shown(workType, widget.store.workTypeOptions),
        workMode: _shown(workMode, widget.store.workModeOptions),
        experience: _shown(experience, widget.store.experienceOptions),
        salaryMin: showSalary ? number(minSalary) : null,
        salaryMax: showSalary ? number(maxSalary) : null,
        currency: currency,
        salaryPeriod: period,
        description: description.text.trim(),
        requirements: requirements.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        phone: phone.text.trim().isEmpty ? '' : normalizedPhone(phone.text),
        email: email.text.trim(),
        createdAt: now,
        expiresAt: now.add(Duration(days: days)),
        status: 'pending',
      );
      await widget.store.submit(job, contactConsent: consent);
      if (!mounted) return;
      setState(() {
        changed = false;
        completed = true;
        submissionRecorded = true;
      });
      if (scroll.hasClients) scroll.jumpTo(0);
      if (!MediaQuery.disableAnimationsOf(context)) {
        stepAnimation.forward(from: 0);
      }
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString().replaceFirst('Exception: ', '');
        // The server can accept a job before secure/local persistence fails.
        // In that state never expose another submit button for the same draft.
        submissionRecorded = widget.store.submissions.any(
          (submission) => !existingIds.contains(submission.id),
        );
        if (submissionRecorded) changed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) animateScrollTo(context, scroll, 0);
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> exitPage() async {
    if (saving) return;
    FocusScope.of(context).unfocus();
    setState(() => allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void requestClose() {
    if (saving) return;
    if (!changed || completed || submissionRecorded) {
      exitPage();
      return;
    }
    FocusScope.of(context).unfocus();
    revealTimer?.cancel();
    setState(() => confirmingExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) animateScrollTo(context, scroll, 0);
    });
  }

  void back() {
    if (saving) return;
    if (confirmingExit) {
      setState(() => confirmingExit = false);
    } else if (step == 1 && !completed && !submissionRecorded) {
      changeStep(0);
    } else {
      requestClose();
    }
  }

  Widget exitConfirmation() => section('تترك الإعلان؟', [
    Text(
      'التفاصيل اللي كتبتها ما انحفظت بعد.',
      style: TextStyle(color: context.sanad.secondary),
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: () => setState(() => confirmingExit = false),
      child: const Text('كمّل كتابة'),
    ),
    const SizedBox(height: 12),
    TextButton(onPressed: exitPage, child: const Text('اترك الإعلان بدون حفظ')),
    const SizedBox(height: 8),
  ]);

  Widget stepOne() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      postIntro(),
      section('عرّف الناس بالفرصة', [
        field(title, 'المسمّى الوظيفي', hint: 'مثلاً: مصمم غرافيك', max: 100),
        titleSuggestions(),
        field(
          company,
          'اسم جهة العمل',
          hint: 'الاسم اللي رح يظهر بالإعلان',
          max: 100,
        ),
        field(
          companyWebsite,
          'رابط جهة العمل',
          hint: 'example.com',
          helper:
              'اختياري · موقع مؤسستك أو صفحتها الرسمية، وبيظهر ضمن تفاصيل الفرصة.',
          keyboard: TextInputType.url,
          required: false,
          max: 2048,
        ),
      ], icon: CupertinoIcons.briefcase),
      section('وين وكيف الشغل؟', [
        picker(
          'المحافظة',
          _shown(city, widget.store.placeOptions),
          widget.store.placeOptions,
          (v) => city = v,
        ),
        Divider(height: 1, color: context.sanad.border),
        picker(
          'المجال',
          _shown(category, widget.store.categoryOptions),
          widget.store.categoryOptions,
          (v) => category = v,
        ),
        Divider(height: 1, color: context.sanad.border),
        picker(
          'نوع الدوام',
          _shown(workType, widget.store.workTypeOptions),
          widget.store.workTypeOptions,
          (v) => workType = v,
        ),
        Divider(height: 1, color: context.sanad.border),
        picker(
          'طريقة العمل',
          _shown(workMode, widget.store.workModeOptions),
          widget.store.workModeOptions,
          (v) => workMode = v,
        ),
        Divider(height: 1, color: context.sanad.border),
        picker(
          'الخبرة المطلوبة',
          _shown(experience, widget.store.experienceOptions),
          widget.store.experienceOptions,
          (v) => experience = v,
        ),
        const SizedBox(height: 12),
      ], icon: CupertinoIcons.location),
      section('شو المطلوب؟', [
        field(
          description,
          'وصف الشغل والمسؤوليات',
          lines: 5,
          max: 5000,
          hint: 'شو رح يعمل الشخص؟ وين وأي ساعات؟',
          helper: 'التفاصيل الواضحة بتسهّل وصول الشخص المناسب.',
        ),
        field(
          requirements,
          'المتطلبات',
          lines: 3,
          max: 2411,
          required: false,
          hint: 'كل متطلب على سطر مستقل',
          helper: 'اختياري',
        ),
      ], icon: CupertinoIcons.doc_text),
    ],
  );

  Widget stepTwo() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      section(
        'كيف بيتواصلوا معك؟',
        [
          field(
            phone,
            'رقم واتساب',
            required: false,
            keyboard: TextInputType.phone,
            max: 40,
            hint: 'الرقم المحلي',
            helper: 'رقم واتساب أو بريد إلكتروني واحد بيكفي.',
            countrySelector: phoneCountryButton(),
          ),
          MotionSize(
            duration: motionDuration(context, 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: phoneCountryOptions(),
          ),
          field(
            email,
            'البريد الإلكتروني',
            required: false,
            keyboard: TextInputType.emailAddress,
            max: 254,
            hint: 'name@example.com',
          ),
        ],
        subtitle: 'التواصل مباشر معك، بدون إنشاء حساب.',
        icon: CupertinoIcons.chat_bubble_2_fill,
      ),
      section('الراتب', [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('إضافة راتب', style: TextStyle(fontSize: 14)),
          subtitle: Text(
            'اختياري، لكنه بيوفّر وقتك ووقت المتقدم.',
            style: TextStyle(fontSize: 12, color: context.sanad.secondary),
          ),
          value: showSalary,
          onChanged: saving || submissionRecorded
              ? null
              : (value) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    showSalary = value;
                    changed = true;
                    expandedChoice = null;
                  });
                },
        ),
        MotionSize(
          duration: motionDuration(context, 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showSalary
              ? Column(
                  children: [
                    picker('العملة', currency, const [
                      'SYP',
                      'USD',
                    ], (v) => currency = v),
                    picker(
                      'فترة الراتب',
                      period,
                      jobSalaryPeriods,
                      (v) => period = v,
                    ),
                    const SizedBox(height: 12),
                    field(
                      minSalary,
                      'الراتب من',
                      required: false,
                      numeric: true,
                      max: 10,
                      helper: 'اختياري',
                    ),
                    field(
                      maxSalary,
                      'الراتب حتى',
                      required: false,
                      numeric: true,
                      max: 10,
                      helper: 'اختياري',
                    ),
                  ],
                )
              : Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'رح يظهر «الراتب عند التواصل».',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.sanad.secondary,
                    ),
                  ),
                ),
        ),
      ], icon: CupertinoIcons.money_dollar_circle),
      section('مدة الإعلان', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in [7, 14, 30])
              Semantics(
                selected: days == value,
                child: OutlinedButton(
                  onPressed: saving || submissionRecorded
                      ? null
                      : () => setState(() {
                          days = value;
                          changed = true;
                        }),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: days == value
                        ? context.sanad.tint
                        : context.sanad.surface,
                    side: BorderSide(
                      color: days == value
                          ? context.sanad.primary
                          : context.sanad.border,
                    ),
                  ),
                  child: Text('$value يوم'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ], icon: CupertinoIcons.calendar),
      section('قبل الإرسال', [
        Column(
          key: consentKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: saving || submissionRecorded
                  ? null
                  : (value) => setState(() {
                      consent = value ?? false;
                      changed = true;
                      consentError = !consent && tried;
                    }),
              title: const Text(
                'أوافق على نشر وسيلة التواصل مع الإعلان، وأؤكد أنني مخوّل بالنشر وأن معلومات الفرصة صحيحة.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            if (consentError)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'نحتاج موافقتك على نشر وسيلة التواصل.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'يُراجع الإعلان قبل النشر. لا نقبل فرصاً تطلب دفع مبالغ للتقديم. بتقدر تتابع إعلانك وتسحبه من الجهاز نفسه؛ احتفظ ببيانات التطبيق.',
          style: TextStyle(fontSize: 12, color: context.sanad.secondary),
        ),
        const SizedBox(height: 18),
      ], icon: CupertinoIcons.lock_shield),
    ],
  );

  Widget postIntro() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: context.sanad.isDark
              ? [
                  context.sanad.surface,
                  context.sanad.tint,
                  context.sanad.background,
                ]
              : const [Color(0xFFFFFFFF), Color(0xFFE7F0FA), Color(0xFFD3E6F7)],
        ),
        border: Border.all(color: context.sanad.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.sanad.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: AppIcon(
              CupertinoIcons.plus_app,
              color: context.sanad.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'خلّي الفرصة تلاقي صاحبها',
                  style: TextStyle(
                    color: context.sanad.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تفاصيل واضحة، تواصل مباشر، ومراجعة قبل النشر.',
                  style: TextStyle(
                    color: context.sanad.secondary,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget postStepHeader() {
    Widget pill(int index, String label) {
      final active = step == index;
      final done = step > index;
      return Expanded(
        child: AnimatedContainer(
          duration: motionDuration(context, 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? context.sanad.primary
                : done
                ? context.sanad.tint
                : context.sanad.surface.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? context.sanad.primary : context.sanad.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: .18)
                      : context.sanad.surface,
                  shape: BoxShape.circle,
                ),
                child: done && !active
                    ? AppIcon(
                        CupertinoIcons.checkmark,
                        size: 14,
                        color: context.sanad.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: active ? Colors.white : context.sanad.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : context.sanad.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            pill(0, 'التفاصيل'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AppIcon(
                CupertinoIcons.chevron_left,
                size: 14,
                color: context.sanad.secondary,
              ),
            ),
            pill(1, 'التواصل'),
          ],
        ),
        const SizedBox(height: 12),
        SanadStepTrack(value: (step + 1) / 2),
      ],
    );
  }

  Widget success() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeTransition(
          opacity: stepAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .92, end: 1).animate(
              CurvedAnimation(
                parent: stepAnimation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.sanad.tint,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                CupertinoIcons.check_mark,
                color: context.sanad.primary,
                size: 38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          widget.store.isDemo ? 'انحفظت التجربة!' : 'وصلتنا فرصتك!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          widget.store.isDemo
              ? 'انحفظ الإعلان محلياً للتجربة، وما اننشر للعامة.'
              : 'رح نراجع إعلانك قبل ظهوره للناس. بتلاقي حالته بصفحة إعلاناتك.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.sanad.secondary),
        ),
        const SizedBox(height: 28),
        section(title.text.trim(), [
          Text(
            '${company.text.trim()} · $city',
            style: TextStyle(color: context.sanad.secondary),
          ),
          const SizedBox(height: 12),
          Text(
            widget.store.isDemo
                ? 'إعلان تجريبي على هذا الجهاز'
                : 'قيد المراجعة',
            style: TextStyle(
              color: context.sanad.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
        ]),
        FilledButton(
          onPressed: exitPage,
          child: const Text('العودة إلى إعلاناتي'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        allowExit ||
        completed ||
        submissionRecorded ||
        (!changed && !saving && step == 0),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: ReferenceBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: context.sanad.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: sanadHeaderFill(context),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إضافة فرصة',
                style: TextStyle(
                  fontSize: kIsWeb ? 20 : 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                step == 0 ? 'التفاصيل أولاً' : 'التواصل والنشر',
                style: TextStyle(
                  color: context.sanad.secondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          leading: IconButton(
            tooltip: step == 1 && !completed ? 'العودة للتفاصيل' : 'رجوع',
            onPressed: saving ? null : back,
            icon: AppIcon(
              CupertinoIcons.chevron_right,
              color: context.sanad.ink,
            ),
          ),
          actions: [
            if (step == 1 && !completed)
              TextButton(
                onPressed: saving ? null : requestClose,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: const Text('إغلاق'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kIsWeb ? WebLayout.formMax : 640,
              ),
              child: completed
                  ? success()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: postStepHeader(),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scroll,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (confirmingExit) exitConfirmation(),
                                if (error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SignalCard(
                                      error!,
                                      onClose: submissionRecorded
                                          ? null
                                          : () => setState(() => error = null),
                                    ),
                                  ),
                                if (widget.store.isDemo)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: Text(
                                      'وضع تجريبي · الإعلان بينحفظ على هالجهاز فقط.',
                                      style: TextStyle(
                                        color: context.sanad.secondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ExcludeFocus(
                                  excluding:
                                      confirmingExit || submissionRecorded,
                                  child: IgnorePointer(
                                    ignoring:
                                        confirmingExit || submissionRecorded,
                                    child: FadeTransition(
                                      opacity: stepAnimation,
                                      child: SlideTransition(
                                        position:
                                            Tween<Offset>(
                                              begin: const Offset(.035, 0),
                                              end: Offset.zero,
                                            ).animate(
                                              CurvedAnimation(
                                                parent: stepAnimation,
                                                curve: Curves.easeOutCubic,
                                              ),
                                            ),
                                        child: Form(
                                          key: forms[step],
                                          child: step == 0
                                              ? stepOne()
                                              : stepTwo(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          decoration: BoxDecoration(
                            color: context.sanad.surface,
                            border: Border(
                              top: BorderSide(color: context.sanad.border),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 54),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: submissionRecorded
                                    ? exitPage
                                    : saving || confirmingExit
                                    ? null
                                    : next,
                                child: saving
                                    ? const SanadLoader(
                                        size: 26,
                                        label: 'عم نرسل…',
                                      )
                                    : Text(
                                        submissionRecorded
                                            ? 'العودة إلى إعلاناتي'
                                            : step == 0
                                            ? 'التالي: التواصل والراتب'
                                            : widget.store.isDemo
                                            ? 'حفظ إعلان تجريبي'
                                            : 'إرسال للمراجعة',
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}
