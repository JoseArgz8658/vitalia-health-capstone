import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import 'sil_workspace.dart';

class SilAdminSites extends StatefulWidget {
  const SilAdminSites({
    super.key,
    required this.api,
    required this.labId,
    required this.onExpired,
  });

  final AuthApi api;
  final String labId;
  final VoidCallback onExpired;

  @override
  State<SilAdminSites> createState() => _SilAdminSitesState();
}

class _SilAdminSitesState extends State<SilAdminSites> {
  String get _path => '/labs/${widget.labId}/sites';
  late Future<Map<String, dynamic>> _sites;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sites = widget.api.silMainRequest(_path);
  }

  void _refresh() => setState(() => _sites = widget.api.silMainRequest(_path));

  Future<void> _save(String path, Map<String, dynamic> body) async {
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.silMainRequest(path, body: body);
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sede actualizada.')),
        );
      }
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.status == 401) {
        widget.onExpired();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.status == 409
              ? 'Ya existe una sede con ese nombre en el laboratorio.'
              : error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map? site]) async {
    final values = <String, String>{
      for (final key in ['name', 'address', 'commune', 'region', 'phone', 'email'])
        key: site?[key] as String? ?? '',
    };
    final key = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(site == null ? 'Nueva sede' : 'Editar sede'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in const [
                  ('name', 'Nombre', 2, 120),
                  ('address', 'Dirección', 3, 200),
                  ('commune', 'Comuna', 2, 100),
                  ('region', 'Región (opcional)', 0, 100),
                  ('phone', 'Teléfono (opcional)', 0, 32),
                  ('email', 'Correo (opcional)', 0, 254),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      initialValue: values[field.$1],
                      decoration: InputDecoration(labelText: field.$2),
                      onSaved: (value) => values[field.$1] = (value ?? '').trim(),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.length < field.$3 || text.length > field.$4) {
                          return 'Revisa la longitud.';
                        }
                        if (field.$1 == 'email' && text.isNotEmpty &&
                            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                          return 'Ingresa un correo válido.';
                        }
                        return null;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final form = key.currentState!;
              if (!form.validate()) return;
              form.save();
              Navigator.pop(dialog, true);
            },
            child: const Text('Guardar sede'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _save(_path, {
      if (site != null) 'siteId': site['id'],
      for (final entry in values.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    });
  }

  Future<void> _toggle(Map site) async {
    final active = site['active'] != true;
    final label = active ? 'Activar' : 'Desactivar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$label sede'),
        content: Text(active
            ? '${site['name']} estará disponible para nuevas recepciones.'
            : '${site['name']} dejará de estar disponible para nuevas recepciones. Sus órdenes conservarán la sede.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(label)),
        ],
      ),
    );
    if (confirmed == true) {
      await _save('$_path/state', {'siteId': site['id'], 'active': active});
    }
  }

  @override
  Widget build(BuildContext context) => SilWorkspaceSurface(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SilWorkspaceHeading(
          section: true,
          title: 'Sedes del laboratorio',
          actions: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Nueva sede'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<Map<String, dynamic>>(
          future: _sites,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator(semanticsLabel: 'Cargando sedes');
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  const Text('No se pudieron consultar las sedes.'),
                  TextButton(
                    onPressed: error is AuthFailure && error.status == 401
                        ? widget.onExpired : _refresh,
                    child: Text(error is AuthFailure && error.status == 401
                        ? 'Volver a ingresar' : 'Reintentar'),
                  ),
                ],
              );
            }
            final sites = (snapshot.data?['sites'] as List? ?? []).cast<Map>();
            if (sites.isEmpty) return const Text('Este laboratorio aún no tiene sedes.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final site in sites) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(site['name'] as String),
                    subtitle: Text(
                      '${site['address']} · ${site['commune']} · '
                      '${site['active'] == true ? 'Activa' : 'Inactiva'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Acciones de ${site['name']}',
                      enabled: !_busy,
                      onSelected: (value) => value == 'edit' ? _edit(site) : _toggle(site),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(
                          value: 'state',
                          child: Text(site['active'] == true ? 'Desactivar' : 'Activar'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}
