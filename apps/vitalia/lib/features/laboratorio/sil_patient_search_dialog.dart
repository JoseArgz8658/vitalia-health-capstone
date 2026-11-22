import 'package:flutter/material.dart';

import '../../core/auth_api.dart';

/// Búsqueda de pacientes vinculados al laboratorio, sin descargar el directorio.
/// La API aplica permisos por laboratorio y entrega sólo 20 coincidencias por página.
class SilPatientSearchDialog extends StatefulWidget {
  const SilPatientSearchDialog({
    super.key,
    required this.api,
    required this.labId,
    required this.onExpired,
  });

  final AuthApi api;
  final String labId;
  final VoidCallback onExpired;

  @override
  State<SilPatientSearchDialog> createState() => _SilPatientSearchDialogState();
}

class _SilPatientSearchDialogState extends State<SilPatientSearchDialog> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _patients = [];
  String? _error;
  bool _loading = false;
  bool _searched = false;
  bool _hasMore = false;
  int _offset = 0;
  int _requestVersion = 0;

  @override
  void dispose() {
    _requestVersion++;
    _search.dispose();
    super.dispose();
  }

  void _invalidate(String _) {
    // No permitir que una respuesta anterior reemplace otra búsqueda.
    _requestVersion++;
    setState(() {
      _patients = [];
      _offset = 0;
      _hasMore = false;
      _searched = false;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _loadPage(int offset) async {
    final term = _search.text.trim();
    if (term.length < 2 || term.length > 120) {
      setState(() => _error = 'Escribe al menos 2 caracteres del nombre o correo.');
      return;
    }
    FocusScope.of(context).unfocus();
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _patients = [];
    });
    final query = Uri(queryParameters: {
      'limit': '$_pageSize',
      'offset': '$offset',
      'search': term,
    }).query;
    try {
      final result = await widget.api.silMainRequest(
        '/labs/' + widget.labId + '/patients?' + query,
      );
      if (!mounted || version != _requestVersion || term != _search.text.trim()) {
        return;
      }
      final patients = (result['patients'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      setState(() {
        _patients = patients;
        _offset = offset;
        _hasMore = result['hasMore'] == true;
        _searched = true;
      });
    } on AuthFailure catch (error) {
      if (!mounted || version != _requestVersion) return;
      if (error.status == 401) {
        Navigator.of(context).pop();
        widget.onExpired();
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (mounted && version == _requestVersion) {
        setState(() => _error = 'No se pudo consultar el directorio. Intenta nuevamente.');
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  String _displayName(Map<String, dynamic> patient) {
    final name = [patient['givenNames'], patient['familyNames']]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    final email = patient['email'] as String? ?? '';
    return name.isEmpty ? email : name;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Seleccionar paciente'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Busca entre las cuentas activas y vinculadas a este laboratorio. '
              'Los resultados se consultan por páginas, sin cargar todos los pacientes.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.search,
              onChanged: _invalidate,
              onSubmitted: (_) => _loadPage(0),
              decoration: const InputDecoration(
                labelText: 'Nombre o correo del paciente',
                hintText: 'Ejemplo: Ana Pérez',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _loadPage(0),
                icon: const Icon(Icons.search),
                label: const Text('Buscar'),
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 290,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !_searched
                      ? const Center(
                          child: Text(
                            'Escribe al menos dos caracteres y pulsa Buscar.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _patients.isEmpty
                          ? const Center(
                              child: Text(
                                'No encontramos pacientes con ese nombre o correo en este laboratorio.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Scrollbar(
                              child: ListView.separated(
                                key: const ValueKey('sil-patient-search-results'),
                                itemCount: _patients.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final patient = _patients[index];
                                  final name = _displayName(patient);
                                  final email = patient['email'] as String? ?? '';
                                  return ListTile(
                                    key: ValueKey('patient-option-' + (patient['id'] as String)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    title: Text(name, overflow: TextOverflow.ellipsis),
                                    subtitle: email.isNotEmpty && name != email
                                        ? Text(email, overflow: TextOverflow.ellipsis)
                                        : null,
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(context)
                                        .pop<Map<String, dynamic>>(patient),
                                  );
                                },
                              ),
                            ),
            ),
            if (_searched && (_offset > 0 || _hasMore)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resultados ' + (_offset + 1).toString()
                          + '–' + (_offset + _patients.length).toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _loading || _offset == 0
                        ? null : () => _loadPage(_offset - _pageSize),
                    child: const Text('Anterior'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loading || !_hasMore || _offset >= 10000
                        ? null : () => _loadPage(_offset + _pageSize),
                    child: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
