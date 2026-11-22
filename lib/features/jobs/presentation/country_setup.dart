import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../data/jobs_store.dart';
import '../domain/job_geography.dart';
import 'country_flag.dart';

class CountryGate extends StatelessWidget {
  const CountryGate({super.key, required this.store, required this.child});
  final JobsStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) =>
        store.needsCountryChoice ? CountrySetupPage(store: store) : child,
  );
}

class CountrySetupPage extends StatefulWidget {
  const CountrySetupPage({super.key, required this.store});
  final JobsStore store;
  @override
  State<CountrySetupPage> createState() => _CountrySetupPageState();
}

class _CountrySetupPageState extends State<CountrySetupPage> {
  String query = '';
  String? selected, error;
  bool saving = false;

  Future<void> submit() async {
    if (selected == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.confirmCountry(selected!);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'تعذّر حفظ البلد. يرجى المحاولة مجدداً.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = availableJobCountries
        .where(
          (country) => locationSearchKey(
            '${country.name} ${country.englishName} ${country.code} ${country.aliases.join(' ')}',
          ).contains(locationSearchKey(query)),
        )
        .toList();
    return PopScope(
      canPop: false,
      child: ReferenceBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('حدد بلد البحث'),
            flexibleSpace: sanadHeaderFill(context, blur: false),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(20),
            child: SanadPrimaryButton(
              onPressed: selected == null || saving ? null : submit,
              child: Text(saving ? 'جارٍ الحفظ…' : 'عرض فرص العمل'),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (query.isEmpty)
                            const Text(
                              'اختر البلد الذي ترغب في البحث عن عمل فيه. يمكنك تغييره لاحقاً من خيارات البحث.',
                            ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('country_search'),
                            onChanged: (value) => setState(() => query = value),
                            decoration: const InputDecoration(
                              labelText: 'البحث عن بلد',
                              prefixIcon: AppIcon(
                                CupertinoIcons.search,
                                size: 20,
                              ),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(error!),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (options.isEmpty)
                    const SliverToBoxAdapter(
                      child: Center(child: Text('لا توجد بلدان مطابقة للبحث.')),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList.builder(
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final country = options[index];
                        return ListTile(
                          selected: selected == country.code,
                          leading: CountryFlag(country: country),
                          title: Text(country.name),
                          trailing: selected == country.code
                              ? AppIcon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: context.sanad.primary,
                                )
                              : null,
                          onTap: saving
                              ? null
                              : () {
                                  FocusScope.of(context).unfocus();
                                  setState(() => selected = country.code);
                                },
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
