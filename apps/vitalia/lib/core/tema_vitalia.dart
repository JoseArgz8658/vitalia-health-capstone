import 'package:flutter/material.dart';

/// Sistema visual Vitalia: contraste legible y colores reservados para acciones
/// y estados. Los tonos suaves favorecen el uso prolongado de la aplicación.
abstract final class ColoresVitalia {
  static const azul = Color(0xFF236A86);
  static const azulActivo = Color(0xFF17354E);
  static const azulSuave = Color(0xFFEAF3F6);
  static const verde = Color(0xFF1A776D);
  static const verdeSuave = Color(0xFFE7F3F2);
  static const fondoAzul = Color(0xFFF4F7FA);
  static const blanco = Color(0xFFFFFFFF);
  static const texto = Color(0xFF17354E);
  static const textoSecundario = Color(0xFF536B7C);
  static const borde = Color(0xFFDCE4EA);
  static const bordeTenue = Color(0xFFE9EEF2);
  static const advertenciaSuave = Color(0xFFFEF5E8);
  static const pendienteSuave = Color(0xFFECF0FA);
  static const error = Color(0xFFB54B5D);
  static const errorSuave = Color(0xFFFBECEF);
}

ThemeData temaVitalia() {
  final colors = ColorScheme.fromSeed(
    seedColor: ColoresVitalia.azul,
    brightness: Brightness.light,
  ).copyWith(
    primary: ColoresVitalia.azul,
    onPrimary: ColoresVitalia.blanco,
    primaryContainer: ColoresVitalia.azulSuave,
    onPrimaryContainer: ColoresVitalia.azulActivo,
    secondary: ColoresVitalia.verde,
    onSecondary: ColoresVitalia.blanco,
    secondaryContainer: ColoresVitalia.verdeSuave,
    onSecondaryContainer: const Color(0xFF245955),
    tertiary: const Color(0xFF586E8C),
    tertiaryContainer: ColoresVitalia.pendienteSuave,
    onTertiaryContainer: const Color(0xFF334766),
    surface: ColoresVitalia.blanco,
    onSurface: ColoresVitalia.texto,
    outline: ColoresVitalia.borde,
    outlineVariant: ColoresVitalia.bordeTenue,
    error: ColoresVitalia.error,
    errorContainer: ColoresVitalia.errorSuave,
    onErrorContainer: const Color(0xFF782B3C),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: ColoresVitalia.fondoAzul,
    appBarTheme: const AppBarTheme(
      backgroundColor: ColoresVitalia.blanco,
      foregroundColor: ColoresVitalia.texto,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ColoresVitalia.texto,
      ),
    ),
    cardTheme: const CardThemeData(
      color: ColoresVitalia.blanco,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: ColoresVitalia.borde),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: ColoresVitalia.blanco,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      labelStyle: TextStyle(color: ColoresVitalia.textoSecundario),
      helperStyle: TextStyle(
        color: ColoresVitalia.textoSecundario,
        fontSize: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.azul, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        side: const BorderSide(color: ColoresVitalia.borde),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: ColoresVitalia.fondoAzul,
      selectedColor: ColoresVitalia.azulSuave,
      side: BorderSide(color: ColoresVitalia.bordeTenue),
      labelStyle: TextStyle(fontSize: 12, color: ColoresVitalia.texto),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    dividerColor: ColoresVitalia.bordeTenue,
  );
}
