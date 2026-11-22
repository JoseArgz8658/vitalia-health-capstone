import 'package:flutter/material.dart';

import '../../core/auth_api.dart';
import 'sil_workspace.dart';

class SilAdminSites extends StatefulWidget {
  const SilAdminSites({
    super.key,
    required this.api,
    required this.labId,
    required this.labName,
    required this.onExpired,
  });

  final AuthApi api;
  final String labId;
  final String labName;
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
    setState(() => _busy = true);
    late final Map<String, dynamic> catalog;
    try {
      catalog = await widget.api.silMainRequest('/site-territories');
    } on AuthFailure catch (error) {
      if (mounted) {
        if (error.status == 401) {
          widget.onExpired();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo cargar el catálogo territorial. Intenta de nuevo.')),
          );
        }
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    final regions = (catalog['regions'] as List).cast<Map>();
    final provinces = (catalog['provinces'] as List).cast<Map>();
    final communes = (catalog['communes'] as List).cast<Map>()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    var region = regions.where((item) => item['name'] == site?['region']).firstOrNull;
    List<Map> localCommunes() {
      final codes = provinces.where((item) => item['regionCode'] == region?['code'])
          .map((item) => item['code']).toSet();
      return communes.where((item) => codes.contains(item['provinceCode'])).toList();
    }

    var commune = localCommunes().where((item) => item['name'] == site?['commune']).firstOrNull;
    final values = <String, String>{
      for (final field in ['name', 'address', 'phone', 'email'])
        field: site?[field] as String? ?? '',
    };
    final key = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(site == null ? 'Nueva sede' : 'Editar sede'),
          scrollable: true,
          content: SizedBox(
            width: 480,
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.business_outlined),
                    title: Text(widget.labName),
                    subtitle: const Text('Laboratorio principal al que pertenece la sede'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: values['name'],
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la sede',
                      hintText: 'Ej. Casa matriz o Sede Providencia',
                    ),
                    onSaved: (value) => values['name'] = value!.trim(),
                    validator: (value) {
                      final length = (value ?? '').trim().length;
                      return length >= 2 && length <= 120 ? null : 'Ingresa un nombre entre 2 y 120 caracteres.';
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Map>(
                    initialValue: region,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Región'),
                    items: [
                      for (final item in regions)
                        DropdownMenuItem(value: item, child: Text(item['name'] as String, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (value) => update(() {
                      region = value;
                      commune = null;
                      values['address'] = '';
                    }),
                    validator: (value) => value == null ? 'Selecciona la región.' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Map>(
                    key: ValueKey(region?['code']),
                    initialValue: commune,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Comuna',
                      helperText: region == null ? 'Primero selecciona la región.' : null,
                    ),
                    items: [
                      for (final item in localCommunes())
                        DropdownMenuItem(value: item, child: Text(item['name'] as String, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: region == null ? null : (value) => update(() {
                      commune = value;
                      values['address'] = '';
                    }),
                    validator: (value) => value == null ? 'Selecciona la comuna.' : null,
                  ),
                  const SizedBox(height: 12),
                  for (final (field, label, minimum, maximum) in const [
                    ('address', 'Calle y número', 3, 200),
                    ('phone', 'Teléfono (opcional)', 0, 32),
                    ('email', 'Correo (opcional)', 0, 254),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        key: field == 'address' ? ValueKey(commune?['code']) : null,
                        enabled: field != 'address' || commune != null,
                        initialValue: values[field],
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: field == 'address'
                              ? (commune == null ? 'Primero selecciona la comuna.' : 'Dirección dentro de ${commune!['name']}.')
                              : null,
                        ),
                        onSaved: (value) => values[field] = (value ?? '').trim(),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (field == 'address' && commune == null) return null;
                          if (text.length < minimum || text.length > maximum) return 'Revisa este campo.';
                          if (field == 'phone' && text.isNotEmpty && !RegExp(r'^[+0-9 ()-]{5,32}$').hasMatch(text)) {
                            return 'Ingresa un teléfono válido.';
                          }
                          if (field == 'email' && text.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
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
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')),
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
      ),
    );
    if (accepted != true || !mounted) return;
    await _save(_path, {
      if (site != null) 'siteId': site['id'],
      'region': region!['name'],
      'commune': commune!['name'],
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
          title: widget.labName,
          description: 'Laboratorio principal · Sedes y datos de contacto',
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
            final active = sites.where((site) => site['active'] == true).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text('${sites.length} sedes registradas · $active activas · ${sites.length - active} inactivas'),
                ),
                for (final site in sites) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(site['name'] as String),
                        Text(site['active'] == true ? 'Activa' : 'Inactiva',
                            style: Theme.of(context).textTheme.labelMedium),
                      ],
                    ),
                    leading: const Icon(Icons.location_on_outlined),
                    subtitle: Text([
                      [site['address'], site['commune'], site['region']].whereType<String>().join(', '),
                      [site['phone'], site['email']].whereType<String>().join(' · '),
                    ].where((line) => line.isNotEmpty).join('\n')),
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
