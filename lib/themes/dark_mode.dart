import 'package:flutter/material.dart';

ThemeData darkMode = ThemeData(
  scaffoldBackgroundColor: const Color(0xFF1C1916),
  colorScheme: const ColorScheme.dark(
    surface: Color(0xFF252119),
    primary: Color(0xFFC4BDB0),
    secondary: Color(0xFF302C25),
    tertiary: Color(0xFF403B32),
    inversePrimary: Color(0xFFEDE8E0),
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Color(0xFF1C1916),
    surfaceTintColor: Colors.transparent,
    foregroundColor: Color(0xFFEDE8E0),
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.5,
      color: Color(0xFFEDE8E0),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF302C25),
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
