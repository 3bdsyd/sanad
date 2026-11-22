import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/sanad_refresh.dart';
import '../data/platform_store.dart';
import '../domain/platform_models.dart';
import 'auth_page.dart';
export '../../../core/motion.dart' show SignalCard;
export '../../../core/adaptive_text_field.dart' show textDirectionFor;

class PlatformScaffold extends StatelessWidget {
  const PlatformScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.bottom,
    this.account,
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? bottom;
  final PlatformStore? account;
  @override
  Widget build(BuildContext context) => account == null
      ? surface(context)
      : ListenableBuilder(
          listenable: account!,
          builder: (context, _) =>
              account!.signedIn ? surface(context) : AuthPage(store: account!),
        );
  Widget surface(BuildContext context) => Scaffold(
    appBar: AppBar(centerTitle: true, title: Text(title), actions: actions),
    body: ReferenceBackdrop(
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: account?.storageError == null
                ? child
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SignalCard(account!.storageError!),
                      ),
                      Expanded(child: child),
                    ],
                  ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: bottom,
            ),
          ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.compact = false,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 18 : 32, horizontal: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: context.sanad.tint,
            borderRadius: BorderRadius.circular(28),
          ),
          child: AppIcon(icon, size: 34, color: context.sanad.primary),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: context.sanad.ink,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.sanad.secondary, height: 1.8),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 22), action!],
      ],
    ),
  );
}

class PlatformCollection extends StatefulWidget {
  const PlatformCollection({
    super.key,
    required this.store,
    required this.path,
    required this.builder,
    this.empty,
    this.header,
  });
  final PlatformStore store;
  final String path;
  final Widget Function(BuildContext, Json) builder;
  final Widget? empty, header;
  @override
  State<PlatformCollection> createState() => _PlatformCollectionState();
}

class _PlatformCollectionState extends State<PlatformCollection> {
  String? error;
  bool loading = true, more = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(covariant PlatformCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      loading = true;
      more = false;
      error = null;
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final run = ++generation;
    try {
      await widget.store.load(widget.path);
      if (mounted && run == generation) setState(() => error = null);
    } catch (e) {
      if (mounted && run == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && run == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final data = widget.store.snapshot(widget.path);
      final rows = objects(data['data']);
      return SanadRefresh(
        onRefresh: () async {
          await refresh();
          return error;
        },
        indicatorTop: 0,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.header != null) ...[
              widget.header!,
              const SizedBox(height: 20),
            ],
            if (widget.store.demo)
              const SignalCard(
                'وضع عرض توضيحي — لا توجد طلبات أو رسائل حقيقية.',
              ),
            if (error != null) ...[
              SignalCard(
                error!,
                action: refresh,
                actionLabel: 'إعادة المحاولة',
              ),
              const SizedBox(height: 12),
            ],
            if (widget.store.stale && rows.isNotEmpty) ...[
              const Text('نسخة محفوظة — قد تتغير الحالات عند الاتصال.'),
              const SizedBox(height: 12),
            ],
            if (loading && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: SanadLoader(size: 44)),
              )
            else if (rows.isEmpty && error == null)
              widget.empty ??
                  const EmptyPanel(
                    icon: CupertinoIcons.tray,
                    title: 'لا يوجد محتوى بعد',
                    description: 'ستظهر التحديثات هنا عند توفرها.',
                  ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: widget.builder(context, row),
              ),
            if (object(data['meta'])['next_cursor'] != null)
              TextButton.icon(
                onPressed: more
                    ? null
                    : () async {
                        final path = widget.path;
                        setState(() => more = true);
                        try {
                          await widget.store.loadMore(path);
                        } catch (e) {
                          if (mounted && path == widget.path) {
                            setState(() => error = e.toString());
                          }
                        } finally {
                          if (mounted && path == widget.path) {
                            setState(() => more = false);
                          }
                        }
                      },
                icon: more
                    ? const SanadLoader(size: 18)
                    : const AppIcon(CupertinoIcons.chevron_down),
                label: const Text('عرض المزيد'),
              ),
          ],
        ),
      );
    },
  );
}

class ProfileProgress extends StatelessWidget {
  const ProfileProgress({super.key, required this.member});
  final Member member;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'اكتمال بيانات الملف: ${member.completedSteps} من ${member.profileSteps.length}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Semantics(
        label: 'اكتمال بيانات الملف',
        value: '${member.completedSteps} من ${member.profileSteps.length}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: member.completedSteps / member.profileSteps.length,
            minHeight: 6,
            backgroundColor: context.sanad.border,
            color: context.sanad.primary,
          ),
        ),
      ),
      if (member.completedSteps < member.profileSteps.length) ...[
        const SizedBox(height: 10),
        Text(
          'يمكنك إضافة: ${member.profileSteps.entries.where((e) => !e.value).map((e) => e.key).join('، ')}. جميع البيانات المهنية الإضافية اختيارية.',
          style: TextStyle(
            color: context.sanad.secondary,
            height: 1.7,
            fontSize: 12,
          ),
        ),
      ],
    ],
  );
}

class ProfessionalSummary extends StatelessWidget {
  const ProfessionalSummary({super.key, required this.member});
  final Member member;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (member.experienceYears case final years?) ...[
        Text(years == 0 ? 'دون خبرة سابقة' : 'سنوات الخبرة: $years'),
        const SizedBox(height: 12),
      ],
      if (member.summary.isNotEmpty) ...[
        Text(member.summary, style: const TextStyle(height: 1.8)),
        const SizedBox(height: 12),
      ],
      if (member.skills.isNotEmpty) ...[
        const Text('المهارات', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final skill in member.skills) Chip(label: Text(skill)),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (member.languages.isNotEmpty)
        Text(
          'اللغات: ${member.languages.join('، ')}',
          style: const TextStyle(height: 1.8),
        ),
    ],
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.posting = false});
  final String status;
  final bool posting;
  @override
  Widget build(BuildContext context) => AppTag(
    (posting ? postingLabels : applicationLabels)[status] ??
        'جارٍ التحقق من الحالة',
  );
}

class AccountDestination extends StatelessWidget {
  const AccountDestination({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.badge,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) => Glass(
    padding: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: AppIcon(icon, color: context.sanad.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: context.sanad.secondary),
      ),
      trailing: badge == null
          ? const AppIcon(CupertinoIcons.chevron_back, size: 16)
          : AppTag(badge!),
      onTap: onTap,
    ),
  );
}

Future<T?> platformRoute<T>(BuildContext context, Widget child) =>
    openPage<T>(context, child);
