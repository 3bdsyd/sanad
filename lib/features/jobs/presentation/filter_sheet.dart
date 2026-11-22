import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/web_layout.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/job_filters.dart';
import '../domain/job_geography.dart';
import 'geography_picker.dart';
import 'location_picker.dart';
import 'country_flag.dart';
import '../../platform/presentation/auth_page.dart';

/// A normal page keeps the home context in the navigation stack, while allowing
/// every filter to remain readable with a keyboard or larger accessibility text.
Future<JobFilters?> showFilters(BuildContext context, JobsStore store) =>
    openPage<JobFilters>(context, FilterSheet(store: store));

/// Country and optional city are chosen together on a normal page.
Future<void> showCityFilter(BuildContext context, JobsStore store) async {
  await openPage<JobFilters>(
    context,
    LocationPickerPage(
      store: store,
      initial: store.filters,
      applyToStore: true,
    ),
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.store});
  final JobsStore store;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> with WidgetsBindingObserver {
  late JobFilters filters = widget.store.filters;
  late final minimum = TextEditingController(
    text: filters.minSalary?.toString() ?? '',
  );
  final scroll = ScrollController();
  final minimumFocus = FocusNode();
  final salaryKey = GlobalKey();
  final currencyKey = GlobalKey();
  final periodKey = GlobalKey();
  Timer? revealTimer;
  String? amountError, currencyError, periodError, saveError;
  String? expanded;
  bool save = false, applying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    minimumFocus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (minimumFocus.hasFocus) _scheduleReveal(salaryKey);
  }

  @override
  void didChangeMetrics() {
    if (minimumFocus.hasFocus) _scheduleReveal(salaryKey);
  }

  void _scheduleReveal(GlobalKey key) {
    revealTimer?.cancel();
    revealTimer = Timer(const Duration(milliseconds: 330), () {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .18,
          duration: motionDuration(context, 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    revealTimer?.cancel();
    minimumFocus.removeListener(_focusChanged);
    minimumFocus.dispose();
    minimum.dispose();
    scroll.dispose();
    super.dispose();
  }

  String labelFor(String value) => switch (value) {
    'SYP' => 'ليرة سورية',
    'USD' => 'دولار أمريكي',
    'AED' => 'درهم إماراتي',
    'SAR' => 'ريال سعودي',
    'شهري' => 'شهرياً',
    'أسبوعي' => 'أسبوعياً',
    'يومي' => 'يومياً',
    _ when jobExperienceFilterLevels.contains(value) => experienceDisplayLabel(
      value,
    ),
    _ => value,
  };

  Widget choices(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> changed, {
    GlobalKey? sectionKey,
    String? validation,
  }) {
    final isOpen = expanded == label;
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: isOpen,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            minVerticalPadding: 12,
            leading: AppIcon(
              sanadPickerIcon(label),
              color: context.sanad.primary,
              size: 22,
            ),
            title: Text(label, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              value == null ? 'الكل' : labelFor(value),
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
                size: 17,
                color: context.sanad.secondary,
              ),
            ),
            onTap: applying
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() => expanded = isOpen ? null : label);
                  },
          ),
        ),
        MotionSize(
          duration: motionDuration(context, 230),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SanadActions(
                      children: [
                        for (final item in <String?>[null, ...values])
                          Semantics(
                            selected: value == item,
                            child: OutlinedButton(
                              onPressed: applying
                                  ? null
                                  : () => setState(() {
                                      changed(item);
                                      currencyError = null;
                                      periodError = null;
                                    }),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: value == item
                                    ? context.sanad.primary
                                    : context.sanad.ink,
                                backgroundColor: value == item
                                    ? context.sanad.tint
                                    : context.sanad.surface,
                                minimumSize: compactWebControls(context)
                                    ? const Size(44, 44)
                                    : const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                side: BorderSide(
                                  color: value == item
                                      ? context.sanad.primary
                                      : context.sanad.border,
                                ),
                              ),
                              child: Text(
                                item == null ? 'الكل' : labelFor(item),
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
        if (validation != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                validation,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> changeLocation() async {
    final result = await openPage<JobFilters>(
      context,
      LocationPickerPage(store: widget.store, initial: filters),
    );
    if (mounted && result != null) setState(() => filters = result);
  }

  Future<void> changeCurrency() async {
    final value = await chooseJobCurrency(
      context,
      selected: filters.currency,
      allowAll: true,
    );
    if (mounted && value != null) {
      setState(() {
        filters = filters.copyWith(currency: value.isEmpty ? null : value);
        currencyError = null;
      });
    }
  }

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: context.sanad.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: context.sanad.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );

  JobFilters get previewFilters =>
      filters.copyWith(minSalary: int.tryParse(normalizeSearch(minimum.text)));

  String? _countKey;
  Future<int?>? _countFuture;

  /// Server total for the site's paged catalog, fetched once per selection.
  Future<int?> get _serverCount {
    final key = previewFilters.toJson().toString();
    if (key != _countKey) {
      _countKey = key;
      _countFuture = widget.store.countFor(previewFilters);
    }
    return _countFuture!;
  }

  Future<void> apply() async {
    if (applying) return;
    FocusScope.of(context).unfocus();
    final raw = normalizeSearch(minimum.text);
    final number = raw.isEmpty ? null : int.tryParse(raw);
    final needsComparison = number != null || filters.sort == 'salary';
    setState(() {
      amountError =
          raw.isNotEmpty &&
              (number == null || number < 0 || number > 1000000000)
          ? 'اكتب مبلغاً صحيحاً من ٠ إلى مليار، أو اتركه فارغاً.'
          : null;
      currencyError = needsComparison && filters.currency == null
          ? 'حدّد العملة حتى نقارن رواتب من نفس النوع.'
          : null;
      periodError = needsComparison && filters.salaryPeriod == null
          ? 'حدّد فترة الراتب حتى تكون المقارنة واضحة.'
          : null;
      if (currencyError != null) expanded = 'عملة الراتب';
      if (currencyError == null && periodError != null) {
        expanded = 'فترة الراتب';
      }
    });
    if (amountError != null) {
      minimumFocus.requestFocus();
      _scheduleReveal(salaryKey);
      return;
    }
    if (currencyError != null || periodError != null) {
      _scheduleReveal(currencyError != null ? currencyKey : periodKey);
      return;
    }
    if (save &&
            widget.store.accountsEnabled &&
            !await ensureAccount(
              context,
              widget.store.platform,
              reason: 'لحفظ البحث وإشعارات الفرص الجديدة',
            ) ||
        !mounted) {
      return;
    }
    setState(() => applying = true);
    final result = filters.copyWith(minSalary: number);
    widget.store.updateFilters(result);
    if (save) {
      try {
        await widget.store.saveSearch();
      } catch (e) {
        if (mounted) {
          setState(() {
            applying = false;
            saveError = e.toString();
          });
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  void reset() {
    FocusScope.of(context).unfocus();
    setState(() {
      filters = const JobFilters();
      minimum.clear();
      amountError = currencyError = periodError = null;
      expanded = null;
      save = false;
    });
  }

  Widget bottomAction() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    decoration: BoxDecoration(
      color: context.sanad.surface,
      border: Border(top: BorderSide(color: context.sanad.border)),
    ),
    child: SizedBox(
      width: double.infinity,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => SanadPrimaryButton(
          onPressed: applying ? null : apply,
          child: applying
              ? const SanadLoader(size: 26, label: 'جارٍ حفظ اختياراتك…')
              : AnimatedSwitcher(
                  duration: motionDuration(context, 180),
                  child: widget.store.pagedCatalog
                      ? FutureBuilder<int?>(
                          key: ValueKey(previewFilters.toJson().toString()),
                          future: _serverCount,
                          builder: (context, snapshot) => Text(
                            snapshot.data == null
                                ? 'عرض الفرص'
                                : 'عرض ${snapshot.data} فرصة',
                          ),
                        )
                      : Text(
                          'عرض ${previewFilters.apply(widget.store.discoverableJobs, widget.store.query).length} فرصة',
                          key: ValueKey(
                            previewFilters
                                .apply(
                                  widget.store.discoverableJobs,
                                  widget.store.query,
                                )
                                .length,
                          ),
                        ),
                ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ReferenceBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: kIsWeb
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: context.sanad.ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: sanadHeaderFill(context, blur: false),
              title: const Text('فلتر الفرص'),
              leading: IconButton(
                tooltip: 'رجوع بدون تطبيق',
                onPressed: applying ? null : () => Navigator.of(context).pop(),
                icon: AppIcon(
                  CupertinoIcons.chevron_right,
                  color: context.sanad.ink,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: applying ? null : reset,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('إعادة ضبط'),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: SafeArea(
        top: false,
        bottom: !kIsWeb,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: kIsWeb ? WebLayout.contentMax : 640,
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      24 + (kIsWeb ? MediaQuery.paddingOf(context).bottom : 0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (kIsWeb) ...[
                          SanadActionHeader(
                            title: Text(
                              'فلتر الفرص',
                              style: TextStyle(
                                color: context.sanad.ink,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: applying ? null : reset,
                                child: const Text('إعادة ضبط'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          'اعثر على فرص تلائم احتياجاتك.',
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 14,
                          ),
                        ),
                        if (widget.store.query.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'ضمن البحث: ${widget.store.query}',
                              style: TextStyle(color: context.sanad.primary),
                            ),
                          ),
                        const SizedBox(height: 20),
                        section('المكان والمجال', [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('البلد والمحافظة'),
                            leading: countryFor(filters.country) == null
                                ? const AppIcon(CupertinoIcons.globe, size: 22)
                                : CountryFlag(
                                    country: countryFor(filters.country)!,
                                  ),
                            subtitle: Text(filters.locationLabel),
                            trailing: AppIcon(
                              CupertinoIcons.chevron_left,
                              color: context.sanad.primary,
                              size: 18,
                            ),
                            onTap: applying ? null : changeLocation,
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: AppIcon(
                              sanadPickerIcon('المجال'),
                              color: context.sanad.primary,
                            ),
                            title: const Text('المجال'),
                            subtitle: Text(filters.category ?? 'كل المجالات'),
                            trailing: AppIcon(
                              CupertinoIcons.chevron_left,
                              color: context.sanad.primary,
                              size: 18,
                            ),
                            onTap: applying
                                ? null
                                : () async {
                                    final value = await chooseJobCategory(
                                      context,
                                      values: widget.store.categoryOptions,
                                      selected: filters.category,
                                      allowAll: true,
                                      translations: {
                                        for (final field in widget.store.fields)
                                          field.nameAr: field.nameEn,
                                      },
                                    );
                                    if (mounted && value != null) {
                                      setState(
                                        () => filters = filters.copyWith(
                                          category: value.isEmpty
                                              ? null
                                              : value,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ]),
                        section('طريقة العمل', [
                          choices(
                            'نوع الدوام',
                            filters.workType,
                            widget.store.workTypeOptions,
                            (v) => filters = filters.copyWith(workType: v),
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          choices(
                            'طريقة العمل',
                            filters.workMode,
                            widget.store.workModeOptions,
                            (v) => filters = filters.copyWith(workMode: v),
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          choices(
                            'الخبرة',
                            filters.experience,
                            jobExperienceFilterLevels,
                            (v) => filters = filters.copyWith(experience: v),
                          ),
                        ]),
                        section('الراتب', [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'راتب معلن فقط',
                              style: TextStyle(fontSize: 14),
                            ),
                            value: filters.salaryOnly,
                            onChanged: applying
                                ? null
                                : (v) => setState(
                                    () => filters = filters.copyWith(
                                      salaryOnly: v,
                                    ),
                                  ),
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          Column(
                            key: currencyKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('عملة الراتب'),
                                leading: AppIcon(
                                  CupertinoIcons.money_dollar_circle,
                                  color: context.sanad.primary,
                                  size: 22,
                                ),
                                subtitle: Text(
                                  filters.currency == null
                                      ? 'كل العملات'
                                      : currencyLabel(filters.currency!),
                                ),
                                onTap: applying ? null : changeCurrency,
                                trailing: AppIcon(
                                  CupertinoIcons.chevron_left,
                                  color: context.sanad.primary,
                                  size: 18,
                                ),
                              ),
                              if (currencyError != null)
                                Text(
                                  currencyError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          choices(
                            'فترة الراتب',
                            filters.salaryPeriod,
                            jobSalaryPeriods,
                            (v) => filters = filters.copyWith(salaryPeriod: v),
                            sectionKey: periodKey,
                            validation: periodError,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: salaryKey,
                            controller: minimum,
                            focusNode: minimumFocus,
                            onTap: () => _scheduleReveal(salaryKey),
                            enabled: !applying,
                            keyboardType: TextInputType.number,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            textInputAction: TextInputAction.done,
                            scrollPadding: const EdgeInsets.all(24),
                            onChanged: (_) =>
                                setState(() => amountError = null),
                            onSubmitted: (_) => minimumFocus.unfocus(),
                            decoration: InputDecoration(
                              labelText: 'الحد الأدنى للراتب',
                              hintText: 'اختياري',
                              errorText: amountError,
                              errorMaxLines: 3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'تُقارن الرواتب عندما تتطابق العملة وفترة الراتب.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.sanad.secondary,
                            ),
                          ),
                        ]),
                        section('ترتيب النتائج', [
                          SanadActions(
                            children: [
                              for (final option in [
                                ('newest', 'الأحدث'),
                                ('salary', 'الراتب الأعلى'),
                              ])
                                Semantics(
                                  selected: filters.sort == option.$1,
                                  child: OutlinedButton(
                                    onPressed: applying
                                        ? null
                                        : () => setState(
                                            () => filters = filters.copyWith(
                                              sort: option.$1,
                                            ),
                                          ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: compactWebControls(context)
                                          ? const Size(44, 44)
                                          : const Size(48, 48),
                                      backgroundColor: filters.sort == option.$1
                                          ? context.sanad.tint
                                          : context.sanad.surface,
                                      side: BorderSide(
                                        color: filters.sort == option.$1
                                            ? context.sanad.primary
                                            : context.sanad.border,
                                      ),
                                    ),
                                    child: Text(option.$2),
                                  ),
                                ),
                            ],
                          ),
                        ]),
                        section('احفظ هذا البحث للعودة إليه بسهولة', [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'حفظ البحث',
                              style: TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              'سيُحفظ على هذا الجهاز، وستظهر نتائجه في صفحة «المحفوظات».',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.sanad.secondary,
                              ),
                            ),
                            value: save,
                            onChanged: applying
                                ? null
                                : (value) => setState(() => save = value),
                          ),
                        ]),
                        if (saveError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SignalCard(saveError!),
                          ),
                        if (kIsWeb) bottomAction(),
                      ],
                    ),
                  ),
                ),
                if (!kIsWeb) bottomAction(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
