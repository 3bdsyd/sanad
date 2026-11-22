import 'package:flutter/material.dart';

/// Animate the complete button surface, including keyboard activation.
class SanadPrimaryButton extends StatefulWidget {
  const SanadPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       tonal = false;
  const SanadPrimaryButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style,
  }) : child = label,
       tonal = false;
  const SanadPrimaryButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       tonal = true;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool tonal;

  @override
  State<SanadPrimaryButton> createState() => _SanadPrimaryButtonState();
}

class _SanadPrimaryButtonState extends State<SanadPrimaryButton>
    with SingleTickerProviderStateMixin {
  final states = WidgetStatesController();
  late final scale = AnimationController.unbounded(vsync: this, value: 1);
  bool pressed = false;
  int generation = 0;
  bool reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void initState() {
    super.initState();
    states.addListener(changed);
  }

  Future<void> changed() async {
    final next = states.value.contains(WidgetState.pressed);
    if (next == pressed) return;
    pressed = next;
    final request = ++generation;
    if (reduceMotion) {
      scale.value = 1;
      return;
    }
    if (next) {
      await scale.animateTo(
        .965,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (scale.value > .98) {
        await scale.animateTo(
          .965,
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOutCubic,
        );
        if (!mounted || request != generation) return;
      }
      await scale.animateTo(
        1.025,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
      if (mounted && request == generation) {
        await scale.animateTo(
          1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    states.removeListener(changed);
    states.dispose();
    scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The shared inner label animation is disabled: this surface owns motion.
    final style = (widget.style ?? const ButtonStyle()).copyWith(
      foregroundBuilder: (context, states, child) => child!,
    );
    final button = widget.icon != null
        ? FilledButton.icon(
            onPressed: widget.onPressed,
            statesController: states,
            style: style,
            icon: widget.icon,
            label: widget.child,
          )
        : widget.tonal
        ? FilledButton.tonal(
            onPressed: widget.onPressed,
            statesController: states,
            style: style,
            child: widget.child,
          )
        : FilledButton(
            onPressed: widget.onPressed,
            statesController: states,
            style: style,
            child: widget.child,
          );
    return AnimatedBuilder(
      animation: scale,
      child: button,
      builder: (context, child) => Transform.scale(
        scale: MediaQuery.disableAnimationsOf(context) ? 1 : scale.value,
        child: child,
      ),
    );
  }
}
