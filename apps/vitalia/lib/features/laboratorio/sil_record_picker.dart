import 'package:flutter/material.dart';

import 'sil_operator_workbench.dart';

typedef SilRecordOption = ({String id, String title, String detail});

class SilRecordPicker extends StatelessWidget {
  const SilRecordPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.searchLabel = 'Buscar en esta lista',
    this.sitesById = const {},
  });

  final String label;
  final List<SilRecordOption> options;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final String searchLabel;
  final Map<String, String> sitesById;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((row) => row.id == selectedId).firstOrNull;
    return OutlinedButton.icon(
      onPressed: onSelected == null || options.isEmpty
          ? null
          : () async {
              final id = await showDialog<String>(
                context: context,
                builder: (_) => _RecordDialog(
                  label: label,
                  options: options,
                  searchLabel: searchLabel,
                  sitesById: sitesById,
                ),
              );
              if (context.mounted && id != null) onSelected?.call(id);
            },
      icon: const Icon(Icons.search),
      label: Text(selected == null ? label : selected.title),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({
    required this.label,
    required this.options,
    required this.searchLabel,
    required this.sitesById,
  });

  final String label;
  final List<SilRecordOption> options;
  final String searchLabel;
  final Map<String, String> sitesById;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  static const _pageSize = 6;
  String _query = '';
  String _site = '';
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    final sites = widget.sitesById.values.toSet().toList()..sort();
    final matches = widget.options.where((row) {
      if (_site.isNotEmpty && widget.sitesById[row.id] != _site) return false;
      final text = '${row.title} ${row.detail}'.toLowerCase();
      return tokens.every(text.contains);
    }).toList();
    final visible = matches.skip(_offset).take(_pageSize).toList();
    return AlertDialog(
      title: Text(widget.label),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.searchLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (query) => setState(() {
                _query = query;
                _offset = 0;
              }),
            ),
            const SizedBox(height: 12),
            if (sites.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _site,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Filtrar por sede'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todas las sedes')),
                  for (final site in sites)
                    DropdownMenuItem(value: site, child: Text(site)),
                ],
                onChanged: (site) => setState(() {
                  _site = site ?? '';
                  _offset = 0;
                }),
              ),
              const SizedBox(height: 10),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                matches.isEmpty
                    ? 'Sin coincidencias. Prueba otra búsqueda.'
                    : 'Resultados ${_offset + 1} a ${_offset + visible.length} de ${matches.length}',
              ),
            ),
            const Divider(),
            for (final row in visible)
              MergeSemantics(
                child: Semantics(
                  button: true,
                  child: SilWorkbenchRow(
                    icon: Icons.description_outlined,
                    primary: Text(row.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    secondary: row.detail.isEmpty ? null : Text(row.detail),
                    onOpen: () => Navigator.of(context).pop(row.id),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _offset == 0 ? null : () => setState(() => _offset -= _pageSize),
          child: const Text('Anterior'),
        ),
        TextButton(
          onPressed: _offset + _pageSize >= matches.length
              ? null
              : () => setState(() => _offset += _pageSize),
          child: const Text('Siguiente'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
