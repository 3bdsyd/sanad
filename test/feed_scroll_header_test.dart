import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snad/features/jobs/presentation/feed_scroll_header.dart';

class _HeaderFixture extends StatefulWidget {
  const _HeaderFixture({
    required this.scroll,
    required this.focus,
    this.onExtentChanged,
  });
  final ScrollController scroll;
  final FocusNode focus;
  final ValueChanged<double>? onExtentChanged;

  @override
  State<_HeaderFixture> createState() => _HeaderFixtureState();
}

class _HeaderFixtureState extends State<_HeaderFixture> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.focus,
    builder: (context, _) => Scaffold(
      body: CustomScrollView(
        controller: widget.scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        slivers: [
          FeedScrollHeader(
            searchFocused: widget.focus.hasFocus,
            onExtentChanged: widget.onExtentChanged,
            child: ColoredBox(
              color: Colors.white,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('سند', style: TextStyle(fontSize: 25)),
                  ),
                  TextField(focusNode: widget.focus),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: 80,
            itemBuilder: (_, i) =>
                SizedBox(height: 100, child: Text('فرصة $i')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
    'header reappears gradually as one surface without resizing or moving content',
    (tester) async {
      final scroll = ScrollController();
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: _HeaderFixture(scroll: scroll, focus: focus),
        ),
      );
      final originalSize = tester.getSize(find.byType(Column));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pump();
      final opacityFinder = find.descendant(
        of: find.byType(AnimatedOpacity),
        matching: find.byType(FadeTransition),
      );
      double opacity() =>
          tester.widget<FadeTransition>(opacityFinder).opacity.value;
      final offset = scroll.offset;
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        opacity(),
        inExclusiveRange(0, .3),
        reason:
            'A fast reverse must not reveal the complete header in one frame.',
      );
      expect(tester.getSize(find.byType(Column)), originalSize);
      await tester.pump(const Duration(milliseconds: 80));
      expect(opacity(), inExclusiveRange(.3, .8));
      expect(tester.getSize(find.byType(Column)), originalSize);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(
        scroll.offset,
        offset,
        reason: 'The reveal must not push the list.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      focus.dispose();
    },
  );

  testWidgets('header hides down and returns on reverse far from list start', (
    tester,
  ) async {
    final scroll = ScrollController();
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: _HeaderFixture(scroll: scroll, focus: focus),
      ),
    );
    expect(find.text('سند').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(500));
    expect(find.text('سند').hitTestable(), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(500));
    expect(find.text('سند').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    focus.dispose();
  });

  testWidgets(
    'pinning retains search text, selection and focus while scrolling',
    (tester) async {
      final scroll = ScrollController();
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: _HeaderFixture(scroll: scroll, focus: focus),
        ),
      );
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'محاسب');
      editor.widget.controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(500));
      expect(focus.hasFocus, isTrue);
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(editor.widget.controller.text, 'محاسب');
      expect(
        editor.widget.controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(find.text('سند').hitTestable(), findsOneWidget);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      focus.unfocus();
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('سند').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      focus.dispose();
    },
  );

  testWidgets('floating header supports large text and reduced motion', (
    tester,
  ) async {
    final scroll = ScrollController();
    final focus = FocusNode();
    double? reportedExtent;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2.5),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: _HeaderFixture(
          scroll: scroll,
          focus: focus,
          onExtentChanged: (value) => reportedExtent = value,
        ),
      ),
    );
    expect(reportedExtent, tester.getSize(find.byType(Column)).height);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.text('سند').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    focus.dispose();
  });
}
