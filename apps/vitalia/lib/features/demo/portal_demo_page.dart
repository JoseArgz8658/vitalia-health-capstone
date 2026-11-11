import 'package:flutter/material.dart';
import '../acceso/acceso_page.dart';
import '../documentos/documentos_page.dart';
import '../profesional/profesional_page.dart';
import '../administracion/administracion_page.dart';
import '../examenes/examenes_page.dart';

/// Portal de integración visual. Ninguna opción representa permisos reales.
class PortalDemoPage extends StatelessWidget {
  const PortalDemoPage({super.key});
  void _abrir(BuildContext context, Widget pagina) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pagina));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vitalia Health')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: Center(child: SizedBox(width: 1000, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tus exámenes, en un solo lugar',
            style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          const Text('Prototipo visual con datos ficticios. '
            'Puedes explorar cada rol sin iniciar una sesión real.'),
          const SizedBox(height: 24),
          Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Acceso', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Revisa el formulario de correo y contraseña. '
                'La autenticación está pendiente.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _abrir(context, const AccesoPage()),
                icon: const Icon(Icons.login), label: const Text('Ver formulario de acceso')),
            ],
          ))),
          const SizedBox(height: 16),
          _tarjeta(context, 'Paciente', Icons.person_outline,
            'Seleccionar archivo, registrar sus datos y consultar los registros locales.',
            'Explorar paciente', const DocumentosPage()),
          _tarjeta(context, 'Profesional', Icons.medical_services_outlined,
            'Buscar pacientes ficticios y consultar exámenes e historial.',
            'Explorar profesional', const ProfesionalPage()),
          _tarjeta(context, 'Administrador', Icons.manage_accounts_outlined,
            'Consultar usuarios, resumen de permisos y ejemplo de auditoría.',
            'Explorar administrador', const AdministracionPage()),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _abrir(context, const ExamenesPage()),
            icon: const Icon(Icons.history),
            label: const Text('Consultar historial inicial con filtros'),
          ),
          const SizedBox(height: 16),
          const Text('Los registros locales del paciente aún no se sincronizan '
            'con otros paneles. No hay almacenamiento S3 ni procesamiento con IA.'),
        ],
      ))),
    ),
  );

  Widget _tarjeta(BuildContext context, String titulo, IconData icono,
    String descripcion, String accion, Widget pagina) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icono, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 12),
        Text(descripcion),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: () => _abrir(context, pagina), child: Text(accion)),
      ],
    )),
  );
}
