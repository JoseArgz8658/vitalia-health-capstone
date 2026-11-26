import 'package:flutter/material.dart';

/// Sistema visual Vitalia: contraste legible y colores reservados para acciones
/// y estados. Los tonos suaves favorecen el uso prolongado de la aplicación.
abstract final class ColoresVitalia {
  static const azul = Color(0xFF245942);
  static const azulActivo = Color(0xFF19342A);
  static const azulSuave = Color(0xFFE7EFE8);
  static const verde = Color(0xFF2A6950);
  static const verdeSuave = Color(0xFFE8F2EB);
  static const fondoAzul = Color(0xFFF5F5EE);
  static const blanco = Color(0xFFFFFFFF);
  static const texto = Color(0xFF19342A);
  static const textoSecundario = Color(0xFF4D6256);
  static const borde = Color(0xFFD7DED5);
  static const bordeTenue = Color(0xFFE7EBE3);
  static const bordeControl = Color(0xFF768577);
  static const foco = Color(0xFF604276);
  static const focoRelleno = Color(0xFFF6CF7C);
  static const advertenciaSuave = Color(0xFFF6EBD3);
  static const pendienteSuave = Color(0xFFECF0FA);
  static const error = Color(0xFF9F3549);
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
    outline: ColoresVitalia.bordeControl,
    outlineVariant: ColoresVitalia.bordeTenue,
    error: ColoresVitalia.error,
    errorContainer: ColoresVitalia.errorSuave,
    onErrorContainer: const Color(0xFF782B3C),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    focusColor: const Color(0xFFE0D3EA),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
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
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      labelStyle: TextStyle(color: ColoresVitalia.textoSecundario),
      helperStyle: TextStyle(
        color: ColoresVitalia.textoSecundario,
        fontSize: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.bordeControl),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.bordeControl),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: ColoresVitalia.foco, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.focused)
                ? const BorderSide(color: ColoresVitalia.focoRelleno, width: 3)
                : null),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          return states.contains(WidgetState.focused)
              ? const BorderSide(color: ColoresVitalia.foco, width: 2)
              : const BorderSide(color: ColoresVitalia.bordeControl);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)).copyWith(
        side: WidgetStateProperty.resolveWith(_keyboardFocusBorder),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        side: WidgetStateProperty.resolveWith(_keyboardFocusBorder),
      ),
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

BorderSide? _keyboardFocusBorder(Set<WidgetState> states) =>
    states.contains(WidgetState.focused)
        ? const BorderSide(color: ColoresVitalia.foco, width: 2)
        : null;
