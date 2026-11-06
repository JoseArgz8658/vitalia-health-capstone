import 'package:flutter/material.dart';
import '../features/inicio/inicio_page.dart';

/// Composición compartida para web y Android.
class VitaliaApp extends StatelessWidget {
  const VitaliaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vitalia Health',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F8C)),
      scaffoldBackgroundColor: const Color(0xFFF5F8FA),
    ),
    home: const InicioPage(),
  );
}
