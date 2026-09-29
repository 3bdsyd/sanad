import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'design.dart';

/// The system UITabBar on iPhone, with a glass Flutter fallback elsewhere.
///
/// Place directly in Scaffold.bottomNavigationBar without SafeArea or padding.
/// UIKit reports its own height including the home-indicator area. The Flutter
/// fallback owns its bottom safe area and horizontal capsule insets as well.
/// Logical indexes are opportunities (0), saved (1), publish/manage (2).
class NativeNavigation extends StatefulWidget {
  const NativeNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 3);

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<NativeNavigation> createState() => _NativeNavigationState();
}

class _NativeNavigationState extends State<NativeNavigation> {
  MethodChannel? _channel;
  double? _nativeHeight;

  @override
  void didUpdateWidget(covariant NativeNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      unawaited(_syncSelection());
    }
  }

  Future<void> _syncSelection() async {
    try {
      await _channel?.invokeMethod<void>('setSelected', widget.selectedIndex);
    } on MissingPluginException {
      // The platform view may be disappearing during a route transition.
    } on PlatformException {
      // A disposed native view does not need further selection updates.
    }
  }

  void _acceptHeight(Object? value) {
    if (!mounted || value is! num) return;
    final height = value.toDouble();
    if (!height.isFinite || height <= 0 || height == _nativeHeight) return;
    setState(() => _nativeHeight = height);
  }

  Future<void> _readHeight() async {
    try {
      _acceptHeight(await _channel?.invokeMethod<num>('getHeight'));
    } on MissingPluginException {
      // The view may be removed before its initial layout completes.
    } on PlatformException {
      // The estimated height remains usable until UIKit sends a new value.
    }
  }

  void _onPlatformViewCreated(int id) {
    if (!mounted) return;
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('app.fursa/navigation/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onSelected' && call.arguments is int) {
        final index = call.arguments as int;
        if (index >= 0 && index < 3) widget.onSelected(index);
      } else if (call.method == 'onHeightChanged') {
        _acceptHeight(call.arguments);
      }
    });
    unawaited(_syncSelection());
    // Initial native layout can precede channel handler registration.
    unawaited(_readHeight());
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (NativeBridge.available) {
      return SizedBox(
        height: _nativeHeight ?? 49 + MediaQuery.paddingOf(context).bottom,
        child: UiKitView(
          viewType: 'app.fursa/navigation',
          layoutDirection: TextDirection.rtl,
          creationParams: {'selectedIndex': widget.selectedIndex},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
          // UIKit owns taps and press-and-slide, including Liquid Glass morphs.
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      );
    }
    return _FlutterGlassBar(
      selectedIndex: widget.selectedIndex,
      onSelected: widget.onSelected,
    );
  }
}

class _FlutterGlassBar extends StatefulWidget {
  const _FlutterGlassBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_FlutterGlassBar> createState() => _FlutterGlassBarState();
}

class _FlutterGlassBarState extends State<_FlutterGlassBar> {
  static const _labels = ['الفرص', 'المحفوظة', 'أضف فرصة'];
  static const _icons = [
    CupertinoIcons.house,
    CupertinoIcons.heart,
    CupertinoIcons.plus,
  ];
  Color get _accent => context.sanad.primary;
  Color get _ink => context.sanad.ink;
  static const _barHeight = 62.0;
  int? _dragIndex;
  int? _focusedIndex;
  int? _focusHighlightIndex;

  void _select(int index) {
    if (index == widget.selectedIndex) return;
    unawaited(NativeBridge.selectionHaptic());
    widget.onSelected(index);
  }

  void _dragTo(Offset position, double width) {
    final start = (width - position.dx).clamp(0.0, width);
    setState(() => _dragIndex = (start / (width / 3)).floor().clamp(0, 2));
  }

  void _finishDrag() {
    final index = _dragIndex;
    setState(() => _dragIndex = null);
    if (index != null) _select(index);
  }

