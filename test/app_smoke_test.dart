import 'dart:async';

import 'package:finance/app.dart';
import 'package:finance/core/formatters.dart';
import 'package:finance/data/json_local_db.dart';
import 'package:finance/data/local_prefs.dart';
import 'package:finance/models/budget.dart';
import 'package:finance/models/expense.dart';
import 'package:finance/models/expense_category.dart';
import 'package:finance/models/vehicle.dart';
import 'package:finance/screens/home_shell.dart';
import 'package:finance/state/auth_controller.dart';
import 'package:finance/state/expense_store.dart';
import 'package:finance/state/theme_controller.dart';
import 'package:finance/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Drives the real app on a narrow phone viewport against in-memory fakes of
/// Supabase auth and the expenses table. Any overflow, null or layout assertion
/// in the widgets below fails these tests.
class _Harness {
  _Harness(
    this.auth,
    this.api,
    this.budgets,
    this.incomes,
    this.projects,
    this.members,
    this.vehicles,
    this.store,
    this.online,
  );

  final FakeAuthGateway auth;
  final FakeExpenseApi api;
  final FakeBudgetApi budgets;
  final FakeIncomeApi incomes;
  final FakeProjectApi projects;
  final FakeMemberApi members;
  final FakeVehicleApi vehicles;
  final ExpenseStore store;

  /// Push false to simulate losing the connection, true to regain it.
  final StreamController<bool> online;
}

Future<_Harness> _bootApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 logical
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authGateway = FakeAuthGateway();
  addTearDown(authGateway.dispose);
  final members = FakeMemberApi(authGateway);
  final api = FakeExpenseApi(authGateway, members: members);
  members.expenses = api;
  final budgets = FakeBudgetApi(authGateway);
  final incomes = FakeIncomeApi(authGateway);
  final projects = FakeProjectApi(authGateway);
  final vehicles = FakeVehicleApi(authGateway);
  final prefs = LocalPrefs();
  // In-memory LocalDb: same contract and outbox as SQLite, no plugin needed.
  final localDb = JsonLocalDb(MemoryKeyValueStore());
  // The connectivity plugin is unavailable in tests, so the online signal is
  // injected and each test can drop the connection deliberately.
  final online = StreamController<bool>.broadcast();
  addTearDown(online.close);
  final store = ExpenseStore(
    api: api,
    budgetApi: budgets,
    incomeApi: incomes,
    projectApi: projects,
    memberApi: members,
    vehicleApi: vehicles,
    localDb: localDb,
    onlineChanges: online.stream,
  );
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
  return _Harness(
    authGateway,
    api,
    budgets,
    incomes,
    projects,
    members,
    vehicles,
    store,
    online,
  );
}

const _name = 'Abdul Moiz';
const _email = 'moiz@example.com';
const _password = 'secret123';

/// Fills in the "who is in the house" sheet, which opens by itself on a first
/// login. Every test that adds an expense needs at least one person, because
/// the form refuses to save without one.
Future<void> _addFamily(WidgetTester tester, List<String> names) async {
  for (final person in names) {
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Abba'),
      person,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add this person'));
    await tester.pumpAndSettle();
  }
  final done = find.textContaining('Done');
  await tester.ensureVisible(done);
  await tester.pumpAndSettle();
  await tester.tap(done);
  await tester.pumpAndSettle();
}

/// Fills the register form and submits it, then sets up the household.
///
/// Pass `family: const []` to leave the setup sheet open and assert on it.
Future<void> _register(
  WidgetTester tester, {
  String name = _name,
  String email = _email,
  String password = _password,
  List<String> family = const [_name],
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

  if (family.isNotEmpty) await _addFamily(tester, family);
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
  String? person,
}) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, amount);
  // With one person in the house there is nothing to choose; with several, the
  // form will not save until one is picked.
  if (person != null) {
    await tester.pumpAndSettle();
    // `.last`: the Overview's person filter shows the same name behind the
    // sheet.
    final chip = find.text(person).last;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }
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

