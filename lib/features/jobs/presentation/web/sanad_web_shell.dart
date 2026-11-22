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
    this.noticesUnread = 0,
    this.overlayHeader = false,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;
  final Widget child;
  final bool menuOpen;
  final VoidCallback? onToggleMenu;
  final int noticesUnread;
  final bool overlayHeader;

  @override
  Widget build(BuildContext context) {
    final breakpoint = WebLayout.of(context);
    final compact = breakpoint == WebBreakpoint.compact;
    final header = sanadHeaderChrome(
      context: context,
      from: 0,
      to: .55,
      edge: true,
      opaque: true,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            WebLayout.pagePadding(breakpoint).left,
            compact ? 10 : 12,
            WebLayout.pagePadding(breakpoint).right,
            12,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const SanadLogo(size: 36, highContrast: true, circle: true),
                  const SizedBox(width: 10),
                  Flexible(
                    flex: compact ? 1 : 0,
                    fit: compact ? FlexFit.tight : FlexFit.loose,
                    child: Text(
                      'سند',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 22 : 24,
                        fontWeight: FontWeight.w700,
                        color: context.sanad.ink,
                      ),
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
                        noticesUnread: noticesUnread,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: sanadActionGap),
                    const SanadThemePicker(compact: true),
                    const SizedBox(width: sanadActionGap),
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
                          noticesUnread: noticesUnread,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Chrome briefly reports a 1×1 viewport while attaching Flutter's
          // first frame. Wait for usable constraints before laying out the chrome.
          if (constraints.maxWidth <= 1 || constraints.maxHeight <= 1) {
            return const SizedBox.shrink();
          }
          return ReferenceBackdrop(
            child: overlayHeader
                ? Stack(
                    children: [
                      Positioned.fill(child: child),
                      Positioned(top: 0, left: 0, right: 0, child: header),
                    ],
                  )
                : Column(
                    children: [
                      header,
                      Expanded(child: child),
                    ],
                  ),
          );
        },
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
    this.noticesUnread = 0,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;
  final int noticesUnread;

  @override
  Widget build(BuildContext context) => SanadActionHeader(
    title: SanadActions(
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
          label: 'إعلاناتك',
          selected: section == 2,
          onTap: () => onSection(2),
        ),
      ],
    ),
    actions: [
      Badge(
        isLabelVisible: noticesUnread > 0,
        label: Text('$noticesUnread'),
        child: TextButton(onPressed: onNotices, child: const Text('المتابعة')),
      ),
      TextButton(onPressed: onAbout, child: const Text('حسابي')),
      const SanadThemePicker(compact: true),
      SanadPrimaryButton(
        onPressed: () => onSection(2),
        child: const Text('إعلاناتك'),
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
    this.noticesUnread = 0,
  });

  final int section;
  final ValueChanged<int> onSection;
  final VoidCallback onNotices;
  final VoidCallback onAbout;
  final int noticesUnread;

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
          leading: Badge(
            isLabelVisible: noticesUnread > 0,
            label: Text('$noticesUnread'),
            child: AppIcon(
              CupertinoIcons.bell,
              color: context.sanad.secondary,
              size: 20,
            ),
          ),
          title: const Text('المتابعة'),
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

/// Placed at the end of each feed's scrollable content, never over the viewport.
class SanadWebFooter extends StatelessWidget {
  const SanadWebFooter({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.sanad.surface.withValues(alpha: .72),
      border: Border(top: BorderSide(color: context.sanad.border)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        WebLayout.pagePadding(WebLayout.of(context)).left,
        16,
        WebLayout.pagePadding(WebLayout.of(context)).right,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WebLayout.contentMax),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Text(
                'سند · فرص عمل دولية، وتواصل مباشر دون حساب',
                style: TextStyle(color: context.sanad.secondary, fontSize: 12),
              ),
              SanadActions(
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
