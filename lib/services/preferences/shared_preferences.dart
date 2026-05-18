import 'package:shared_preferences/shared_preferences.dart';

class Preferences {
  SharedPreferences? prefs;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
  }

  void setTheme(bool isDarkMode) {
    prefs?.setBool('isDarkMode', isDarkMode);
  }

  bool? getTheme() {
    return prefs?.getBool('isDarkMode');
  }

  void setDominantColor(String hexColor) {
    prefs?.setString('dominantColor', hexColor);
  }

  String? getDominantColor() {
    return prefs?.getString('dominantColor');
  }
}
