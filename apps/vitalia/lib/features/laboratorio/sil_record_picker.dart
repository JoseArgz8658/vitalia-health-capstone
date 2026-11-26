import 'package:flutter/material.dart';

typedef SilRecordOption = ({String id, String title, String detail});

class SilRecordPicker extends StatelessWidget {
  const SilRecordPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.searchLabel = 'Buscar en esta lista',
  });

  final String label;
  final List<SilRecordOption> options;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final String searchLabel;

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
  });

  final String label;
  final List<SilRecordOption> options;
  final String searchLabel;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  static const _pageSize = 10;
  String _query = '';
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    final matches = widget.options.where((row) {
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
                  child: ListTile(
                    title: Text(row.title),
                    subtitle: row.detail.isEmpty ? null : Text(row.detail),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(row.id),
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
