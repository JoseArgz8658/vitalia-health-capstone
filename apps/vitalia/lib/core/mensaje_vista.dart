import 'package:flutter/material.dart';

/// Aviso legible con icono; el significado no depende solo del color.
class MensajeVista extends StatelessWidget {
  const MensajeVista({super.key, required this.text,
    this.icon = Icons.info_outline, this.error = false});
  final String text;
  final IconData icon;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(liveRegion: true, child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: error ? colors.onErrorContainer : colors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(
          color: error ? colors.onErrorContainer : colors.onSurfaceVariant))),
      ]),
    ));
  }
}