  void _cancelDrag() => setState(() => _dragIndex = null);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final labelWidth = ((width - 36) / 3 - 20).clamp(1.0, double.infinity);
      var labelHeight = 0.0;
      for (final label in _labels) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: DefaultTextStyle.of(context).style.merge(_labelStyle(true)),
          ),
          textDirection: TextDirection.rtl,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 2,
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: labelWidth);
        if (painter.height > labelHeight) labelHeight = painter.height;
        painter.dispose();
      }
      // Icon, gap, measured label and comfortable vertical padding. Measuring
      // the actual text keeps narrow screens and nonlinear scaling aligned.
      final height = (22 + 3 + labelHeight + 20).clamp(
        _barHeight,
        double.infinity,
      );
      return _buildBar(context, height);
    },
  );

  TextStyle _labelStyle(bool selected) => TextStyle(
    color: selected ? _accent : _ink,
    fontSize: 10.5,
    height: 1.3,
    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
  );

  Widget _buildBar(BuildContext context, double barHeight) {
    final activeIndex = _dragIndex ?? widget.selectedIndex;
    // Scaffold clears bottom padding inside bottomNavigationBar. viewPadding
    // still reports the Android system bar, so the capsule stays above it.
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final colors = context.sanad;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, safeBottom + 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(
                alpha: colors.isDark ? .28 : .14,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(
                  alpha: colors.isDark ? .94 : .9,
                ),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (d) =>
                          _dragTo(d.localPosition, width),
                      onHorizontalDragUpdate: (d) =>
                          _dragTo(d.localPosition, width),
                      onHorizontalDragEnd: (_) => _finishDrag(),
                      onHorizontalDragCancel: _cancelDrag,
                      child: SizedBox(
                        height: barHeight,
                        child: Row(
                          children: List.generate(3, (index) {
                            final selected = activeIndex == index;
                            return Expanded(
                              child: Semantics(
                                button: true,
                                selected: selected,
                                focusable: true,
                                focused: _focusedIndex == index,
                                label: _labels[index],
                                onTap: () => _select(index),
                                child: FocusableActionDetector(
                                  includeFocusSemantics: false,
                                  mouseCursor: SystemMouseCursors.click,
                                  onFocusChange: (focused) => setState(() {
                                    if (focused) {
                                      _focusedIndex = index;
                                    } else if (_focusedIndex == index) {
                                      _focusedIndex = null;
                                    }
                                  }),
                                  onShowFocusHighlight: (highlight) =>
                                      setState(() {
                                        if (highlight) {
                                          _focusHighlightIndex = index;
                                        } else if (_focusHighlightIndex ==
                                            index) {
                                          _focusHighlightIndex = null;
                                        }
                                      }),
                                  shortcuts: const <ShortcutActivator, Intent>{
                                    SingleActivator(LogicalKeyboardKey.enter):
                                        ActivateIntent(),
                                    SingleActivator(
                                      LogicalKeyboardKey.numpadEnter,
                                    ): ActivateIntent(),
                                    SingleActivator(LogicalKeyboardKey.space):
                                        ActivateIntent(),
                                  },
                                  actions: <Type, Action<Intent>>{
                                    ActivateIntent:
                                        CallbackAction<ActivateIntent>(
                                          onInvoke: (_) {
                                            _select(index);
                                            return null;
                                          },
                                        ),
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    excludeFromSemantics: true,
                                    onTap: () => _select(index),
                                    child: ExcludeSemantics(
                                      child: SizedBox(
                                        height: barHeight,
                                        child: DecoratedBox(
                                          position:
                                              DecorationPosition.foreground,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            border:
                                                _focusHighlightIndex == index
                                                ? Border.all(
                                                    color: _accent,
                                                    width: 2,
                                                  )
                                                : null,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                AppIcon(
                                                  _icons[index],
                                                  color: selected
                                                      ? _accent
                                                      : _ink,
                                                  size: 22,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  _labels[index],
                                                  maxLines: 2,
                                                  textAlign: TextAlign.center,
                                                  style: _labelStyle(selected),
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
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
