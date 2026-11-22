import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../domain/job_geography.dart';
import '../domain/job_regions.dart';
import 'country_flag.dart';

Future<String?> chooseJobRegion(
  BuildContext context, {
  required String country,
  String? selected,
  bool allowAll = false,
}) => openPage<String>(
  context,
  GeographyPickerPage(
    title: regionLabel(country),
    selected: selected ?? '',
    options: [
      if (allowAll)
        const GeographyOption('', 'كل المحافظات', 'عرض فرص البلد كله'),
      for (final region in regionsFor(country))
        GeographyOption(
          region.name,
          region.name,
          region.englishName,
          search: '${region.code} ${region.isoName}',
        ),
    ],
  ),
);

Future<String?> chooseJobCategory(
  BuildContext context, {
  required List<String> values,
  String? selected,
  bool allowAll = false,
  Map<String, String> translations = const {},
}) => openPage<String>(
  context,
  GeographyPickerPage(
    title: 'المجال',
    selected: selected ?? '',
    options: [
      if (allowAll)
        const GeographyOption('', 'كل المجالات', 'عرض جميع التخصصات'),
      for (final value in values)
        GeographyOption(value, value, translations[value] ?? 'تخصص العمل'),
    ],
  ),
);

Future<String?> chooseJobCountry(
  BuildContext context, {
  String? selected,
  bool allowAll = false,
}) => openPage<String>(
  context,
  GeographyPickerPage(
    title: 'البلد',
    selected: selected ?? '',
    options: [
      for (final country in availableJobCountries)
        GeographyOption(
          country.code,
          country.name,
          '${country.englishName} · ${country.code}',
          search: country.aliases.join(' '),
          countryCode: country.code,
        ),
    ],
  ),
);

Future<String?> chooseJobCurrency(
  BuildContext context, {
  String? selected,
  bool allowAll = false,
}) => openPage<String>(
  context,
  GeographyPickerPage(
    title: 'عملة الراتب',
    selected: selected ?? '',
    options: [
      if (allowAll)
        const GeographyOption('', 'كل العملات', 'عرض الرواتب دون تحديد عملة'),
      for (final entry in jobCurrencyNames.entries)
        GeographyOption(entry.key, entry.value, entry.key),
    ],
  ),
);

class GeographyOption {
  const GeographyOption(
    this.value,
    this.title,
    this.subtitle, {
    this.search = '',
    this.countryCode,
  });
  final String value, title, subtitle, search;
  final String? countryCode;
}

class GeographyPickerPage extends StatefulWidget {
  const GeographyPickerPage({
    super.key,
    required this.title,
    required this.selected,
    required this.options,
  });
  final String title, selected;
  final List<GeographyOption> options;
  @override
  State<GeographyPickerPage> createState() => _GeographyPickerPageState();
}

class _GeographyPickerPageState extends State<GeographyPickerPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final key = locationSearchKey(query);
    final options = widget.options
        .where(
          (o) => locationSearchKey(
            '${o.title} ${o.subtitle} ${o.search}',
          ).contains(key),
        )
        .toList();
    return ReferenceBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title),
          flexibleSpace: sanadHeaderFill(context, blur: false),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      onChanged: (value) => setState(() => query = value),
                      decoration: InputDecoration(
                        labelText: 'ابحث عن ${widget.title}',
                        hintText: 'الاسم بالعربي أو الإنكليزي أو الرمز',
                        prefixIcon: AppIcon(
                          CupertinoIcons.search,
                          color: context.sanad.primary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: options.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد نتائج مطابقة. يرجى استخدام عبارة بحث أخرى.',
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options[index];
                              final selected = widget.selected == option.value;
                              return ListTile(
                                leading: option.countryCode == null
                                    ? null
                                    : CountryFlag(
                                        country: countryFor(
                                          option.countryCode,
                                        )!,
                                      ),
                                selected: selected,
                                selectedTileColor: context.sanad.tint,
                                title: Text(option.title),
                                subtitle: Text(option.subtitle),
                                trailing: selected
                                    ? AppIcon(
                                        CupertinoIcons.checkmark,
                                        color: context.sanad.primary,
                                        size: 20,
                                      )
                                    : AppIcon(
                                        CupertinoIcons.chevron_left,
                                        color: context.sanad.secondary,
                                        size: 16,
                                      ),
                                onTap: () =>
                                    Navigator.of(context).pop(option.value),
                              );
                            },
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
}
