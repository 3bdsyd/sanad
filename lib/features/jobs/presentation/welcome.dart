import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/design.dart';
import '../../../core/robot_speech.dart';
import '../../../core/theme_controls.dart';
import '../../../core/web_layout.dart';

/// One welcome page with a direct path into browsing, without an account.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onContinue, this.onLogin});
  final VoidCallback onContinue;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) => RobotSystemBars(
    child: Scaffold(
      body: ReferenceBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (kIsWeb && constraints.maxWidth >= WebLayout.compactMax) {
                return _WebLanding(
                  onContinue: onContinue,
                  onLogin: onLogin,
                  wide: constraints.maxWidth >= WebLayout.mediumMax,
                );
              }
              final compact = constraints.maxHeight < 720;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        const _Header(),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: math.min(560, constraints.maxWidth - 48),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SanadReveal(
                                      order: 1,
                                      child: _RobotHero(compact: compact),
                                    ),
                                    const SizedBox(height: 8),
                                    const SanadReveal(
                                      order: 2,
                                      child: _WelcomeCopy(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SanadReveal(
                          order: 3,
                          child: _WelcomeAction(
                            onContinue: onContinue,
                            onLogin: onLogin,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Wide web landing: copy + CTA beside the hero, filling the viewport.
class _WebLanding extends StatelessWidget {
  const _WebLanding({
    required this.onContinue,
    required this.wide,
    this.onLogin,
  });
  final VoidCallback onContinue;
  final VoidCallback? onLogin;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final padding = WebLayout.pagePadding(WebLayout.of(context));
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding.left, 24, padding.right, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 52),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: WebLayout.contentMax),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [const Expanded(child: _Header())]),
                  SizedBox(height: wide ? 48 : 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: SanadReveal(
                          order: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _WelcomeCopy(),
                              const SizedBox(height: 28),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: _WelcomeAction(
                                  onContinue: onContinue,
                                  onLogin: onLogin,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: wide ? 40 : 24),
                      Expanded(
                        flex: wide ? 6 : 5,
                        child: SanadReveal(
                          order: 2,
                          child: _RobotHero(compact: !wide),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SanadLogo(size: 40, highContrast: true, circle: true, hero: true),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سند',
              style: TextStyle(
                fontSize: 21,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: context.sanad.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'لفرص العمل',
              style: TextStyle(fontSize: 10, color: context.sanad.secondary),
            ),
          ],
        ),
      ),
      const SanadThemePicker(compact: true),
    ],
  );
}

class _RobotHero extends StatelessWidget {
  const _RobotHero({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: compact ? 280 : 350,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: compact ? 30 : 48,
          bottom: compact ? 18 : 22,
          left: 18,
          right: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.sanad.isDark
                  ? context.sanad.tint.withValues(alpha: .5)
                  : Colors.white.withValues(alpha: .30),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.sanad.isDark
                      ? context.sanad.primary.withValues(alpha: .12)
                      : Colors.white.withValues(alpha: .62),
                  blurRadius: 54,
                  spreadRadius: 12,
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          top: compact ? 22 : 28,
          child: Semantics(
            image: true,
            label: 'روبوت ودود يبحث عن فرص عمل على حاسوب',
            child: Image.asset(
              'assets/images/career-robot.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        PositionedDirectional(
          top: compact ? 8 : 16,
          end: 0,
          child: _FloatingAccent(
            period: const Duration(milliseconds: 6200),
            phase: 0,
            child: _OpportunityCard(compact: compact),
          ),
        ),
        PositionedDirectional(
          start: 8,
          bottom: compact ? 18 : 28,
          child: _FloatingAccent(
            period: const Duration(milliseconds: 7600),
            phase: math.pi,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: context.sanad.surface.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: context.sanad.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2420508A),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const SanadLogo(size: 42),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Only the small accents drift; the robot and the reading area stay steady.
class _FloatingAccent extends StatefulWidget {
  const _FloatingAccent({
    required this.period,
    required this.phase,
    required this.child,
  });

  final Duration period;
  final double phase;
  final Widget child;

  @override
  State<_FloatingAccent> createState() => _FloatingAccentState();
}

class _FloatingAccentState extends State<_FloatingAccent>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  bool _enabled = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    if (_enabled && _foreground) {
      if (!_float.isAnimating) _float.repeat();
    } else {
      _float.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _float,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) {
      if (!_enabled) return child!;
      final angle = _float.value * math.pi * 2 + widget.phase;
      return Transform.translate(
        offset: Offset(math.sin(angle) * 2.5, math.sin(angle) * 5.5),
        child: Transform.rotate(
          angle: math.sin(angle + math.pi / 2) * .014,
          child: child,
        ),
      );
    },
  );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxWidth: compact ? 176 : 196),
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 11 : 14,
      vertical: compact ? 10 : 12,
    ),
    decoration: BoxDecoration(
      color: context.sanad.surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.sanad.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2620508A),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 42,
          height: compact ? 36 : 42,
          decoration: BoxDecoration(
            color: context.sanad.tint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: AppIcon(
            CupertinoIcons.search,
            size: 20,
            color: context.sanad.primary,
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'فرص عمل متاحة',
                style: TextStyle(
                  color: context.sanad.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'حسب الموقع والتخصص',
                style: TextStyle(color: context.sanad.secondary, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WelcomeCopy extends StatelessWidget {
  const _WelcomeCopy();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'فرص العمل\nوالتواصل المهني',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 26,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: context.sanad.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'اكتشف فرصاً في مدينتك ومجالك، وتواصل مباشرة مع صاحب الفرصة دون حساب.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          height: 1.7,
          color: context.sanad.secondary,
        ),
      ),
    ],
  );
}

class _WelcomeAction extends StatelessWidget {
  const _WelcomeAction({required this.onContinue, this.onLogin});
  final VoidCallback onContinue;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        width: double.infinity,
        child: SanadPrimaryButton(
          onPressed: onContinue,
          child: const Text('ابدأ الاستخدام'),
        ),
      ),
      if (onLogin != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onLogin,
            child: const Text('تسجيل الدخول أو إنشاء حساب'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Text(
        'تصفّح الفرص بحرية · سجّل الدخول للتقديم والحفظ',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: context.sanad.secondary),
      ),
    ],
  );
}
