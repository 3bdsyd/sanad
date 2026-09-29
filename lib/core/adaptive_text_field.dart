import 'package:flutter/widgets.dart';

final _firstLetter = RegExp(r'\p{L}', unicode: true);

/// Resolve Arabic/English mixed input using the first strong letter. Leading
/// digits, punctuation, emoji and Arabic vowel marks never choose a direction.
TextDirection textDirectionFor(
  String text, {
  TextDirection fallback = TextDirection.rtl,
}) {
  final strong = _firstLetter.firstMatch(text);
  if (strong == null) return fallback;
  final code = strong.group(0)!.runes.first;
  return (code >= 0x0590 && code <= 0x08FF) ||
          (code >= 0xFB1D && code <= 0xFEFC) ||
          (code >= 0x10800 && code <= 0x10FFF) ||
          (code >= 0x1E800 && code <= 0x1EEFF)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

/// Rebuild only the editable field as its text changes. Keeping
/// controller/focus ownership in the caller preserves selection and validation.
class AdaptiveFieldDirection extends StatelessWidget {
  const AdaptiveFieldDirection({
    super.key,
    required this.controller,
    required this.builder,
    this.forceLtr = false,
  });

  final TextEditingController controller;
  final Widget Function(BuildContext context, TextDirection direction) builder;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => builder(
          context,
          forceLtr
              ? TextDirection.ltr
              : textDirectionFor(
                  value.text,
                  fallback: Directionality.of(context),
                ),
        ),
      );
}
