import 'dart:convert';

const silPatientDemo = bool.fromEnvironment('VITALIA_SIL_DEMO_MODE');

String? validatePatientEmail(String? value, {bool demo = silPatientDemo}) {
  final email = (value ?? '').trim().toLowerCase();
  if (email.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Escribe un correo válido.';
  }
  if (demo && !email.endsWith('@example.invalid')) {
    return 'Usa un correo ficticio @example.invalid.';
  }
  return null;
}

String? validateNewPatientPassword(String? value) {
  final password = value ?? '';
  if (password.runes.length < 12) return 'Usa al menos 12 caracteres.';
  if (utf8.encode(password).length > 1024)
    return 'La contraseña es demasiado larga.';
  return null;
}
