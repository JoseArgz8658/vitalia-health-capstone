import 'package:flutter/material.dart';
import 'core/tema_vitalia.dart';
import 'features/roles/seleccion_roles_page.dart';

void main() => runApp(MaterialApp(
  title: 'Vitalia Health', debugShowCheckedModeBanner: false,
  theme: temaVitalia(), home: const SeleccionRolesPage(),
));
