import 'package:finance/app.dart';
import 'package:finance/data/expense_repository.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/state/expense_store.dart';
import 'package:finance/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real app on a narrow phone viewport. Any overflow, null or layout
/// assertion in the widgets below fails these tests.
Future<ExpenseStore> _bootApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 logical
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = ExpenseRepository();
  final store = ExpenseStore(repository);
  final themeController = ThemeController(repository);
  await store.initialize();
  await themeController.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ExpenseStore>.value(value: store),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const FinanceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// Scrolls the visible scroll view until [finder] is on screen.
Future<void> _revealText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder _tab(int index) => find.byKey(ValueKey('nav_$index'));

void main() {
  testWidgets('dashboard renders and every period switches cleanly', (
    tester,
  ) async {
    final store = await _bootApp(tester);

    expect(store.totalEntryCount, greaterThan(0)); // demo data seeded
    expect(find.text('Total spent · This month'), findsOneWidget);
    expect(find.text('Spending by week'), findsOneWidget);

    await _revealText(tester, 'Where it went');
    await _revealText(tester, 'Recent expenses');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week').first);
    await tester.pumpAndSettle();
    expect(find.text('Spending by day'), findsOneWidget);

    await tester.tap(find.text('Year').first);
    await tester.pumpAndSettle();
    expect(find.text('Spending by month'), findsOneWidget);

    await tester.tap(find.text('Month').first);
    await tester.pumpAndSettle();
    expect(find.text('Total spent · This month'), findsOneWidget);
  });

  testWidgets('every trend bar is a labelled, tappable target', (tester) async {
    final handle = tester.ensureSemantics();

    await _bootApp(tester);
    await tester.tap(find.text('Week').first);
    await tester.pumpAndSettle();

    // Each bar carries a full-height hit target announced with its value, so a
    // screen reader (and a tap) can reach every column.
    final monday = find.bySemanticsLabel(RegExp(r'^Mon, .*, Rs '));
    expect(monday, findsOneWidget);
    await tester.tap(monday);
    await tester.pumpAndSettle();

    handle.dispose();
  });

  testWidgets('stepping back and forth through periods stays in range', (
    tester,
  ) async {
    final store = await _bootApp(tester);

    expect(store.canGoForward, isFalse); // already on the current month
    await tester.tap(find.byTooltip('Previous month').first);
    await tester.pumpAndSettle();
    expect(store.canGoForward, isTrue);
    expect(store.relativeRangeLabel, 'Last month');

    await tester.tap(find.byTooltip('Next month').first);
    await tester.pumpAndSettle();
    expect(store.relativeRangeLabel, 'This month');
  });

  testWidgets('insights tab renders every card', (tester) async {
    await _bootApp(tester);

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    expect(find.text('Patterns behind the total'), findsOneWidget);
    expect(find.text('TOTAL SPENT'), findsOneWidget);

    await _revealText(tester, 'Where it went');
    await _revealText(tester, 'Spending by weekday');
    await _revealText(tester, 'Biggest single spends');
  });

  testWidgets('expenses tab searches and filters', (tester) async {
    final store = await _bootApp(tester);

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    expect(find.text('Search notes, categories, amounts'), findsOneWidget);

    final fuelCount = store.summary.slices
        .firstWhere((s) => s.category == ExpenseCategory.fuel)
        .count;
    expect(fuelCount, greaterThan(0));

    final fuelPill = find.text('Fuel & Transport').first;
    await tester.ensureVisible(fuelPill);
    await tester.pumpAndSettle();
    await tester.tap(fuelPill);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('$fuelCount of ${store.summary.count} in this month'),
      findsOneWidget,
    );

    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzz-no-match');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('adding an expense updates the total', (tester) async {
    final store = await _bootApp(tester);
    final before = store.summary.total;

    await tester.tap(find.byTooltip('Add expense'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '2500');
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.summary.total, before + 2500);
    expect(find.textContaining('Added Rs 2,500'), findsOneWidget);
  });

  testWidgets('an empty amount is rejected', (tester) async {
    final store = await _bootApp(tester);
    final before = store.totalEntryCount;

    await tester.tap(find.byTooltip('Add expense'));
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than 0'), findsOneWidget);
    expect(store.totalEntryCount, before);
  });

  testWidgets('dark theme renders every screen', (tester) async {
    await _bootApp(tester);

    // System -> light -> dark.
    await tester.tap(find.byTooltip('System theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Light theme'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dark theme'), findsOneWidget);

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    await tester.tap(_tab(0));
    await tester.pumpAndSettle();
  });

  testWidgets('clearing all expenses empties the dashboard', (tester) async {
    final store = await _bootApp(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear everything'));
    await tester.pumpAndSettle();

    expect(store.totalEntryCount, 0);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    await _revealText(tester, 'No breakdown yet');
  });
}
