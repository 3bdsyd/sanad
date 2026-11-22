import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snad/core/design.dart';
import 'package:snad/core/home_back_guard.dart';

void main() {
  testWidgets('system back closes details, returns home, then confirms exit', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var tab = 1;
    var exited = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exited = true;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: sanadTheme(),
        home: NavigatorPopHandler<void>(
          onPopWithResult: (_) => navigator.currentState!.maybePop(),
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => StatefulBuilder(
                builder: (context, setState) => HomeBackGuard(
                  isHome: tab == 0,
                  onHome: () => setState(() => tab = 0),
                  child: Scaffold(body: Text('tab $tab')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('details')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('details'), findsNothing);
    expect(find.text('tab 1'), findsOneWidget);
    expect(exited, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('tab 0'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('هل تريد إغلاق التطبيق؟'), findsOneWidget);
    expect(exited, isFalse);
    await tester.tap(find.text('متابعة الاستخدام'));
    await tester.pumpAndSettle();
    expect(find.text('tab 0'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('إغلاق التطبيق'));
    expect(exited, isTrue);
  });

  testWidgets('nested protected form receives back without losing the draft', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var handled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NavigatorPopHandler<void>(
          onPopWithResult: (_) => navigator.currentState!.maybePop(),
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const Scaffold()),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) => handled = !didPop,
          child: const Scaffold(body: Text('draft')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('draft'), findsOneWidget);
  });
}
