import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/supabase_config.dart';
import 'data/auth_gateway.dart';
import 'data/budget_api.dart';
import 'data/expense_api.dart';
import 'data/income_api.dart';
import 'data/local_db_factory.dart';
import 'data/local_prefs.dart';
import 'state/auth_controller.dart';
import 'state/expense_store.dart';
import 'state/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    runApp(const SetupApp());
    return;
  }

  // Restores a persisted session before the first frame, so a returning user
  // never sees the login screen flash past.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  final client = Supabase.instance.client;
  final prefs = LocalPrefs();
  final themeController = ThemeController(prefs);
  await themeController.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<AuthController>(
          create: (_) => AuthController(SupabaseAuthGateway(client.auth)),
        ),
        ChangeNotifierProvider<ExpenseStore>(
          create: (_) => ExpenseStore(
            api: SupabaseExpenseApi(client),
            budgetApi: SupabaseBudgetApi(client),
            incomeApi: SupabaseIncomeApi(client),
            localDb: createLocalDb(),
          ),
        ),
      ],
      child: const FinanceApp(),
    ),
  );
}
