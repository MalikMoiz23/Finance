import 'package:flutter/material.dart';

import '../data/local_prefs.dart';

/// Light / dark / follow-system, persisted on the device. Dark mode is a
/// selected palette (its own validated steps), not an inverted light one.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs);

  final LocalPrefs _prefs;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> initialize() async {
    _mode = await _prefs.loadThemeMode();
    notifyListeners();
  }

  /// Cycles system -> light -> dark -> system.
  Future<void> cycle() async {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    notifyListeners();
    await _prefs.saveThemeMode(_mode);
  }

  IconData get icon => switch (_mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  String get label => switch (_mode) {
    ThemeMode.system => 'System theme',
    ThemeMode.light => 'Light theme',
    ThemeMode.dark => 'Dark theme',
  };
}