/// The period pills live at the top, so a test that scrolled down to read a
/// chart must come back up before it can tap them.
Future<void> _toTop(WidgetTester tester) async {
  await tester.drag(_verticalScroll, const Offset(0, 3000));
  await tester.pumpAndSettle();
}

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
    expect(find.textContaining(', Abdul'), findsOneWidget); // greeting
    expect(find.text('Total spent · This month'), findsOneWidget);
    // A brand new account starts empty.
    expect(app.store.totalEntryCount, 0);
    await _revealText(tester, 'Nothing logged yet');
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

  testWidgets('a failed sync leaves the local data fully readable', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(DateTime.now()));
    await app.store.sync();
    await tester.pumpAndSettle();
    expect(app.store.totalEntryCount, 3);

    // A sync that cannot reach the server changes nothing on screen: the local
    // database is the source the UI reads from.
    app.api.offline = true;
    await app.store.sync();
    await tester.pumpAndSettle();

    expect(app.store.totalEntryCount, 3);
    expect(app.store.summary.total, 7600);
    expect(find.text('Total spent · This month'), findsOneWidget);
    // Nothing was queued, so there is no "waiting" banner to show.
    expect(app.store.pendingCount, 0);
    expect(app.store.syncState, SyncState.synced);
    expect(app.store.syncError, isNotNull);

    app.api.offline = false;
    await app.store.sync();
    await tester.pumpAndSettle();
    expect(app.store.syncError, isNull);
  });

  testWidgets('a write the server rejects is kept locally and queued', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    // The push fails, but the expense is already safe on the device — the whole
    // point of writing locally first. The sheet closes as normal.
    app.api.failNextWrite = true;
    await _addExpenseThroughUi(tester, amount: '1500', item: 'Chicken');

    expect(app.store.totalEntryCount, 1);
    expect(app.store.summary.total, 1500);
    expect(app.api.rowsFor(userId), isEmpty, reason: 'server never got it');
    expect(app.store.pendingCount, 1, reason: 'still queued');

    // Next sync drains it — nothing was lost and nothing is duplicated.
    await app.store.sync();
    await tester.pumpAndSettle();
    expect(app.api.rowsFor(userId).length, 1);
    expect(app.api.rowsFor(userId).single.item, 'Chicken');
    expect(app.store.pendingCount, 0);
    expect(app.store.totalEntryCount, 1);
  });

  testWidgets('expenses added with no connection sync when it returns', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    // Go offline: every server call now fails the way a dropped link does.
    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    await _addExpenseThroughUi(tester, amount: '900', item: 'Chicken');
    await _addExpenseThroughUi(tester, amount: '2500', item: 'Petrol');
    await app.store.saveIncome(DateTime.now(), 120000);
    await tester.pumpAndSettle();

    // Everything works offline: the numbers on screen are real and local.
    expect(app.store.totalEntryCount, 2);
    expect(app.store.summary.total, 3400);
    expect(app.store.monthMoney(DateTime.now()).income, 120000);
    expect(app.store.pendingCount, 3);
    expect(app.store.syncState, SyncState.waiting);
    expect(app.api.rowsFor(userId), isEmpty);

    // Connection returns: the queue drains by itself, no user action.
    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.pendingCount, 0);
    expect(app.store.syncState, SyncState.synced);
    expect(app.api.rowsFor(userId).length, 2);
    expect(app.api.rowsFor(userId).map((e) => e.item).toSet(), {
      'Chicken',
      'Petrol',
    });
    expect(app.incomes.rowsFor(userId).single.amount, 120000);
    // No duplicates: ids were generated on the device, so the push is a replay.
    expect(app.store.totalEntryCount, 2);
  });

  testWidgets('an offline delete removes the row on the server later', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.sync();
    await tester.pumpAndSettle();
    expect(app.store.totalEntryCount, 3);

    app.api.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    await app.store.remove('seed-2');
    await tester.pumpAndSettle();
    expect(app.store.totalEntryCount, 2, reason: 'gone locally straight away');
    expect(app.api.rowsFor(userId).length, 3, reason: 'server still has it');

    app.api.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.api.rowsFor(userId).length, 2);
    expect(app.api.rowsFor(userId).any((e) => e.id == 'seed-2'), isFalse);
    expect(app.store.pendingCount, 0);
  });

  testWidgets('charts and periods work on seeded data', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);
    app.api.seed(app.auth.currentUser!.id, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    await _revealText(tester, 'Spending by week');
    expect(find.text('Spending by week'), findsOneWidget);
    await _revealText(tester, 'Where it went');
    await _revealText(tester, 'Recent expenses');
    await _toTop(tester);

    await tester.tap(find.text('Week').first);
    await tester.pumpAndSettle();
    await _revealText(tester, 'Spending by day');
    expect(find.text('Spending by day'), findsOneWidget);

    await _toTop(tester);
    await tester.tap(find.text('Year').first);
    await tester.pumpAndSettle();
    await _revealText(tester, 'Spending by month');
    expect(find.text('Spending by month'), findsOneWidget);

    await _toTop(tester);
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
    // The button lands a pixel below a 780px viewport, so it has to be scrolled
    // to before it can be tapped.
    final setLimit = find.widgetWithText(FilledButton, 'Set limit');
    await tester.ensureVisible(setLimit);
    await tester.pumpAndSettle();
    await tester.tap(setLimit);
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

  testWidgets('setting pay turns the dashboard into savings tracking', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.refresh();
    await tester.pumpAndSettle();

    // Without pay there is only a prompt — savings cannot be computed.
    expect(find.text('Add your income'), findsOneWidget);
    expect(find.text('Pay & savings'), findsNothing);

    // FilledButton.icon builds a private subclass, which find.byType (exact
    // type match) will not see — target the label instead.
    final setIncome = find.text('Set monthly income');
    await tester.ensureVisible(setIncome);
    await tester.pumpAndSettle();
    await tester.tap(setIncome);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '120000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Set pay'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(app.incomes.rowsFor(userId).single.amount, 120000);
    expect(
      app.incomes.rowsFor(userId).single.month,
      DateTime(now.year, now.month),
    );

    // 4,200 + 2,500 + 900 = 7,600 spent this month, so 112,400 kept.
    final money = app.store.monthMoney(now);
    expect(money.income, 120000);
    expect(money.spent, 7600);
    expect(money.saved, 112400);
    expect(find.text('Pay & savings'), findsOneWidget);
    expect(find.textContaining('94% saved'), findsOneWidget);
  });

  testWidgets('pay carries forward but a raise does not rewrite history', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final twoMonthsAgo = DateTime(now.year, now.month - 2);

    await app.store.saveIncome(twoMonthsAgo, 80000);
    await tester.pumpAndSettle();

    // The gap month and this month both inherit the older figure.
    expect(app.store.monthMoney(thisMonth).income, 80000);
    expect(app.store.monthMoney(thisMonth).carriedForward, isTrue);

    // A raise entered for this month leaves the earlier months alone.
    await app.store.saveIncome(thisMonth, 120000);
    await tester.pumpAndSettle();
    expect(app.store.monthMoney(thisMonth).income, 120000);
    expect(app.store.monthMoney(thisMonth).carriedForward, isFalse);
    expect(app.store.monthMoney(twoMonthsAgo).income, 80000);
    expect(
      app.store.monthMoney(DateTime(now.year, now.month - 3)).income,
      isNull,
      reason: 'nothing was earned on record before the first entry',
    );
  });

  testWidgets('a single limit can be removed, and all of them reset', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    await app.store.saveBudget(ExpenseCategory.groceries, 25000);
    await app.store.saveBudget(ExpenseCategory.fuel, 8000);
    await app.store.saveBudget(ExpenseCategory.dining, 3000);
    await tester.pumpAndSettle();
    expect(app.budgets.rowsFor(userId).length, 3);

    await tester.tap(_tab(3));
    await tester.pumpAndSettle();

    // One limit: open it and use the spelled-out remove button.
    await _revealText(tester, 'Groceries');
    await tester.tap(find.text('Groceries').first);
    await tester.pumpAndSettle();
    final removeOne = find.text('Remove the Groceries limit');
    await tester.ensureVisible(removeOne);
    await tester.pumpAndSettle();
    await tester.tap(removeOne);
    await tester.pumpAndSettle();

    expect(app.budgets.rowsFor(userId).length, 2);
    expect(app.store.budgetFor(ExpenseCategory.groceries), isNull);

    // All of them: Reset all, which asks first.
    await _toTop(tester);
    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();
    expect(find.text('Reset all budgets?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset all'));
    await tester.pumpAndSettle();

    expect(app.budgets.rowsFor(userId), isEmpty);
    expect(app.store.budgetStatuses, isEmpty);
    // Expenses are untouched by a budget reset.
    expect(app.store.totalEntryCount, 0);
    expect(find.text('No limits yet'), findsOneWidget);
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

  // ------------------------------------------------------------- projects ---

  testWidgets('the Projects tab explains itself before anything exists', (
    tester,
  ) async {
    await _bootApp(tester);
    await _register(tester);

    await tester.tap(_tab(HomeShell.projectsTab));
    await tester.pumpAndSettle();

    expect(find.text('No projects yet'), findsOneWidget);
    // `FilledButton.icon` is a private subclass, so the label is the handle.
    expect(find.text('Start a project'), findsOneWidget);
    expect(
      find.text('None of it touches your monthly spending or budgets.'),
      findsOneWidget,
    );
  });

  testWidgets('a project is created from the tab and opens straight away', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    await tester.tap(_tab(HomeShell.projectsTab));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a project'));
    await tester.pumpAndSettle();

    // The example chips are the fastest path to a name.
    await tester.tap(find.text('Building a house'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. 2500000'),
      '2500000',
    );
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create project');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(app.store.projects.length, 1);
    expect(app.store.projects.first.name, 'Building a house');
    expect(app.store.projects.first.estimate, 2500000);
    expect(app.projects.projectsFor(userId).length, 1);

    // Straight into the empty ledger, not back to a list.
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('SPENT SO FAR'), findsOneWidget);
  });

  testWidgets('bricks are logged by quantity and rate, and the total is '
      'computed', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final project = await app.store.createProject(
      name: 'Building a house',
      estimate: 2500000,
    );
    await tester.pumpAndSettle();

    await tester.tap(_tab(HomeShell.projectsTab));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Building a house'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add the first entry'));
    await tester.pumpAndSettle();

    // Quantity x rate is the second mode; the form opens on Total.
    await tester.tap(find.text('Quantity × rate'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'e.g. Bricks'), 'Bri');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bricks').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Quantity').first,
      '5000',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Rate per piece'),
        '18.5');
    await tester.pumpAndSettle();

    // The arithmetic is on screen before anything is saved.
    expect(find.text('5,000 pieces × Rs 18.50'), findsOneWidget);
    expect(find.text('Rs 92,500'), findsWidgets);

    final save = find.widgetWithText(FilledButton, 'Add entry');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final summary = app.store.projectById(project.id)!;
    expect(summary.total, 92500);
    expect(summary.entries.single.quantity, 5000);
    expect(summary.entries.single.rate, 18.5);
    expect(summary.entries.single.unit, 'pieces');
    // The unit came from picking "Bricks", not from typing it.
    expect(find.text('5,000 pieces × Rs 18.50'), findsOneWidget);
  });

  testWidgets('project spending stays out of the monthly figures', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.sync();
    await tester.pumpAndSettle();

    await app.store.saveIncome(DateTime.now(), 120000);
    await app.store.saveBudget(ExpenseCategory.groceries, 10000);
    await tester.pumpAndSettle();

    final spentBefore = app.store.summary.total;
    final savedBefore = app.store.monthMoney(DateTime.now()).saved;
    final groceriesBefore = app.store.spentThisMonth(ExpenseCategory.groceries);

    final project = await app.store.createProject(name: 'Building a house');
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 0,
      quantity: 5000,
      rate: 18.5,
      unit: 'pieces',
      date: DateTime.now(),
    );
    await tester.pumpAndSettle();

    expect(app.store.projectsTotal, 92500);
    expect(app.store.summary.total, spentBefore);
    expect(app.store.monthMoney(DateTime.now()).saved, savedBefore);
    expect(
      app.store.spentThisMonth(ExpenseCategory.groceries),
      groceriesBefore,
    );
    expect(app.store.totalSpentThisMonth, isNot(92500));
  });

  testWidgets('a project built offline reaches the server on reconnect', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final project = await app.store.createProject(
      name: 'Building a house',
      estimate: 2500000,
    );
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 0,
      quantity: 5000,
      rate: 18.5,
      unit: 'pieces',
      date: DateTime.now(),
    );
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Mason labour',
      amount: 18900,
      date: DateTime.now(),
    );
    await tester.pumpAndSettle();

    expect(app.store.projectsTotal, 111400, reason: 'usable with no network');
    expect(app.store.pendingCount, 3);
    expect(app.projects.projectsFor(userId), isEmpty);

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.pendingCount, 0);
    expect(app.store.syncState, SyncState.synced);
    expect(app.projects.projectsFor(userId).length, 1);
    expect(app.projects.entriesFor(userId).length, 2);
    expect(app.store.projectsTotal, 111400, reason: 'no duplicates after pull');
  });

  testWidgets('editing a project after adding to it still pushes the entry', (
    tester,
  ) async {
    // The queue collapses a repeated edit by moving that row's op to the back.
    // Without parents-before-children ordering the entry would be pushed first
    // and rejected: its project does not exist on the server yet.
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final project = await app.store.createProject(name: 'Building a house');
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 92500,
      date: DateTime.now(),
    );
    // The edit lands *after* the entry in the queue.
    await app.store.saveProject(project.copyWith(estimate: 2500000));
    await tester.pumpAndSettle();

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.projects.projectsFor(userId).single.estimate, 2500000);
    expect(app.projects.entriesFor(userId).length, 1);
  });

  testWidgets('deleting a project takes its entries with it, here and there', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    final project = await app.store.createProject(name: 'Building a house');
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 92500,
      date: DateTime.now(),
    );
    await tester.pumpAndSettle();
    expect(app.projects.entriesFor(userId).length, 1);

    await app.store.deleteProject(project.id);
    await tester.pumpAndSettle();

    expect(app.store.projects, isEmpty);
    expect(app.store.projectsTotal, 0);
    expect(app.store.pendingCount, 0);
    expect(app.projects.projectsFor(userId), isEmpty);
    expect(app.projects.entriesFor(userId), isEmpty);
    expect(app.store.syncError, isNull);
  });

  testWidgets('a project deleted offline drops its entries queued ops too', (
    tester,
  ) async {
    // Both created offline, so neither ever reached the server. A queued insert
    // for the entry would be pushed after the project delete and rejected.
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final project = await app.store.createProject(name: 'Mistake');
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 92500,
      date: DateTime.now(),
    );
    await app.store.deleteProject(project.id);
    await tester.pumpAndSettle();

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.projects.projectsFor(userId), isEmpty);
    expect(app.projects.entriesFor(userId), isEmpty);
  });

  testWidgets('the Overview only mentions projects once one exists', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);

    await _revealText(tester, 'Recent expenses');
    expect(find.text('Paid from savings · not in the figures above'),
        findsNothing);

    final project = await app.store.createProject(name: 'Building a house');
    await app.store.addProjectEntry(
      projectId: project.id,
      stage: 'Bricks',
      amount: 92500,
      date: DateTime.now(),
    );
    await tester.pumpAndSettle();

    await _revealText(tester, 'Paid from savings · not in the figures above');
    expect(find.text('Biggest: Building a house · Rs 92,500'), findsOneWidget);
  });

  // --------------------------------------------------------------- family ---

  testWidgets('a new account is asked who is in the house before anything '
      'else', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const []);

    expect(find.text('Who is in the house?'), findsOneWidget);
    expect(
      find.textContaining('Everyone uses this same login'),
      findsOneWidget,
    );
    // Nothing to do until there is a name, and the button says so.
    expect(find.text('Add at least one person'), findsOneWidget);
    expect(app.store.hasMembers, isFalse);

    await tester.tap(find.text('Abba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ammi'));
    await tester.pumpAndSettle();

    expect(app.store.members.map((m) => m.name).toList(), ['Abba', 'Ammi']);
    expect(find.text('Done, start tracking'), findsOneWidget);

    await tester.tap(find.text('Done, start tracking'));
    await tester.pumpAndSettle();
    expect(find.text('Who is in the house?'), findsNothing);
  });

  testWidgets('the same name cannot be added twice', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const []);

    await tester.tap(find.text('Abba'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Abba'),
      'abba',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add this person'));
    await tester.pumpAndSettle();

    expect(find.text('abba is already on the list'), findsOneWidget);
    expect(app.store.members.length, 1);
  });

  testWidgets('an expense will not save until a person is picked', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1250');
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Add expense');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('Pick who spent this'), findsOneWidget);
    expect(app.store.totalEntryCount, 0, reason: 'nothing was saved');

    // Pick one and the same button now works. Scrolling to the save button
    // pushed the picker above the fold, so it has to be brought back.
    final ammi = find.text('Ammi').last;
    await tester.ensureVisible(ammi);
    await tester.pumpAndSettle();
    await tester.tap(ammi);
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(app.store.totalEntryCount, 1);
    final saved = app.store.allExpenses.single;
    expect(_memberName(app, saved.memberId), 'Ammi');
  });

  testWidgets('with one person in the house nothing has to be picked', (
    tester,
  ) async {
    // Not a guess: with a single member there is exactly one possible answer.
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba']);

    await _addExpenseThroughUi(tester, amount: '1250', item: 'Chicken');

    expect(app.store.totalEntryCount, 1);
    expect(
      _memberName(app, app.store.allExpenses.single.memberId),
      'Abba',
    );
  });

  testWidgets('the Insights tab ranks who spent how much', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);

    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    await _addExpenseThroughUi(
      tester,
      amount: '2000',
      item: 'Petrol',
      person: 'Ammi',
    );

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    await _revealText(tester, 'Spent by person');

    expect(find.text('Rs 6,000'), findsWidgets);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    final rows = app.store.spendByMemberThisPeriod;
    expect(rows.map((r) => r.name).toList(), ['Abba', 'Ammi']);
    expect(rows.first.total, 6000);
    expect(rows.last.total, 2000);
  });

  testWidgets('expenses from before the family existed read as Not set', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba']);
    final userId = app.auth.currentUser!.id;

    // Seeded straight onto the server with no member, the way every expense
    // logged before this feature existed looks.
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.sync();
    await tester.pumpAndSettle();

    expect(app.store.unassignedExpenseCount, 3);
    final rows = app.store.spendByMemberThisPeriod;
    expect(rows.last.unassigned, isTrue);
    expect(rows.last.name, 'Not set');
    expect(rows.last.count, 3, reason: 'all three fall in this month');

    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    await _revealText(tester, 'Spent by person');
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('the Expenses tab filters down to one person', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);

    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    await _addExpenseThroughUi(
      tester,
      amount: '2000',
      item: 'Petrol',
      person: 'Ammi',
    );

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Petrol'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, 'Abba').first);
    await tester.pumpAndSettle();

    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('Petrol'), findsNothing);
    expect(find.textContaining('1 of 2'), findsOneWidget);

    // Everyone puts it back.
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    expect(find.text('Petrol'), findsOneWidget);
    expect(app.store.totalEntryCount, 2);
  });

  testWidgets('removing a person keeps their spending in the totals', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);
    final userId = app.auth.currentUser!.id;

    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    final totalBefore = app.store.summary.total;
    final abba = app.store.members.firstWhere((m) => m.name == 'Abba');

    await app.store.deleteMember(abba.id);
    await tester.pumpAndSettle();

    expect(app.store.members.map((m) => m.name).toList(), ['Ammi']);
    expect(app.store.summary.total, totalBefore, reason: 'money is not lost');
    expect(app.store.totalEntryCount, 1);
    expect(app.store.allExpenses.single.memberId, isNull);
    expect(app.store.unassignedExpenseCount, 1);

    // And the server agrees, with no foreign key left dangling.
    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.members.rowsFor(userId).length, 1);
    expect(app.api.rowsFor(userId).single.memberId, isNull);
  });

  testWidgets('a family set up offline reaches the server on reconnect', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba']);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.members.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final ammi = await app.store.addMember('Ammi');
    await app.store.create(
      amount: 3200,
      category: ExpenseCategory.groceries,
      date: DateTime.now(),
      item: 'Mutton',
      note: '',
      memberId: ammi.id,
    );
    await tester.pumpAndSettle();

    expect(app.store.members.length, 2, reason: 'usable with no network');
    expect(
      app.members.rowsFor(userId).length,
      1,
      reason: 'Abba synced before the connection dropped, Ammi did not',
    );

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.members.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.members.rowsFor(userId).length, 2);
    expect(app.api.rowsFor(userId).single.memberId, ammi.id);
  });

  testWidgets('renaming a person after logging against them still pushes', (
    tester,
  ) async {
    // The queue collapses a repeated edit by moving that row's op to the back,
    // so the rename lands behind the expense that names it. Without parents
    // first, the expense would be pushed to a server that has never heard of
    // the member and be rejected.
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba']);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.members.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final bhai = await app.store.addMember('Bhai');
    await app.store.create(
      amount: 900,
      category: ExpenseCategory.dining,
      date: DateTime.now(),
      item: 'Chai',
      note: '',
      memberId: bhai.id,
    );
    // The rename lands *after* the expense in the queue.
    await app.store.saveMember(bhai.copyWith(name: 'Hamza'));
    await tester.pumpAndSettle();

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.members.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(
      app.members.rowsFor(userId).map((m) => m.name).toList(),
      ['Abba', 'Hamza'],
    );
    expect(app.api.rowsFor(userId).single.memberId, bhai.id);
  });

  testWidgets('a person removed offline does not strand their expenses', (
    tester,
  ) async {
    // Both made offline, so neither reached the server. A queued expense still
    // naming the removed member would be rejected by the foreign key.
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba']);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.members.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final guest = await app.store.addMember('Guest');
    await app.store.create(
      amount: 400,
      category: ExpenseCategory.dining,
      date: DateTime.now(),
      item: 'Samosa',
      note: '',
      memberId: guest.id,
    );
    await app.store.deleteMember(guest.id);
    await tester.pumpAndSettle();

    expect(app.store.allExpenses.single.memberId, isNull);

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.members.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.members.rowsFor(userId).map((m) => m.name).toList(), ['Abba']);
    expect(app.api.rowsFor(userId).single.memberId, isNull);
  });

  testWidgets('the family list is reachable from the account menu', (
    tester,
  ) async {
    await _bootApp(tester);
    await _register(tester, family: const ['Abba']);

    await tester.tap(find.byKey(const ValueKey('account_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family members'));
    await tester.pumpAndSettle();

    expect(find.text('Family members'), findsOneWidget);
    expect(find.textContaining('Everyone shares this login'), findsOneWidget);
  });

  // ------------------------------------------------------------- vehicles ---

  testWidgets('a car is added from the tab and opens on its logbook', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    await tester.tap(_tab(HomeShell.vehiclesTab));
    await tester.pumpAndSettle();
    expect(find.text('No vehicles yet'), findsOneWidget);

    await tester.tap(find.text('Add a vehicle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Honda City'),
      'Honda City',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. 42150'),
      '42150',
    );
    await tester.pumpAndSettle();
    final add = find.widgetWithText(FilledButton, 'Add vehicle');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(app.store.vehicles.single.name, 'Honda City');
    expect(app.store.vehicles.single.currentKm, 42150);
    expect(app.vehicles.vehiclesFor(userId).single.odometer, 42150);
    // Straight into the logbook, not back to a list.
    expect(find.text('42,150 km'), findsOneWidget);
    expect(find.text('Next service'), findsOneWidget);
  });

  testWidgets('picking Tuning fills its interval and works out the next due', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    final bike = await app.store.createVehicle(
      name: 'CD 70',
      kind: VehicleKind.bike,
      odometer: 18000,
    );
    await tester.pumpAndSettle();

    await tester.tap(_tab(HomeShell.vehiclesTab));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CD 70'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log service'));
    await tester.pumpAndSettle();

    // The bike presets, not the car ones.
    await tester.tap(find.text('Tuning'));
    await tester.pumpAndSettle();
    final values = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller.text);
    expect(values, containsAll(['Tuning', '18000', '3000', '6']));

    await tester.enterText(find.widgetWithText(TextField, '2500'), '1500');
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save service');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final summary = app.store.vehicleById(bike.id)!;
    final record = summary.services.single;
    expect(record.service, 'Tuning');
    expect(record.odometer, 18000, reason: 'prefilled from the reading');
    expect(record.cost, 1500);
    expect(record.intervalKm, 3000);
    expect(record.intervalMonths, 6);
    expect(summary.nextDue!.dueKm, 21000);
    expect(summary.nextDue!.status, DueStatus.ok);
    expect(app.vehicles.servicesFor(userId).single.cost, 1500);
    expect(find.textContaining('in 3,000 km'), findsWidgets);
  });

  testWidgets('service costs stay out of the monthly figures', (tester) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    app.api.seed(userId, _sampleExpenses(DateTime.now()));
    await app.store.sync();
    await app.store.saveIncome(DateTime.now(), 120000);
    await tester.pumpAndSettle();

    final spentBefore = app.store.summary.total;
    final savedBefore = app.store.monthMoney(DateTime.now()).saved;
    final fuelBefore = app.store.spentThisMonth(ExpenseCategory.fuel);

    final car = await app.store.createVehicle(
      name: 'Honda City',
      kind: VehicleKind.car,
      odometer: 42000,
    );
    await app.store.addVehicleService(
      vehicleId: car.id,
      service: 'Tuning',
      date: DateTime.now(),
      odometer: 42000,
      cost: 8500,
      intervalKm: 10000,
    );
    await tester.pumpAndSettle();

    expect(app.store.vehiclesTotalCost, 8500);
    expect(app.store.summary.total, spentBefore);
    expect(app.store.monthMoney(DateTime.now()).saved, savedBefore);
    expect(app.store.spentThisMonth(ExpenseCategory.fuel), fuelBefore);
  });

  testWidgets('the Overview flags a service that has come due', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    expect(find.text('Vehicle service'), findsNothing);

    final car = await app.store.createVehicle(
      name: 'Honda City',
      kind: VehicleKind.car,
      odometer: 47200,
    );
    await app.store.addVehicleService(
      vehicleId: car.id,
      service: 'Engine oil change',
      date: DateTime.now(),
      odometer: 42000,
      intervalKm: 5000,
    );
    await tester.pumpAndSettle();

    await _revealText(tester, 'Vehicle service');
    expect(find.text('1 job needs attention'), findsOneWidget);
    expect(
      find.textContaining('Honda City · Engine oil change'),
      findsOneWidget,
    );
    expect(find.textContaining('200 km over'), findsOneWidget);
  });

  testWidgets('a vehicle logged offline reaches the server on reconnect', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;

    app.api.offline = true;
    app.budgets.offline = true;
    app.incomes.offline = true;
    app.projects.offline = true;
    app.members.offline = true;
    app.vehicles.offline = true;
    app.online.add(false);
    await tester.pumpAndSettle();

    final car = await app.store.createVehicle(
      name: 'Honda City',
      kind: VehicleKind.car,
    );
    await app.store.addVehicleService(
      vehicleId: car.id,
      service: 'Tuning',
      date: DateTime.now(),
      odometer: 42000,
      cost: 8500,
    );
    // Editing the vehicle after logging against it moves its op to the back of
    // the queue; it must still reach the server before its service record.
    await app.store.saveVehicle(
      app.store.vehicleById(car.id)!.vehicle.copyWith(plate: 'LEB-1234'),
    );
    await tester.pumpAndSettle();

    expect(app.store.vehiclesTotalCost, 8500, reason: 'usable offline');
    expect(app.vehicles.vehiclesFor(userId), isEmpty);

    app.api.offline = false;
    app.budgets.offline = false;
    app.incomes.offline = false;
    app.projects.offline = false;
    app.members.offline = false;
    app.vehicles.offline = false;
    app.online.add(true);
    await tester.pumpAndSettle();

    expect(app.store.syncError, isNull);
    expect(app.store.pendingCount, 0);
    expect(app.vehicles.vehiclesFor(userId).single.plate, 'LEB-1234');
    expect(app.vehicles.servicesFor(userId).single.cost, 8500);
    expect(app.store.vehiclesTotalCost, 8500, reason: 'no duplicates');
  });

  testWidgets('deleting a vehicle takes its history with it, here and there', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    final car = await app.store.createVehicle(
      name: 'Honda City',
      kind: VehicleKind.car,
    );
    await app.store.addVehicleService(
      vehicleId: car.id,
      service: 'Tuning',
      date: DateTime.now(),
      odometer: 42000,
      cost: 8500,
    );
    await tester.pumpAndSettle();
    expect(app.vehicles.servicesFor(userId), hasLength(1));

    await tester.tap(_tab(HomeShell.vehiclesTab));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Honda City'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete vehicle'));
    await tester.pumpAndSettle();

    expect(app.store.hasVehicles, isFalse);
    expect(app.vehicles.vehiclesFor(userId), isEmpty);
    expect(app.vehicles.servicesFor(userId), isEmpty);
    expect(find.text('No vehicles yet'), findsOneWidget);
  });

  // --------------------------------------------------------- person filter ---

  testWidgets('picking a person narrows every tab to their spending', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);
    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    await _addExpenseThroughUi(
      tester,
      amount: '2000',
      item: 'Petrol',
      person: 'Ammi',
    );
    expect(app.store.summary.total, 8000);
    await _revealText(tester, 'Who spent it');
    await _toTop(tester);

    // The pill row scrolls sideways; the test font is wide enough to push the
    // third pill past the edge.
    final ammi = find.widgetWithText(GestureDetector, 'Ammi').first;
    await tester.ensureVisible(ammi);
    await tester.pumpAndSettle();
    await tester.tap(ammi);
    await tester.pumpAndSettle();

    expect(app.store.summary.total, 2000);
    expect(find.text('Spent by Ammi · This month'), findsOneWidget);
    expect(find.textContaining('Showing Ammi only'), findsOneWidget);
    await _revealText(tester, 'Recent expenses');
    expect(find.text('Who spent it'), findsNothing);
    // The household ranking is not narrowed: one row would answer nothing.
    expect(app.store.spendByMemberThisPeriod, hasLength(2));

    // The choice follows to the other tabs, like the period does.
    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ammi · Rs 2,000'), findsOneWidget);
    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    expect(find.text('Petrol'), findsOneWidget);
    expect(find.text('Chicken'), findsNothing);
    expect(find.text('TOTAL · AMMI'), findsOneWidget);

    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    expect(app.store.summary.total, 8000);
    expect(app.store.memberFilter, isNull);
  });

  testWidgets('a person row on the Overview filters to that person', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);
    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    await _addExpenseThroughUi(
      tester,
      amount: '2000',
      item: 'Petrol',
      person: 'Ammi',
    );

    await _revealText(tester, 'Who spent it');
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SectionCard, 'Who spent it'),
        matching: find.text('Abba'),
      ),
    );
    await tester.pumpAndSettle();

    expect(app.store.memberFilterLabel, 'Abba');
    expect(app.store.summary.total, 6000);
  });

  testWidgets('the Overview gives every category its own total', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester);
    final userId = app.auth.currentUser!.id;
    final today = DateTime.now();
    final amounts = {
      ExpenseCategory.groceries: 4200.0,
      ExpenseCategory.fuel: 2500.0,
      ExpenseCategory.bills: 1800.0,
      ExpenseCategory.dining: 900.0,
      ExpenseCategory.health: 700.0,
      ExpenseCategory.shopping: 300.0,
    };
    app.api.seed(userId, [
      for (final entry in amounts.entries)
        Expense(
          id: 'seed-${entry.key.name}',
          amount: entry.value,
          category: entry.key,
          date: today,
        ),
    ]);
    await app.store.sync();
    await tester.pumpAndSettle();

    await _revealText(tester, 'Where it went');
    // All six, not a top five: the smallest is still a number worth seeing.
    await _revealText(tester, 'Shopping');
    expect(find.text('Rs 300'), findsWidgets);
    expect(app.store.summary.slices.map((s) => s.total).toList(), [
      4200,
      2500,
      1800,
      900,
      700,
      300,
    ]);
  });

  testWidgets('the Expenses totals card splits a category by person', (
    tester,
  ) async {
    await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);
    await _addExpenseThroughUi(
      tester,
      amount: '6000',
      item: 'Chicken',
      person: 'Abba',
    );
    await _addExpenseThroughUi(
      tester,
      amount: '1500',
      item: 'Eggs',
      person: 'Ammi',
    );

    await tester.tap(_tab(2));
    await tester.pumpAndSettle();
    // Unfiltered, the line under the title carries the total.
    expect(find.textContaining('TOTAL'), findsNothing);

    await tester.tap(find.widgetWithText(GestureDetector, 'Groceries').first);
    await tester.pumpAndSettle();
    expect(find.text('TOTAL · GROCERIES'), findsOneWidget);
    // Also the day header's total, so at least one.
    expect(find.text('Rs 7,500'), findsWidgets);

    // Lift it clear of the add button floating over the list.
    await tester.drag(_verticalScroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('By person · Groceries'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
  });

  testWidgets('removing the person being shown goes back to everyone', (
    tester,
  ) async {
    final app = await _bootApp(tester);
    await _register(tester, family: const ['Abba', 'Ammi']);
    final abba = app.store.members.firstWhere((m) => m.name == 'Abba');

    app.store.setMemberFilter(abba.id);
    await tester.pumpAndSettle();
    expect(app.store.isMemberFiltered, isTrue);

    await app.store.deleteMember(abba.id);
    await tester.pumpAndSettle();
    expect(app.store.memberFilter, isNull);
  });
}

/// Reads a member name off the store, for assertions.
String? _memberName(_Harness app, String? id) =>
    app.store.memberById(id)?.name;
