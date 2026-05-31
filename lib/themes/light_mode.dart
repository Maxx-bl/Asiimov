import 'package:flutter/material.dart';

ThemeData lightMode = ThemeData(
  scaffoldBackgroundColor: const Color(0xFFF9F7F5),
  colorScheme: const ColorScheme.light(
    surface: Color(0xFFF9F7F5),
    primary: Color(0xFF505050),
    secondary: Color(0xFFF2F2F2),
    tertiary: Color(0xFFC0C0C0),
    inversePrimary: Color(0xFF1A1A1A),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Color(0xFFF9F7F5),
    surfaceTintColor: Colors.transparent,
    foregroundColor: Color(0xFF1A1A1A),
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.5,
      color: Color(0xFF1A1A1A),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFFC0C0C0),
    thickness: 0.5,
    space: 0,
  ),
  popupMenuTheme: const PopupMenuThemeData(
    elevation: 2,
    shadowColor: Colors.black26,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    elevation: 2,
    shadowColor: Colors.black26,
  ),
);

