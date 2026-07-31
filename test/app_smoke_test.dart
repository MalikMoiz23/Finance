import 'package:finance/app.dart';
import 'package:finance/core/formatters.dart';
import 'package:finance/data/local_prefs.dart';
import 'package:finance/models/budget.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/state/auth_controller.dart';
import 'package:finance/state/expense_store.dart';
import 'package:finance/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Drives the real app on a narrow phone viewport against in-memory fakes of
/// Supabase auth and the expenses table. Any overflow, null or layout assertion
/// in the widgets below fails these tests.
class _Harness {
  _Harness(this.auth, this.api, this.budgets, this.store);

  final FakeAuthGateway auth;
  final FakeExpenseApi api;
  final FakeBudgetApi budgets;
  final ExpenseStore store;
}

Future<_Harness> _bootApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 logical
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authGateway = FakeAuthGateway();
  addTearDown(authGateway.dispose);
  final api = FakeExpenseApi(authGateway);
  final budgets = FakeBudgetApi(authGateway);
  final prefs = LocalPrefs();
  final store = ExpenseStore(api: api, budgetApi: budgets, prefs: prefs);
  final themeController = ThemeController(prefs);
  await themeController.initialize();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<AuthController>.value(
          value: AuthController(authGateway),
        ),
        ChangeNotifierProvider<ExpenseStore>.value(value: store),
      ],
      child: const FinanceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(authGateway, api, budgets, store);
}

const _name = 'Abdul Moiz';
const _email = 'moiz@example.com';
const _password = 'secret123';

/// Fills the register form and submits it.
Future<void> _register(
  WidgetTester tester, {
  String name = _name,
  String email = _email,
  String password = _password,
}) async {
  await tester.tap(find.text('Register'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
  await tester.pumpAndSettle();
}

Future<void> _login(
  WidgetTester tester, {
  String email = _email,
  String password = _password,
}) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
  await tester.pumpAndSettle();
}

Future<void> _addExpenseThroughUi(
  WidgetTester tester, {
  required String amount,
  String? item,
  String? note,
}) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, amount);
  if (item != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Chicken'),
      item,
    );
  }
  if (note != null) {
    await tester.enterText(find.byType(TextField).last, note);
  }
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Add expense');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

/// The tab pager is also a Scrollable (horizontal, locked), so tests must aim
/// at the vertical one belonging to the visible screen.
Finder get _verticalScroll => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _revealText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    280,
    scrollable: _verticalScroll,
  );
  await tester.pumpAndSettle();
}

Finder _tab(int index) => find.byKey(ValueKey('nav_$index'));

List<Expense> _sampleExpenses(DateTime now) => [
  Expense(
    id: 'seed-1',
    amount: 4200,
    category: ExpenseCategory.groceries,
    date: now,
    note: 'Weekly grocery run',
  ),
  Expense(
    id: 'seed-2',
    amount: 2500,
    category: ExpenseCategory.fuel,
    date: DateTime(now.year, now.month, now.day - 1),
    note: 'Petrol',
  ),
  Expense(
    id: 'seed-3',
    amount: 900,
    category: ExpenseCategory.dining,
    date: DateTime(now.year, now.month, 1),
    note: 'Chai',
  ),
];

