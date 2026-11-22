import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

/// Selector administrativo de una o varias sedes. No concede permisos por sí mismo:
/// el backend vuelve a validar la membresía, las sedes y el laboratorio.
class SilAdminOperatorDialog {
  static Future<Map<String, dynamic>?> open({
    required BuildContext context,
    required AuthApi api,
    required String labId,
    required String labName,
    Map<String, dynamic>? member,
  }) async {
    final response = await api.silMainRequest('/labs/$labId/sites');
    if (!context.mounted) return null;
    final sites = (response['sites'] as List? ?? [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .where((entry) => entry['active'] == true)
        .toList();
    var email = (member?['email'] as String? ?? '').trim().toLowerCase();
    var linkExisting = false;
    var mode = member?['siteAccessMode'] as String? ??
        (sites.isEmpty ? 'all' : 'selected');
    final selected = <String>{
      for (final id in member?['siteIds'] as List? ?? <String>[]) id as String,
    };
    String? error;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(member == null ? 'Agregar operador' : 'Asignar sedes'),
          scrollable: true,
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Laboratorio: $labName'),
                const SizedBox(height: 16),
                if (member == null) ...[
                  const Text('¿Ya tiene una cuenta de operador en Vitalia?'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Nuevo')),
                      ButtonSegment(value: true, label: Text('Ya tiene cuenta')),
                    ],
                    selected: {linkExisting},
                    onSelectionChanged: (value) => update(() {
                      linkExisting = value.first;
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    autofocus: true,
                    initialValue: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo del operador',
                      helperText: 'Debe corresponder al destinatario autorizado.',
                    ),
                    onChanged: (value) => email = value.trim().toLowerCase(),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  Text(email, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Acceso a sedes'),
                  items: const [
                    DropdownMenuItem(value: 'selected',
                        child: Text('Solo sedes seleccionadas')),
                    DropdownMenuItem(value: 'all', child: Text('Todas las sedes')),
                  ],
                  onChanged: (value) => update(() {
                    mode = value ?? mode;
                    error = null;
                  }),
                ),
                const SizedBox(height: 10),
                if (mode == 'all')
                  const Text('Incluye las sedes nuevas que se creen en este laboratorio.'),
                if (mode == 'selected') ...[
                  if (sites.isEmpty)
                    const Text('No hay sedes activas. Crea una sede o selecciona «Todas las sedes».'),
                  for (final site in sites)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(site['name'] as String),
                      subtitle: Text(site['commune'] as String? ?? ''),
                      value: selected.contains(site['id']),
                      onChanged: (checked) => update(() {
                        final id = site['id'] as String;
                        if (checked == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                        error = null;
                      }),
                    ),
                  const Text('El operador tendrá acceso operativo únicamente a esas sedes.'),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (member == null &&
                    !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  update(() => error = 'Ingresa un correo válido.');
                  return;
                }
                final chosen = mode == 'all' ? <String>[] :
                    sites.where((site) => selected.contains(site['id']))
                        .map((site) => site['id'] as String).toList();
                if (mode == 'selected' && chosen.isEmpty) {
                  update(() => error = 'Selecciona al menos una sede activa.');
                  return;
                }
                Navigator.of(dialog).pop({
                  'email': email,
                  'existing': linkExisting,
                  'siteAccess': {'mode': mode, 'siteIds': chosen},
                });
              },
              child: Text(member == null ? 'Continuar' : 'Guardar asignación'),
            ),
          ],
        ),
      ),
    );
  }
}
