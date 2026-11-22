import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../../jobs/data/jobs_store.dart';
import '../../jobs/presentation/about_page.dart';
import '../data/platform_store.dart';
import '../domain/platform_models.dart';
import 'applications_page.dart';
import 'auth_page.dart';
import 'chat_page.dart';
import 'complaints_page.dart';
import 'platform_ui.dart';
import 'publisher_panel.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.store});
  final JobsStore store;
  Future<void> protected(BuildContext context, Widget page) async {
    if (await ensureAccount(context, store.platform) && context.mounted) {
      await platformRoute<void>(context, page);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'حسابي',
    child: ListenableBuilder(
      listenable: store.platform,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SanadLogo(size: 48),
                const SizedBox(height: 18),
                Text(
                  store.platform.user?.name ?? 'خطوتك المهنية التالية',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  store.platform.signedIn
                      ? store.platform.user!.email
                      : 'حساب واحد لحفظ الفرص والتقديم والتواصل مع جهات العمل.',
                  style: TextStyle(color: context.sanad.secondary, height: 1.8),
                ),
                const SizedBox(height: 16),
                if (store.platform.user case final member?) ...[
                  ProfileProgress(member: member),
                  const SizedBox(height: 16),
                ],
                SanadPrimaryButton(
                  onPressed: () => store.platform.signedIn
                      ? platformRoute<void>(
                          context,
                          ProfilePage(store: store.platform),
                        )
                      : ensureAccount(context, store.platform),
                  child: Text(
                    store.platform.signedIn
                        ? 'الملف المهني'
                        : 'تسجيل الدخول أو إنشاء حساب',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AccountDestination(
            title: 'طلباتي',
            subtitle: 'الفرص التي تقدمت إليها وحالة كل طلب',
            icon: CupertinoIcons.doc_text,
            onTap: () => protected(context, ApplicationsPage(store: store)),
          ),
          const SizedBox(height: 12),
          AccountDestination(
            title: 'الرسائل',
            subtitle: 'تواصل بشأن الطلبات والفرص',
            icon: CupertinoIcons.chat_bubble_2,
            onTap: () =>
                protected(context, ConversationsPage(store: store.platform)),
          ),
          const SizedBox(height: 12),
          AccountDestination(
            title: 'إعلاناتك',
            subtitle: 'إدارة الفرص ومراجعة المتقدمين',
            icon: CupertinoIcons.briefcase,
            onTap: () => platformRoute<void>(
              context,
              PlatformScaffold(
                title: 'إعلاناتك',
                child: PublisherPanel(store: store),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AccountDestination(
            title: 'الشكاوى والدعم',
            subtitle: 'أرسل مشكلة وتابع رد فريق الدعم',
            icon: CupertinoIcons.bubble_left_bubble_right,
            onTap: () =>
                protected(context, ComplaintsPage(store: store.platform)),
          ),
          const SizedBox(height: 12),
          AccountDestination(
            title: 'تفضيلات الإشعارات',
            subtitle: 'الفرص المطابقة والطلبات والرسائل',
            icon: CupertinoIcons.bell,
            onTap: () => protected(
              context,
              NotificationPreferencesPage(store: store.platform),
            ),
          ),
          const SizedBox(height: 12),
          AccountDestination(
            title: 'عن سند والخصوصية',
            subtitle: 'معلومات التطبيق وسياسة الخصوصية',
            icon: CupertinoIcons.info_circle,
            onTap: () => platformRoute<void>(context, AboutPage(store: store)),
          ),
        ],
      ),
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.store});
  final PlatformStore store;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.store.user?.name);
  late final headline = TextEditingController(
    text: widget.store.user?.headline,
  );
  late final phone = TextEditingController(text: widget.store.user?.phone);
  late final summary = TextEditingController(text: widget.store.user?.summary);
  late final skills = TextEditingController(
    text: widget.store.user?.skills.join('، '),
  );
  late final languages = TextEditingController(
    text: widget.store.user?.languages.join('، '),
  );
  late final experience = TextEditingController(
    text: widget.store.user?.experienceYears?.toString(),
  );
  bool busy = false, logoutConfirm = false;
  String? message;
  @override
  void dispose() {
    name.dispose();
    headline.dispose();
    phone.dispose();
    summary.dispose();
    skills.dispose();
    languages.dispose();
    experience.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(invalid.first.context, alignment: 0.2);
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.store.updateProfile({
        'name': name.text.trim(),
        'headline': headline.text.trim(),
        'phone': phone.text.trim(),
        'summary': summary.text.trim(),
        'skills': profileLabels(skills.text),
        'languages': profileLabels(languages.text),
        'experience_years': profileYears(experience.text),
      });
      if (mounted) setState(() => message = 'تم حفظ ملفك المهني.');
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    setState(() => busy = true);
    try {
      await widget.store.logout();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'الملف المهني',
    account: widget.store,
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'عرّف جهات العمل بخبرتك',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'يُشارك ملفك مع صاحب الفرصة عندما تتقدم إليها فقط.',
            style: TextStyle(color: context.sanad.secondary, height: 1.8),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'الاسم',
              prefixIcon: AppIcon(CupertinoIcons.person),
            ),
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'أدخل اسمك.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: headline,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'المسمى المهني أو نبذة قصيرة',
              prefixIcon: AppIcon(CupertinoIcons.briefcase),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            maxLength: 16,
            decoration: const InputDecoration(
              labelText: 'رقم التواصل (اختياري)',
              hintText: '+963…',
              prefixIcon: AppIcon(CupertinoIcons.phone),
            ),
            validator: (v) =>
                v == null ||
                    v.trim().isEmpty ||
                    RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(v.trim())
                ? null
                : 'استخدم الصيغة الدولية التي تبدأ بـ +.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: summary,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'نبذة مهنية (اختياري)',
              hintText: 'اذكر تخصصك وخبرتك وأبرز ما يمكنك تقديمه.',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: skills,
            maxLength: 838,
            decoration: const InputDecoration(
              labelText: 'المهارات (اختياري)',
              helperText: 'افصل بين المهارات بفاصلة، حتى 20 مهارة.',
              helperMaxLines: 3,
            ),
            validator: (v) => validateProfileLabels(v ?? '', 20),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: languages,
            maxLength: 418,
            decoration: const InputDecoration(
              labelText: 'اللغات (اختياري)',
              helperText: 'مثال: العربية، الإنجليزية',
              helperMaxLines: 3,
            ),
            validator: (v) => validateProfileLabels(v ?? '', 10),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: experience,
            keyboardType: TextInputType.number,
            maxLength: 2,
            decoration: const InputDecoration(
              labelText: 'سنوات الخبرة (اختياري)',
              helperText: 'اكتب 0 إذا لم تكن لديك خبرة سابقة.',
              helperMaxLines: 3,
            ),
            validator: (v) =>
                v == null ||
                    v.trim().isEmpty ||
                    (profileYears(v) != null &&
                        profileYears(v)! >= 0 &&
                        profileYears(v)! <= 60)
                ? null
                : 'أدخل عدداً من 0 إلى 60.',
          ),
          const SizedBox(height: 16),
          Text(
            widget.store.user?.email ?? '',
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 20),
          const Text(
            'طرق الدخول',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SanadActions(
            children: [
              for (final provider in ['google', 'apple'])
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            message = null;
                          });
                          try {
                            await widget.store.linkIdentity(provider);
                            if (mounted) {
                              setState(
                                () => message = 'تم ربط طريقة الدخول بالحساب.',
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => message =
                                    'تعذّر ربط الحساب. تأكد من استخدام البريد نفسه وحاول مجدداً.',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Text(
                    'ربط ${provider == 'google' ? 'Google' : 'Apple'}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => platformRoute<void>(
              context,
              BlockedMembersPage(store: widget.store),
            ),
            child: const Text('المستخدمون المحظورون'),
          ),

          const SizedBox(height: 24),
          if (message != null) ...[
            SignalCard(message!),
            const SizedBox(height: 16),
          ],
          SanadPrimaryButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ الملف'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          SanadActions(
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() => logoutConfirm = !logoutConfirm),
                icon: const AppIcon(CupertinoIcons.square_arrow_right),
                label: const Text('تسجيل الخروج'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => platformRoute<void>(
                        context,
                        DeleteAccountPage(store: widget.store),
                      ),
                child: Text(
                  'حذف الحساب',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
          if (logoutConfirm) ...[
            const SizedBox(height: 16),
            SignalCard(
              'ستُحذف نسخة بيانات الحساب من هذا الجهاز. تبقى بياناتك على الخادم ويمكنك العودة إليها بتسجيل الدخول.',
              action: busy ? null : logout,
              actionLabel: 'تأكيد تسجيل الخروج',
            ),
          ],
        ],
      ),
    ),
  );
}

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key, required this.store});
  final PlatformStore store;
  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  Json values = {
    'saved_search_matches': true,
    'job_moderation': true,
    'applications': true,
    'messages': true,
    'complaints': true,
  };
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.store.load('/me/notification-preferences');
      if (mounted) {
        setState(() => values = {...values, ...object(result['data'])});
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.store.savePreferences(values);
      if (mounted) setState(() => error = 'تم حفظ تفضيلات الإشعارات.');
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'تفضيلات الإشعارات',
    account: widget.store,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'التحديثات التي تهمّك',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'تظل التحديثات متاحة داخل الحساب. إيقاف فئة يمنع إشعار الهاتف الخاص بها.',
          style: TextStyle(color: context.sanad.secondary, height: 1.8),
        ),
        const SizedBox(height: 20),
        for (final item in {
          'saved_search_matches': 'فرص جديدة تطابق بحثي المحفوظ',
          'job_moderation': 'نتيجة مراجعة إعلاناتي',
          'applications': 'الطلبات وتغيّر حالتها',
          'messages': 'رسائل المحادثات',
          'complaints': 'الردود على الشكاوى',
        }.entries)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(item.value),
            value: values[item.key] == true,
            onChanged: busy
                ? null
                : (v) => setState(() => values[item.key] = v),
          ),
        const SizedBox(height: 20),
        if (error != null) ...[SignalCard(error!), const SizedBox(height: 16)],
        SanadPrimaryButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'جارٍ الحفظ…' : 'حفظ التفضيلات'),
        ),
      ],
    ),
  );
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key, required this.store});
  final PlatformStore store;
  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final code = TextEditingController();
  String? challenge, error;
  bool busy = false, confirmed = false, deleted = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> execute() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (challenge == null) {
        final response = widget.store.demo
            ? {
                'data': {'challenge_id': 'demo'},
              }
            : await widget.store.request(
                'POST',
                '/auth/reauth/email/challenge',
                body: {},
                key: PlatformStore.newId(),
              );
        if (mounted) {
          setState(
            () => challenge = textOf(object(response['data'])['challenge_id']),
          );
        }
      } else {
        if (!confirmed || code.text.trim().length != 6) {
          throw const PlatformFailure('أدخل رمز التحقق ووافق على حذف الحساب.');
        }
        final response = widget.store.demo
            ? {
                'data': {'reauth_ticket': 'demo'},
              }
            : await widget.store.request(
                'POST',
                '/auth/reauth/verify',
                body: {'challenge_id': challenge, 'code': code.text.trim()},
                key: PlatformStore.newId(),
              );
        await widget.store.deleteAccount(
          textOf(object(response['data'])['reauth_ticket']),
        );
        if (mounted) setState(() => deleted = true);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'حذف الحساب',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: deleted
          ? [
              EmptyPanel(
                icon: CupertinoIcons.checkmark_circle,
                title: 'تم حذف الحساب',
                description:
                    'أُغلقت الجلسات وأزيلت بيانات الحساب وفق سياسة الخصوصية.',
                action: SanadPrimaryButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('العودة للتصفح'),
                ),
              ),
            ]
          : [
              const EmptyPanel(
                icon: CupertinoIcons.person_crop_circle_badge_xmark,
                title: 'هل تريد حذف حسابك؟',
                description:
                    'ستُسحب إعلاناتك وتُلغى طلباتك وتُحذف بيانات ملفك. قد تُحتفظ بيانات البلاغات الضرورية لمدة محددة وفق سياسة الخصوصية.',
              ),
              if (challenge != null) ...[
                const Text('أرسلنا رمز تأكيد إلى بريد حسابك.'),
                const SizedBox(height: 16),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'رمز التحقق'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: (v) => setState(() => confirmed = v ?? false),
                  title: const Text('أفهم أن حذف الحساب نهائي.'),
                ),
              ],
              if (error != null) ...[
                SignalCard(error!),
                const SizedBox(height: 16),
              ],
              SanadPrimaryButton(
                onPressed: busy ? null : execute,
                child: Text(
                  busy
                      ? 'جارٍ التنفيذ…'
                      : challenge == null
                      ? 'التحقق من هويتي'
                      : 'حذف الحساب نهائياً',
                ),
              ),
            ],
    ),
  );
}

class BlockedMembersPage extends StatelessWidget {
  const BlockedMembersPage({super.key, required this.store});
  final PlatformStore store;
  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'المستخدمون المحظورون',
    account: store,
    child: PlatformCollection(
      store: store,
      path: '/me/blocks',
      empty: const EmptyPanel(
        icon: CupertinoIcons.hand_raised,
        title: 'لا يوجد مستخدمون محظورون',
        description:
            'يمكنك حظر أي طرف من خيارات المحادثة. يمنع الحظر إرسال رسائل جديدة بينكما.',
      ),
      builder: (context, row) => Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              textOf(row['name']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                try {
                  await store.block(textOf(row['id']), false);
                  await store.load('/me/blocks');
                } catch (e) {
                  if (context.mounted) {
                    await platformRoute<void>(
                      context,
                      PlatformScaffold(
                        title: 'تعذّر إلغاء الحظر',
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SignalCard(e.toString()),
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('إلغاء الحظر'),
            ),
          ],
        ),
      ),
    ),
  );
}
