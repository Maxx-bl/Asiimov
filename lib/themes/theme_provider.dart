import 'package:asiimov/services/preferences/shared_preferences.dart';
import 'package:asiimov/themes/dark_mode.dart';
import 'package:asiimov/themes/light_mode.dart';
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData _themeData = lightMode;
  Color _dominantColor = Colors.orange;

  final Preferences _preferences = Preferences();

  ThemeProvider() {
    _init();
  }

  ThemeData get themeData => _themeData.copyWith(
        primaryColor: _dominantColor,
      );

  bool get isDarkMode => _themeData == darkMode;
  Color get dominantColor => _dominantColor;

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

  void setDominantColor(Color color) {
    _dominantColor = color;
    _preferences.setDominantColor(colorToHex(color));
    notifyListeners();
  }

  Future<void> _init() async {
    await _preferences.init();
    
    // Load theme
    final isDark = _preferences.getTheme();
    if (isDark != null && isDark) {
      _themeData = darkMode;
    } else {
      _themeData = lightMode;
    }

    // Load dominant color
    final hexColor = _preferences.getDominantColor();
    if (hexColor != null && hexColor.isNotEmpty) {
      _dominantColor = hexToColor(hexColor);
    } else {
      _dominantColor = Colors.orange;
    }

    notifyListeners();
  }

  // Helper functions for hex conversion
  static String colorToHex(Color color) {
    return color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

  static Color hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
