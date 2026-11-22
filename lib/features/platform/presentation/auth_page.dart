import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_links.dart';
import '../../../core/design.dart';
import '../data/platform_store.dart';
import '../domain/platform_models.dart';
import 'platform_ui.dart';

final _authFlights = Expando<Future<bool>>();

Future<bool> ensureAccount(
  BuildContext context,
  PlatformStore store, {
  String reason = 'للمتابعة',
}) async {
  if (!store.requiresAccount) return true;
  await store.initialize();
  if (!context.mounted) return false;
  if (store.signedIn) return true;
  final running = _authFlights[store];
  if (running != null) return running;
  final future = _requestAccount(context, store, reason);
  _authFlights[store] = future;
  try {
    return await future;
  } finally {
    _authFlights[store] = null;
  }
}

Future<bool> _requestAccount(
  BuildContext context,
  PlatformStore store,
  String reason,
) async {
  final result = await platformRoute<bool>(
    context,
    AuthPage(store: store, reason: reason),
  );
  return result == true && store.signedIn;
}

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.store,
    this.reason = 'لحفظ فرصك ومتابعة طلباتك',
  });
  final PlatformStore store;
  final String reason;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      name = TextEditingController(),
      code = TextEditingController();
  Json? challenge;
  String? error;
  bool busy = false, agreed = false;
  bool needsName = false;
  int resend = 0;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (!agreed) {
      setState(
        () => error = 'يرجى الموافقة على سياسة الخصوصية وشروط الاستخدام.',
      );
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e.code) {
            'popup-closed-by-user' ||
            'web-context-cancelled' ||
            'canceled' => 'تم إلغاء تسجيل الدخول. يمكنك المحاولة مجدداً.',
            'network-request-failed' =>
              'تعذّر الاتصال بخدمة الدخول. تحقق من الشبكة.',
            _ =>
              'الدخول السريع غير متاح حالياً. يمكنك المتابعة بالبريد الإلكتروني.',
          },
        );
      }
    } on PlatformFailure catch (e) {
      if (mounted) {
        setState(() {
          if (e.code == 'name_required') needsName = true;
          error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformFailure
              ? e.message
              : 'تعذّر تسجيل الدخول. حاول مجدداً أو تابع بالبريد الإلكتروني.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() => run(() async {
    if (!form.currentState!.validate()) return;
    challenge = await widget.store.requestCode(email.text.trim());
    if (!mounted) return;
    resend = (challenge!['retry_after'] as num?)?.toInt() ?? 60;
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || resend <= 0) {
        t.cancel();
        return;
      }
      setState(() => resend--);
    });
    setState(() {});
  });
  Future<void> verify() => run(() async {
    if (code.text.length != 6 || needsName && name.text.trim().length < 2) {
      setState(() => error = 'أدخل اسمك ورمز التحقق المكوّن من ستة أرقام.');
      return;
    }
    await widget.store.verifyCode(
      textOf(challenge!['challenge_id']),
      code.text,
      name.text.trim(),
    );
    if (mounted) Navigator.pop(context, true);
  });
  Future<void> social(String provider) => run(() async {
    await widget.store.socialLogin(provider);
    if (mounted) Navigator.pop(context, true);
  });
  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'مرحباً بك في سند',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 18),
        const Center(child: SanadLogo(size: 72)),
        const SizedBox(height: 24),
        Text(
          challenge == null ? 'فرصك تبدأ من هنا' : 'تحقّق من بريدك',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          challenge == null
              ? 'سجّل الدخول أو أنشئ حساباً بخطوة واحدة ${widget.reason}.'
              : 'أرسلنا رمز تحقق إلى ${email.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.sanad.secondary, height: 1.8),
        ),
        const SizedBox(height: 28),
        if (widget.store.demo)
          const SignalCard(
            'عرض توضيحي فقط. يمكنك استخدام أي رمز من ستة أرقام لتجربة الواجهات.',
          ),
        if (error != null) ...[SignalCard(error!), const SizedBox(height: 16)],
        if (widget.store.storageError != null) ...[
          SignalCard(widget.store.storageError!),
          const SizedBox(height: 16),
        ],
        if (challenge == null) ...[
          Glass(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SanadPrimaryButton.icon(
                    onPressed: busy ? null : () => social('google'),
                    icon: const AppIcon(CupertinoIcons.globe),
                    label: const Text('المتابعة باستخدام Google'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => social('apple'),
                    icon: const AppIcon(Icons.apple),
                    label: const Text('المتابعة باستخدام Apple'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Flexible(
                          flex: 3,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'أو بالبريد الإلكتروني',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  TextFormField(
                    controller: email,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: AppIcon(CupertinoIcons.mail),
                    ),
                    validator: (v) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'أدخل بريداً إلكترونياً صحيحاً.',
                  ),
                  const SizedBox(height: 16),
                  SanadPrimaryButton(
                    onPressed: busy ? null : send,
                    child: Text(busy ? 'جارٍ المتابعة…' : 'إرسال رمز التحقق'),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: code,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رمز التحقق',
                    prefixIcon: AppIcon(CupertinoIcons.lock_shield),
                  ),
                ),
                const SizedBox(height: 16),
                if (needsName)
                  TextField(
                    controller: name,
                    autofillHints: const [AutofillHints.name],
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'الاسم الذي سيظهر في حسابك',
                      prefixIcon: AppIcon(CupertinoIcons.person),
                    ),
                  ),
                const SizedBox(height: 16),
                SanadPrimaryButton(
                  onPressed: busy ? null : verify,
                  child: Text(busy ? 'جارٍ التحقق…' : 'الدخول إلى سند'),
                ),
                const SizedBox(height: 12),
                SanadActions(
                  children: [
                    TextButton(
                      onPressed: busy || resend > 0 ? null : send,
                      child: Text(
                        resend > 0
                            ? 'إعادة الإرسال بعد $resend ث'
                            : 'إعادة إرسال الرمز',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              challenge = null;
                              needsName = false;
                              code.clear();
                            }),
                      child: const Text('تغيير البريد'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: agreed,
          onChanged: busy ? null : (v) => setState(() => agreed = v ?? false),
          title: const Text(
            'أوافق على شروط الاستخدام وسياسة الخصوصية',
            style: TextStyle(fontSize: 13),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            TextButton(
              onPressed: AppLinks.hasPrivacy
                  ? () => launchUrl(Uri.parse(AppLinks.privacy))
                  : null,
              child: const Text('سياسة الخصوصية'),
            ),
            TextButton(
              onPressed: () =>
                  platformRoute<void>(context, const PlatformTermsPage()),
              child: const Text('شروط الاستخدام'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'التصفح متاح دون حساب. لا نشارك بريدك علناً، ويُستخدم للتحقق من حسابك.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.sanad.secondary,
            fontSize: 12,
            height: 1.8,
          ),
        ),
      ],
    ),
  );
}

class PlatformTermsPage extends StatelessWidget {
  const PlatformTermsPage({super.key});
  @override
  Widget build(BuildContext context) => const PlatformScaffold(
    title: 'شروط استخدام سند',
    child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Text(
        'باستخدام سند، تلتزم بنشر فرص عمل حقيقية ومعلومات دقيقة، واحترام خصوصية المتقدمين.\n\nتخضع الفرص للمراجعة قبل النشر. يُمنع طلب المال مقابل التوظيف، أو انتحال الهوية، أو المحتوى المسيء والتمييزي. لا تمثل مراجعة الإعلان ضماناً لصحة الجهة أو وعداً بالتوظيف.\n\nتُستخدم المحادثات للتواصل بشأن التقديم فقط. يمكنك حظر الطرف الآخر والإبلاغ عن أي إساءة. يحق للمشغّل إزالة المحتوى المخالف وتقييد الحسابات بعد المراجعة.\n\nيطلع صاحب الفرصة على بيانات ملفك والرسالة التي ترسلها عند التقديم. لا ترسل بيانات مالية أو مستندات حساسة عبر المحادثة.\n\nيمكنك سحب طلبك، وإغلاق إعلانك، وحذف حسابك من إعدادات الحساب. تفاصيل الاحتفاظ بالبيانات ووسيلة التواصل مع المشغّل موضحة في سياسة الخصوصية.',
        style: TextStyle(height: 1.9),
      ),
    ),
  );
}
