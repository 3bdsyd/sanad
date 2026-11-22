import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';

/// Prominent once per page load. Dismissal preserves the requested job URL.
class WebDownloadGate extends StatefulWidget {
  const WebDownloadGate({super.key, required this.child});
  final Widget child;
  @override
  State<WebDownloadGate> createState() => _WebDownloadGateState();
}

class _WebDownloadGateState extends State<WebDownloadGate> {
  bool visible = true;
  String? error;
  void close() => setState(() => visible = false);
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: visible,
        child: IgnorePointer(
          ignoring: visible,
          child: ExcludeSemantics(excluding: visible, child: widget.child),
        ),
      ),
      if (visible)
        Positioned.fill(
          child: Material(
            color: const Color(0xC90D1523),
            child: SafeArea(
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        close();
                        return null;
                      },
                    ),
                  },
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 550),
                        child: Semantics(
                          scopesRoute: true,
                          explicitChildNodes: true,
                          namesRoute: true,
                          label: 'تحميل تطبيق سند',
                          child: Glass(
                            padding: const EdgeInsets.all(24),
                            radius: 32,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: IconButton(
                                    autofocus: true,
                                    tooltip: 'متابعة التصفح',
                                    onPressed: close,
                                    icon: const AppIcon(CupertinoIcons.xmark),
                                  ),
                                ),
                                const SanadLogo(size: 64),
                                const SizedBox(height: 18),
                                const Text(
                                  'فرصتك أقرب مع تطبيق سند',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 29,
                                    fontWeight: FontWeight.w700,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'احفظ الفرص، تابع طلباتك، وتواصل مع جهات العمل من هاتفك.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.sanad.secondary,
                                    height: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: SanadPrimaryButton.icon(
                                    onPressed: () async {
                                      try {
                                        if (!await launchUrl(
                                          Uri.https(
                                            'play.google.com',
                                            '/store/apps/details',
                                            {'id': 'com.jobsnad.snad'},
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        )) {
                                          throw StateError('store unavailable');
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          setState(
                                            () => error =
                                                'تعذّر فتح المتجر. أعد المحاولة.',
                                          );
                                        }
                                      }
                                    },
                                    icon: const AppIcon(
                                      CupertinoIcons.arrow_down_circle,
                                    ),
                                    label: const Text('تحميل من Google Play'),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: null,
                                    child: Text('قريباً على App Store'),
                                  ),
                                ),
                                if (error != null) ...[
                                  const SizedBox(height: 12),
                                  SignalCard(error!),
                                ],
                                const SizedBox(height: 18),
                                TextButton(
                                  onPressed: close,
                                  child: const Text('متابعة التصفح على الموقع'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
