import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/expense_repository.dart';
import 'state/expense_store.dart';
import 'state/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = ExpenseRepository();
  final store = ExpenseStore(repository);
  final themeController = ThemeController(repository);

  // Load from local storage before the first frame, so the dashboard never
  // flashes an empty state it is about to replace.
  await Future.wait([store.initialize(), themeController.initialize()]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ExpenseStore>.value(value: store),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const FinanceApp(),
    ),
  );
}
