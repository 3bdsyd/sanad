import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_links.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/theme_controls.dart';
import '../../../core/web_layout.dart';
import '../data/jobs_store.dart';
import 'welcome.dart';
import '../../ads/data/ads_controller.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.store});
  final JobsStore store;
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String? feedback;
  bool busy = false;
  Future<void> openLink(String value) async {
    try {
      if (!await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      )) {
        if (mounted) {
          setState(() => feedback = 'تعذّر فتح الرابط. حاول مرة أخرى.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => feedback = 'تعذّر فتح الرابط. تحقق من الاتصال.');
      }
    }
  }

  Future<void> restore() async {
    setState(() => busy = true);
    try {
      await widget.store.unhideAllEmployers();
      if (mounted) {
        setState(
          () => feedback = 'تمت استعادة الجهات المخفية إلى نتائج البحث.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => feedback = 'تعذّر استعادة الجهات. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReferenceBackdrop(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: kIsWeb
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: sanadHeaderFill(context, blur: false),
              title: const Text('عن سند'),
              leading: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.pop(context),
                icon: const AppIcon(CupertinoIcons.chevron_right),
              ),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: kIsWeb ? WebLayout.contentMax : 680,
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              30 + (kIsWeb ? MediaQuery.paddingOf(context).bottom : 0),
            ),
            children: [
              if (kIsWeb) ...[
                Text(
                  'عن سند',
                  style: TextStyle(
                    color: context.sanad.ink,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const Center(child: SanadLogo(size: 88)),
              const SizedBox(height: 18),
              const Text(
                'منصة فرص العمل والتواصل المهني.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'يقرّب سند الباحثين عن عمل من أصحاب الفرص. تصفّح الفرص واحفظها وتواصل دون حساب.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.sanad.secondary),
              ),
              const SizedBox(height: 24),
              const Glass(child: SanadThemePicker()),
              const SizedBox(height: 14),
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حماية الخصوصية',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'الفلاتر وتفضيلاتك على جهازك، والمحفوظات مرتبطة بخدمة سند أيضاً. عند نشر إعلان، تُرسل تفاصيله ووسيلة التواصل وتظهر بعد الموافقة. لا نطلب موقعك الدقيق أو جهات اتصالك.',
                      style: TextStyle(color: context.sanad.secondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'مفتاح إدارة إعلانك محفوظ على الجهاز. مسح بيانات التطبيق قد يفقدك إمكانية إدارته.',
                      style: TextStyle(color: context.sanad.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إرشادات التقديم الآمن',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'لا تدفع مقابل وعد بالتوظيف، ولا ترسل وثائق حساسة قبل التحقق من الجهة. الإبلاغ موجود داخل تفاصيل كل فرصة.',
                      style: TextStyle(color: context.sanad.secondary),
                    ),
                  ],
                ),
              ),
              if (widget.store.isDemo)
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: SignalCard(
                    'هذه نسخة عرض بفرص وجهات افتراضية. الإعلانات التي تضيفها هنا تبقى تجريبية على جهازك.',
                  ),
                ),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: SignalCard(
                    feedback!,
                    onClose: () => setState(() => feedback = null),
                  ),
                ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: AdsController.instance,
                builder: (context, _) => SanadActions(
                  vertical: true,
                  children: [
                    if (AdsController.instance.privacyRequired)
                      TextButton.icon(
                        onPressed: () async {
                          final success = await AdsController.instance
                              .editPrivacy();
                          if (mounted && !success) {
                            setState(
                              () => feedback =
                                  'تعذّر فتح خيارات الإعلانات. حاول مجدداً.',
                            );
                          }
                        },
                        icon: const AppIcon(
                          CupertinoIcons.lock_shield,
                          size: 18,
                        ),
                        label: const Text('خيارات خصوصية الإعلانات'),
                      ),
                    if (AppLinks.hasPrivacy)
                      TextButton.icon(
                        onPressed: () => openLink(AppLinks.privacy),
                        icon: const AppIcon(
                          CupertinoIcons.lock_shield,
                          size: 18,
                        ),
                        label: const Text('سياسة الخصوصية الكاملة'),
                      ),
                    if (AppLinks.hasSupport)
                      TextButton.icon(
                        onPressed: () => openLink(AppLinks.support),
                        icon: const AppIcon(
                          CupertinoIcons.chat_bubble,
                          size: 18,
                        ),
                        label: const Text('تواصل مع فريق سند'),
                      ),
                    if (widget.store.hiddenEmployerCount > 0)
                      TextButton(
                        onPressed: busy ? null : restore,
                        child: Text(
                          busy
                              ? 'جارٍ الاستعادة…'
                              : 'إظهار ${widget.store.hiddenEmployerCount} جهة مخفية',
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => openPage<void>(
                        context,
                        Builder(
                          builder: (c) =>
                              WelcomePage(onContinue: () => Navigator.pop(c)),
                        ),
                      ),
                      icon: const AppIcon(CupertinoIcons.sparkles, size: 18),
                      label: const Text('شاشة البداية'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