void main() {
  testWidgets('the app opens on the login screen, not the dashboard', (
    tester,
  ) async {
    await _bootApp(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('register lands on the dashboard, greeted by name', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    expect(app.auth.currentUser?.email, _email);
    expect(app.auth.currentUser?.name, _name);
    expect(find.textContaining('Abdul'), findsOneWidget); // greeting
    expect(find.text('Total spent · This month'), findsOneWidget);
    // A brand new account starts empty.
    expect(app.store.totalEntryCount, 0);
    expect(find.text('Nothing logged yet'), findsOneWidget);
  });

  testWidgets('register validates the form before calling the backend', (
    tester,
  ) async {
    final app = await _bootApp(tester);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '');
    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.enterText(fields.at(2), '123');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name'), findsOneWidget);
    expect(
      find.text('That does not look like an email address'),
      findsOneWidget,
    );
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    expect(app.auth.currentUser, isNull);
  });

  testWidgets(
    'a wrong password is reported and keeps you on the login screen',
    (tester) async {
      final app = await _bootApp(tester);
      await _register(tester);

      // Log out, then get the password wrong.
      await tester.tap(find.byKey(const ValueKey('account_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      await _login(tester, password: 'wrong-password');

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(app.auth.currentUser, isNull);

      // The right password gets in.
      await _login(tester);
      expect(app.auth.currentUser?.email, _email);
    },
  );

  testWidgets('adding an expense writes to the backend and updates the total', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    await _addExpenseThroughUi(tester, amount: '2500', note: 'Petrol');

    final userId = app.auth.currentUser!.id;
    expect(app.api.rowsFor(userId).length, 1);
    expect(app.api.rowsFor(userId).single.amount, 2500);
    expect(app.api.rowsFor(userId).single.note, 'Petrol');
    expect(app.store.summary.total, 2500);
    expect(find.textContaining('Added Rs 2,500'), findsOneWidget);
  });

  testWidgets('each account only sees its own expenses', (tester) async {
    final app = await _bootApp(tester);

    await _register(tester);
    final first = app.auth.currentUser!.id;
    await _addExpenseThroughUi(tester, amount: '3000', note: 'First account');
    expect(app.store.summary.total, 3000);

    // Log out and register a second account.
    await tester.tap(find.byKey(const ValueKey('account_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    await _register(
      tester,
      name: 'Ali Raza',
      email: 'ali@example.com',
      password: 'another123',
    );

    final second = app.auth.currentUser!.id;
    expect(second, isNot(first));
    expect(app.store.totalEntryCount, 0, reason: 'second account is empty');
    expect(find.textContaining('First account'), findsNothing);
    expect(app.api.rowsFor(first).length, 1, reason: 'first account untouched');
  });

  testWidgets('a failed sync shows the banner and keeps the cached data', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();
    expect(app.store.totalEntryCount, 3);

    app.api.offline = true;
    await app.store.refresh();
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Check your network and try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    // The numbers stay on screen — reading works offline.
    expect(app.store.totalEntryCount, 3);
    expect(find.text('Total spent · This month'), findsOneWidget);

    app.api.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(app.store.syncError, isNull);
  });

  testWidgets('a failed write keeps the sheet open with the reason', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    app.api.failNextWrite = true;
    await _addExpenseThroughUi(tester, amount: '1500');

    expect(find.text('Edit expense'), findsNothing);
    expect(find.text('Add expense'), findsWidgets); // sheet still open
    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(app.api.rowsFor(app.auth.currentUser!.id), isEmpty);
    expect(app.store.totalEntryCount, 0);
  });

  testWidgets('charts and periods work on seeded data', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);
    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    expect(find.text('Spending by week'), findsOneWidget);
    await _revealText(tester, 'Where it went');
    await _revealText(tester, 'Recent expenses');
    await tester.drag(_verticalScroll, const Offset(0, 2400));
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

  testWidgets('insights and expenses tabs render for a signed-in account', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    expect(find.text('Patterns behind the total'), findsOneWidget);
    await _revealText(tester, 'Spending by weekday');

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    expect(
      find.text('Search items, notes, categories, amounts'),
      findsOneWidget,
    );
    expect(find.textContaining('3 of 3 in this month'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('deleting an expense removes it from the backend', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Petrol'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(app.api.rowsFor(userId).length, 2);
    expect(app.store.totalEntryCount, 2);
    expect(find.textContaining('Deleted Petrol'), findsOneWidget);
  });

  testWidgets('the account menu is named exactly once for screen readers', (
    tester,
  ) async {
    // PopupMenuButton's tooltip does not name the button, and a tooltip plus a
    // Semantics label names it twice. Exactly one is correct.
    final handle = tester.ensureSemantics();
    await _bootApp(tester);
    await _register(tester);

    expect(find.bySemanticsLabel('Account and data'), findsOneWidget);
    // The floating button carries a tooltip instead, which is a separate
    // semantics field — hence the different finder.
    expect(
      find.byTooltip('Add expense · hold to repeat the last one'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('an item is remembered and offered back with its price', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    await _addExpenseThroughUi(tester, amount: '850', item: 'Chicken');
    final userId = app.auth.currentUser!.id;
    expect(app.api.rowsFor(userId).single.item, 'Chicken');

    // Second entry: the item comes back as a one-tap chip carrying its price.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Buy again'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Chicken'));
    await tester.pumpAndSettle();

    // Tapping it filled the amount from the last price paid.
    final save = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final rows = app.api.rowsFor(userId);
    expect(rows.length, 2);
    expect(rows.every((r) => r.item == 'Chicken'), isTrue);
    expect(rows.every((r) => r.amount == 850), isTrue);
    expect(app.store.summary.total, 1700);
  });

  testWidgets('a budget shows a meter and flags going over', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);

    // Set a Rs 5,000 groceries limit from the Budgets tab.
    await tester.tap(_tab(3));
    await tester.pumpAndSettle();
    expect(find.text('No limits yet'), findsOneWidget);

    await tester.tap(find.text('Set your first limit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rs 5,000'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Set limit'));
    await tester.pumpAndSettle();

    final userId = app.auth.currentUser!.id;
    expect(app.budgets.rowsFor(userId).single.monthlyLimit, 5000);
    expect(find.textContaining('On track'), findsWidgets);

    // Spend past it and the wording changes, not just the colour.
    await _addExpenseThroughUi(tester, amount: '6000', item: 'Chicken');
    await tester.tap(_tab(3));
    await tester.pumpAndSettle();

    final status = app.store.budgetStatuses.single;
    expect(status.spent, 6000);
    expect(status.band, BudgetBand.overBudget);
    expect(find.textContaining('Over budget'), findsWidgets);
    expect(find.textContaining('1 category is over budget'), findsOneWidget);
  });

  testWidgets('swiping a row right logs the same thing again today', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    // Petrol was yesterday; swiping right re-logs it on today.
    await tester.drag(find.text('Petrol'), const Offset(500, 0));
    await tester.pumpAndSettle();

    final petrols = app.api
        .rowsFor(userId)
        .where((r) => r.note == 'Petrol')
        .toList();
    expect(petrols.length, 2, reason: 'original kept, copy added');
    expect(petrols.where((r) => r.date == dayOnly(DateTime.now())).length, 1);
    expect(find.textContaining('again'), findsWidgets);
  });

  testWidgets('Save & add another keeps the sheet open for the next entry', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '300');
    await tester.pumpAndSettle();

    final again = find.widgetWithText(OutlinedButton, 'Save & add another');
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();

    // Saved, and the sheet is still up with a cleared amount.
    expect(app.store.totalEntryCount, 1);
    expect(
      find.widgetWithText(OutlinedButton, 'Save & add another'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '700');
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(app.store.totalEntryCount, 2);
    expect(app.store.summary.total, 1000);
  });

  testWidgets('the calendar shows a day and opens its entries', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final now = DateTime.now();
    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(now));
    await app.store.refresh();
    await tester.pumpAndSettle();

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    await _revealText(tester, 'Spending calendar');

    // Every day is a labelled target; today's carries its total.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('^Day ${now.day}, Rs ')),
      findsOneWidget,
    );
    handle.dispose();

    await tester.tap(find.text('${now.day}').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('entr'), findsWidgets);
  });

  testWidgets('dark theme renders every screen', (tester) async {
    await _bootApp(tester);
    await _register(tester);

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
}
