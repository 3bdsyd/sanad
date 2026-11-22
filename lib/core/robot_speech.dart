import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

/// Robot screens keep their backdrop behind Android's system buttons: no bar
/// colour and no contrast scrim, only the buttons themselves stay visible.
class RobotSystemBars extends StatelessWidget {
  const RobotSystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sanadSystemBars(context.sanad),
      child: child,
    );
  }
}

/// Stable, fully readable speech; the entrance respects Reduce Motion.
class RobotSpeech extends StatelessWidget {
  const RobotSpeech({super.key, required this.title, required this.message});
  final String title, message;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(26, 14),
          painter: _SpeechTail(context.sanad.surface, context.sanad.border),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.sanad.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: context.sanad.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: context.sanad.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: context.sanad.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SpeechTail extends CustomPainter {
  const _SpeechTail(this.fill, this.border);
  final Color fill, border;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SpeechTail oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}

class RobotMessagePage extends StatelessWidget {
  const RobotMessagePage({
    super.key,
    required this.title,
    required this.message,
    this.actions = const [],
    this.loading = false,
  });
  final String title, message;
  final List<Widget> actions;
  final bool loading;

  @override
  Widget build(BuildContext context) => RobotSystemBars(
    child: Scaffold(
      body: ReferenceBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: (constraints.maxWidth - 40).clamp(0, 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SanadReveal(
                          child: ExcludeSemantics(
                            child: Image.asset(
                              'assets/images/career-robot.png',
                              height: constraints.maxHeight < 650 ? 100 : 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SanadReveal(
                          order: 1,
                          child: RobotSpeech(title: title, message: message),
                        ),
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: SanadLogoIntro(size: 36),
                          ),
                        for (final action in actions)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: action,
                            ),
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
  );
}
