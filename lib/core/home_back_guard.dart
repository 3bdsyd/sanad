import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'motion.dart';

/// Let detail/form routes handle back first, then return to the first tab.
class HomeBackGuard extends StatelessWidget {
  const HomeBackGuard({
    super.key,
    required this.isHome,
    required this.onHome,
    required this.child,
  });

  final bool isHome;
  final VoidCallback onHome;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: kIsWeb,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || ModalRoute.of(context)?.isCurrent != true) return;
      if (!isHome) {
        onHome();
      } else {
        openPage<void>(context, const _ExitConfirmation());
      }
    },
    child: child,
  );
}

class _ExitConfirmation extends StatelessWidget {
  const _ExitConfirmation();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الخروج من سند')),
    body: ReferenceBackdrop(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'هل تريد إغلاق التطبيق؟',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SanadPrimaryButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('متابعة الاستخدام'),
                ),
                if (defaultTargetPlatform == TargetPlatform.android) ...[
                  const SizedBox(height: sanadActionGap),
                  TextButton(
                    onPressed: SystemNavigator.pop,
                    child: const Text('إغلاق التطبيق'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
