import 'package:flutter/material.dart';

abstract final class ColoresVitalia {
  static const azul = Color(0xFF2867B2);
  static const verde = Color(0xFF39A59A);
  static const fondoAzul = Color(0xFFEAF2FB);
  static const blanco = Color(0xFFFFFFFF);
  static const texto = Color(0xFF263238);
  static const borde = Color(0xFFD7E0E5);
}

/// Paleta acordada; verde se usa como acento, no para texto pequeño sobre blanco.
ThemeData temaVitalia() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: ColoresVitalia.azul).copyWith(
    primary: ColoresVitalia.azul,
    onPrimary: ColoresVitalia.blanco,
    secondary: ColoresVitalia.verde,
    surface: ColoresVitalia.blanco,
    onSurface: ColoresVitalia.texto,
    outline: ColoresVitalia.borde,
  ),
  scaffoldBackgroundColor: ColoresVitalia.fondoAzul,
  appBarTheme: const AppBarTheme(
    backgroundColor: ColoresVitalia.blanco,
    foregroundColor: ColoresVitalia.texto,
  ),
  dividerColor: ColoresVitalia.borde,
);
