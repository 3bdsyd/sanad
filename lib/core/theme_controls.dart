import 'package:flutter/material.dart';

import 'design.dart';
import 'theme_preference.dart';

/// In-content appearance picker — no dialogs or sheets.
class SanadThemePicker extends StatelessWidget {
  const SanadThemePicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = SanadThemeScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (compact) {
          return IconButton.filledTonal(
            tooltip: 'المظهر: ${controller.label}',
            style: IconButton.styleFrom(backgroundColor: context.sanad.tint),
            onPressed: controller.cycle,
            icon: AppIcon(
              controller.icon,
              color: context.sanad.primary,
              size: 20,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المظهر',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: context.sanad.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اختَر فاتح أو داكن، أو خلّي سند يتبع مظهر جهازك.',
              style: TextStyle(color: context.sanad.secondary, height: 1.6),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  (ThemeMode.system, 'تلقائي', Icons.brightness_auto_rounded),
                  (ThemeMode.light, 'فاتح', Icons.light_mode_rounded),
                  (ThemeMode.dark, 'داكن', Icons.dark_mode_rounded),
                ])
                  _ThemeChip(
                    label: option.$2,
                    icon: option.$3,
                    selected: controller.mode == option.$1,
                    onTap: () => controller.setMode(option.$1),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? context.sanad.primary : context.sanad.surface,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? context.sanad.primary : context.sanad.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon,
              size: 16,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : context.sanad.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : context.sanad.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
