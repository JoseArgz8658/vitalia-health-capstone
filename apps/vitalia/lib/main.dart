import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app/vitalia_mvp_app.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // La web necesita el árbol semántico desde la primera pantalla.
  if (kIsWeb) binding.ensureSemantics();
  runApp(const VitaliaMvpApp());
}
