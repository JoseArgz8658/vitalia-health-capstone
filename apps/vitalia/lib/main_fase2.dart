import 'package:flutter/material.dart';
import 'core/tema_vitalia.dart';
import 'features/examenes/examenes_page.dart';

/// Entrada incremental: mantiene intacta la demostración validada de fase 1.
void main() => runApp(MaterialApp(
  title: 'Vitalia Health',
  debugShowCheckedModeBanner: false,
  theme: temaVitalia(),
  home: const ExamenesPage(),
));
