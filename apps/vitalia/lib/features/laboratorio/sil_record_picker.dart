import 'package:flutter/material.dart';

typedef SilRecordOption = ({String id, String title, String detail});

class SilRecordPicker extends StatelessWidget {
  const SilRecordPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final String label;
  final List<SilRecordOption> options;
  final String? selectedId;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((row) => row.id == selectedId).firstOrNull;
    return OutlinedButton.icon(
      onPressed: onSelected == null || options.isEmpty
          ? null
          : () async {
              final id = await showDialog<String>(
                context: context,
                builder: (_) => _RecordDialog(label: label, options: options),
              );
              if (context.mounted && id != null) onSelected?.call(id);
            },
      icon: const Icon(Icons.search),
      label: Text(selected == null ? label : selected.title),
    );
  }
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.label, required this.options});

  final String label;
  final List<SilRecordOption> options;

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
      content: SizedBox(
        width: 560,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar en esta lista',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) => setState(() {
                _query = query;
                _offset = 0;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              matches.isEmpty
                  ? 'Sin coincidencias'
                  : '${_offset + 1} a ${_offset + visible.length} de ${matches.length}',
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final row = visible[index];
                  return ListTile(
                    title: Text(row.title),
                    subtitle: row.detail.isEmpty ? null : Text(row.detail),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(row.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _offset == 0
              ? null
              : () => setState(() => _offset -= _pageSize),
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
