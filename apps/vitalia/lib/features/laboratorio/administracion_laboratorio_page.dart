import 'package:flutter/material.dart';

/// Administración separada de la operación de laboratorio.
/// Las funciones de gestión global no se simulan como activas.
class AdministracionLaboratorioPage extends StatelessWidget {
  const AdministracionLaboratorioPage({
    super.key,
    required this.email,
    required this.onLogout,
    this.validatorMode = false,
  });

  final String email;
  final VoidCallback onLogout;
  final bool validatorMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitalia Health'),
        actions: [
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      validatorMode
                          ? Icons.verified_user_outlined
                          : Icons.admin_panel_settings_outlined,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      validatorMode
                          ? 'Responsable de validación'
                          : 'Administración de Vitalia Health',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text('Cuenta: $email'),
                    const SizedBox(height: 16),
                    Text(
                      validatorMode
                          ? 'La revisión y validación profesional se habilitarán '
                            'cuando el registro de resultados y la auditoría '
                            'estén implementados.'
                          : 'Este acceso está reservado para la configuración '
                            'y gestión de usuarios del sistema. La recepción '
                            'de muestras y los resultados corresponden al '
                            'rol Operador de laboratorio.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Las opciones administrativas y de validación no '
                      'están habilitadas en esta etapa.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
