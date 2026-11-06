import 'package:flutter/material.dart';
import 'core/tema_vitalia.dart';
import 'features/archivos/archivo_page.dart';

void main() => runApp(MaterialApp(
  title: 'Vitalia Health', debugShowCheckedModeBanner: false,
  theme: temaVitalia(), home: const ArchivoPage(),
));
