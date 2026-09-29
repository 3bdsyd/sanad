import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/app_links.dart';
import '../../../../core/design.dart';
import '../../../../core/motion.dart';
import '../../../../core/theme_controls.dart';
import '../../../../core/web_layout.dart';

/// Website chrome: glass top nav, expandable links on compact, light footer.
class SanadWebShell extends StatelessWidget {
  const SanadWebShell({
    super.key,
    required this.section,
    required this.onSection,
    required this.onNotices,
    required this.onAbout,
    required this.child,
    this.menuOpen = false,
    this.onToggleMenu,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;
  final Widget child;
  final bool menuOpen;
  final VoidCallback? onToggleMenu;

  @override
  Widget build(BuildContext context) {
    final breakpoint = WebLayout.of(context);
    final compact = breakpoint == WebBreakpoint.compact;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ReferenceBackdrop(
        child: Column(
          children: [
            sanadHeaderChrome(
              context: context,
              from: 0,
              to: .55,
              edge: true,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    WebLayout.pagePadding(breakpoint).left,
                    10,
                    WebLayout.pagePadding(breakpoint).right,
                    12,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SanadLogo(size: 36, bare: true, hero: true),
                          const SizedBox(width: 10),
                          Text(
                            'سند',
                            style: TextStyle(
                              fontSize: compact ? 22 : 24,
                              fontWeight: FontWeight.w700,
                              color: context.sanad.ink,
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 28),
                            Expanded(
                              child: _NavLinks(
                                section: section,
                                onSection: onSection,
                                onNotices: onNotices,
                                onAbout: onAbout,
                              ),
                            ),
                          ] else ...[
                            const Spacer(),
                            const SanadThemePicker(compact: true),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              tooltip: menuOpen ? 'إغلاق القائمة' : 'القائمة',
                              style: IconButton.styleFrom(
                                backgroundColor: context.sanad.tint,
                              ),
                              onPressed: onToggleMenu,
                              icon: AppIcon(
                                menuOpen
                                    ? CupertinoIcons.xmark
                                    : CupertinoIcons.line_horizontal_3,
                                color: context.sanad.primary,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
                      MotionSize(
                        duration: motionDuration(context, 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: compact && menuOpen
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _CompactMenu(
                                  section: section,
                                  onSection: onSection,
                                  onNotices: onNotices,
                                  onAbout: onAbout,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
            _WebFooter(breakpoint: breakpoint),
          ],
        ),
      ),
    );
  }
}

class _NavLinks extends StatelessWidget {
  const _NavLinks({
    required this.section,
    required this.onSection,
    required this.onNotices,
    required this.onAbout,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _NavItem(
        label: 'الفرص',
        selected: section == 0,
        onTap: () => onSection(0),
      ),
      _NavItem(
        label: 'المحفوظة',
        selected: section == 1,
        onTap: () => onSection(1),
      ),
      _NavItem(
        label: 'أضف فرصة',
        selected: section == 2,
        onTap: () => onSection(2),
      ),
      const Spacer(),
      TextButton(onPressed: onNotices, child: const Text('على بالك')),
      const SizedBox(width: 4),
      TextButton(onPressed: onAbout, child: const Text('عن سند')),
      const SizedBox(width: 4),
      const SanadThemePicker(compact: true),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: () => onSection(2),
        child: const Text('انشر فرصة'),
      ),
    ],
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? context.sanad.primary
            : context.sanad.secondary,
        backgroundColor: selected ? context.sanad.tint : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ),
  );
}

class _CompactMenu extends StatelessWidget {
  const _CompactMenu({
    required this.section,
    required this.onSection,
    required this.onNotices,
    required this.onAbout,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => Material(
    color: context.sanad.surface.withValues(alpha: .92),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: context.sanad.border),
    ),
    child: Column(
      children: [
        for (final item in [
          (0, 'الفرص', CupertinoIcons.square_grid_2x2),
          (1, 'المحفوظة', CupertinoIcons.heart),
          (2, 'أضف فرصة', CupertinoIcons.plus_app),
        ])
          ListTile(
            leading: AppIcon(
              item.$3,
              color: section == item.$1
                  ? context.sanad.primary
                  : context.sanad.secondary,
              size: 20,
            ),
            title: Text(
              item.$2,
              style: TextStyle(
                fontWeight: section == item.$1
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: section == item.$1
                    ? context.sanad.primary
                    : context.sanad.ink,
              ),
            ),
            onTap: () => onSection(item.$1),
          ),
        Divider(height: 1, color: context.sanad.border),
        ListTile(
          leading: AppIcon(
            CupertinoIcons.bell,
            color: context.sanad.secondary,
            size: 20,
          ),
          title: const Text('على بالك'),
          onTap: onNotices,
        ),
        ListTile(
          leading: AppIcon(
            CupertinoIcons.info_circle,
            color: context.sanad.secondary,
            size: 20,
          ),
          title: const Text('عن سند'),
          onTap: onAbout,
        ),
      ],
    ),
  );
}

class _WebFooter extends StatelessWidget {
  const _WebFooter({required this.breakpoint});
  final WebBreakpoint breakpoint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.sanad.surface.withValues(alpha: .72),
      border: Border(top: BorderSide(color: context.sanad.border)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        WebLayout.pagePadding(breakpoint).left,
        16,
        WebLayout.pagePadding(breakpoint).right,
        18,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WebLayout.contentMax),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Text(
                'سند · فرص بسوريا، تواصل مباشر بلا حساب',
                style: TextStyle(color: context.sanad.secondary, fontSize: 12),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AppLinks.hasPrivacy)
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(AppLinks.privacy),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('الخصوصية'),
                    ),
                  if (AppLinks.hasSupport)
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(AppLinks.support),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('الدعم'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
