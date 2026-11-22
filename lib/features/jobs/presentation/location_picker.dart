import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/design.dart';
import '../data/jobs_store.dart';
import '../domain/job_filters.dart';
import '../domain/job_geography.dart';
import '../domain/job_regions.dart';
import 'geography_picker.dart';
import 'country_flag.dart';

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    super.key,
    required this.store,
    required this.initial,
    this.applyToStore = false,
  });
  final JobsStore store;
  final JobFilters initial;
  final bool applyToStore;
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late String? country = widget.initial.country;
  late final city = TextEditingController(text: widget.initial.city ?? '');
  final form = GlobalKey<FormState>();
  Future<void> changeCountry() async {
    final value = await chooseJobCountry(
      context,
      selected: country,
      allowAll: true,
    );
    if (!mounted || value == null || value == (country ?? '')) return;
    setState(() {
      country = value.isEmpty ? null : value;
      city.clear();
    });
  }

  Future<void> changeRegion() async {
    if (country == null) return;
    final value = await chooseJobRegion(
      context,
      country: country!,
      selected: city.text,
      allowAll: true,
    );
    if (mounted && value != null) setState(() => city.text = value);
  }

  void apply() {
    if (!form.currentState!.validate()) return;
    final result = widget.initial.copyWith(
      country: country,
      city: country == null || city.text.trim().isEmpty
          ? null
          : city.text.trim(),
    );
    if (widget.applyToStore) widget.store.updateFilters(result);
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReferenceBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('مكان البحث'),
          flexibleSpace: sanadHeaderFill(context, blur: false),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(20),
          child: SanadPrimaryButton(
            onPressed: apply,
            child: const Text('عرض الفرص'),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'اختر المحافظة للبحث عن فرص عمل في سوريا.',
                      style: TextStyle(color: context.sanad.secondary),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: countryFor(country) == null
                          ? null
                          : CountryFlag(country: countryFor(country)!),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('البلد'),
                      subtitle: Text(countryLabel(country)),
                      trailing: AppIcon(
                        CupertinoIcons.chevron_left,
                        color: context.sanad.primary,
                        size: 20,
                      ),
                      onTap: null,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: country != null,
                      leading: AppIcon(
                        CupertinoIcons.location,
                        color: context.sanad.primary,
                      ),
                      title: Text(regionLabel(country)),
                      subtitle: Text(
                        city.text.isEmpty ? 'كل المحافظات' : city.text,
                      ),
                      trailing: AppIcon(
                        CupertinoIcons.chevron_left,
                        color: context.sanad.primary,
                        size: 20,
                      ),
                      onTap: changeRegion,
                    ),
                    if (country == null)
                      const Text('حدد بلداً أولاً لاختيار المحافظة.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
