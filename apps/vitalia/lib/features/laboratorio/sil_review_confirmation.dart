import 'package:flutter/material.dart';

Future<bool?> confirmSilReview(BuildContext context, {required bool approve}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Aprobar revisión' : 'Devolver orden'),
        content: Text(approve
            ? 'Se marcará la revisión interna como aprobada. '
                'Esto no publica resultados ni genera un informe clínico.'
            : 'La orden volverá al operador para corregir resultados. '
                'Se conservarán los valores y el motivo en la auditoría.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
