import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/job_filters.dart';

/// A normal page keeps the home context in the navigation stack, while allowing
/// every filter to remain readable with a keyboard or larger accessibility text.
Future<JobFilters?> showFilters(BuildContext context, JobsStore store) =>
    openPage<JobFilters>(context, FilterSheet(store: store));

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
  String? amountError, currencyError, periodError;
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
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
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
                                minimumSize: const Size(48, 48),
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
    setState(() => applying = true);
    final result = filters.copyWith(minSalary: number);
    widget.store.updateFilters(result);
    if (save) await widget.store.saveSearch();
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

  @override
  Widget build(BuildContext context) => ReferenceBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: context.sanad.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: sanadHeaderFill(context),
        title: const Text('فلتر الفرص'),
        leading: IconButton(
          tooltip: 'رجوع بدون تطبيق',
          onPressed: applying ? null : () => Navigator.of(context).pop(),
          icon: AppIcon(CupertinoIcons.chevron_right, color: context.sanad.ink),
        ),
        actions: [
          TextButton(
            onPressed: applying ? null : reset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('إعادة ضبط'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'قرّب النتائج للشغل اللي بدك ياه.',
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
                          choices(
                            'المحافظة',
                            filters.city,
                            widget.store.placeOptions,
                            (v) => filters = filters.copyWith(city: v),
                          ),
                          Divider(height: 1, color: context.sanad.border),
                          choices(
                            'المجال',
                            filters.category,
                            widget.store.categoryOptions,
                            (v) => filters = filters.copyWith(category: v),
                          ),
                        ]),
                        section('طريقة الشغل', [
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
                            widget.store.experienceOptions,
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
                          choices(
                            'عملة الراتب',
                            filters.currency,
                            const ['SYP', 'USD'],
                            (v) => filters = filters.copyWith(currency: v),
                            sectionKey: currencyKey,
                            validation: currencyError,
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
                            'بنقارن المبالغ فقط لما تتطابق العملة وفترة الراتب.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.sanad.secondary,
                            ),
                          ),
                        ]),
                        section('ترتيب النتائج', [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
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
                                      minimumSize: const Size(48, 48),
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
                        section('ارجع لهالبحث بسهولة', [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'احفظ هالبحث',
                              style: TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              'بيضل على هالجهاز، وبتلاقي نتائجه بصفحة «على بالك».',
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
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  decoration: BoxDecoration(
                    color: context.sanad.surface,
                    border: Border(
                      top: BorderSide(color: context.sanad.border),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ListenableBuilder(
                      listenable: widget.store,
                      builder: (context, _) => FilledButton(
                        onPressed: applying ? null : apply,
                        child: applying
                            ? const SanadLoader(
                                size: 26,
                                label: 'عم نحفظ اختياراتك…',
                              )
                            : AnimatedSwitcher(
                                duration: motionDuration(context, 180),
                                child: Text(
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
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
