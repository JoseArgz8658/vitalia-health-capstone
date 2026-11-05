import 'package:flutter/material.dart';
import '../core/tema_vitalia.dart';
import '../features/demo/portal_demo_page.dart';

class VitaliaDemoApp extends StatelessWidget {
  const VitaliaDemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vitalia Health', debugShowCheckedModeBanner: false,
    theme: temaVitalia(), home: const PortalDemoPage(),
  );
}
