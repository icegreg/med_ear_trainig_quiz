import 'package:flutter/material.dart';

const _primaryColor = Color(0xFF00796B); // Teal

final lightTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: _primaryColor,
  brightness: Brightness.light,
);

final darkTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: _primaryColor,
  brightness: Brightness.dark,
);
