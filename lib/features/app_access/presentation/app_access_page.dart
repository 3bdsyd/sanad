import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/robot_speech.dart';
import '../../../core/design.dart';
import '../data/app_access_controller.dart';
import '../domain/app_access.dart';

class AppAccessPage extends StatefulWidget {
  const AppAccessPage({super.key, required this.controller});
  final AppAccessController controller;
  @override
  State<AppAccessPage> createState() => _AppAccessPageState();
}

class _AppAccessPageState extends State<AppAccessPage> {
  bool _opening = false;
  String? _launchError;

  Future<void> _openStore() async {
    final uri = widget.controller.status?.storeUri;
    if (_opening || uri == null) return;
    setState(() {
      _opening = true;
      _launchError = null;
    });
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('store unavailable');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _launchError = 'تعذّر فتح المتجر. يرجى إعادة المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final status = controller.status;
    final maintenance = status?.kind == AppAccessKind.maintenance;
    final update = status?.kind == AppAccessKind.update;
    final waiting = status == null && controller.error == null;
    if (waiting || controller.allowed) {
      return Scaffold(
        body: ReferenceBackdrop(
          child: Center(
            child: controller.allowed
                ? const SizedBox.shrink()
                : const SanadLogoIntro(size: 112),
          ),
        ),
      );
    }
    final title = maintenance
        ? 'الخدمة قيد الصيانة'
        : update
        ? 'يتوفر إصدار جديد من سند'
        : waiting
        ? 'جارٍ التحقق من الخدمة'
        : 'تعذّر التحقق من الخدمة';
    final message = maintenance
        ? 'الخدمة قيد الصيانة حالياً. يرجى إعادة المحاولة لاحقاً.'
        : update
        ? status!.requiredUpdate
              ? 'يجب تحديث التطبيق إلى الإصدار الجديد لمتابعة الاستخدام.'
              : 'يتوفر إصدار جديد. يمكنك التحديث الآن أو متابعة استخدام الإصدار الحالي.'
        : waiting
        ? 'جارٍ التحقق من حالة الخدمة وتوفر تحديثات للتطبيق.'
        : controller.error!;
    return RobotMessagePage(
      title: title,
      message: message,
      loading: controller.checking,
      actions: [
        if (update && status!.latestVersion.isNotEmpty)
          Text(
            'الإصدار الجديد: ${status.latestVersion}',
            textAlign: TextAlign.center,
          ),
        if (update && status!.storeUri == null)
          const Text(
            'رابط التحديث غير متاح حالياً. يرجى إعادة التحقق لاحقاً.',
            textAlign: TextAlign.center,
          ),
        if (controller.error != null && status != null)
          Text(controller.error!, textAlign: TextAlign.center),
        if (_launchError != null)
          Text(_launchError!, textAlign: TextAlign.center),
        if (update && status!.storeUri != null)
          SanadPrimaryButton(
            onPressed: _opening || controller.checking ? null : _openStore,
            child: Text(_opening ? 'جارٍ فتح المتجر…' : 'التحديث الآن'),
          ),
        if (!waiting)
          OutlinedButton(
            onPressed: controller.checking ? null : controller.refresh,
            child: const Text('إعادة التحقق'),
          ),
        if (update && !status!.requiredUpdate)
          TextButton(
            onPressed: controller.checking ? null : controller.skipUpdate,
            child: const Text('المتابعة لاحقاً'),
          ),
      ],
    );
  }
}
