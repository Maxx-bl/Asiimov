import 'package:asiimov/services/preferences/shared_preferences.dart';
import 'package:asiimov/themes/dark_mode.dart';
import 'package:asiimov/themes/light_mode.dart';
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData _themeData = lightMode;

  final Preferences _preferences = Preferences();

  ThemeProvider() {
    _init();
  }

  ThemeData get themeData => _themeData;

  bool get isDarkMode => _themeData == darkMode;

  set themeData(ThemeData themeData) {
    _themeData = themeData;
    notifyListeners();
  }

  void toggleTheme() {
    if (isDarkMode) {
      themeData = lightMode;
    } else {
      themeData = darkMode;
    }
    _preferences.setTheme(isDarkMode);
  }

  Future<void> _init() async {
    await _preferences.init();
    final isDark = _preferences.getTheme();
    if (isDark != null && isDark) {
      themeData = darkMode;
    } else {
      themeData = lightMode;
    }
  }
}
