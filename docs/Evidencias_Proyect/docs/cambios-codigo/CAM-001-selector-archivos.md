# CAM-001 Dependencia para selección de archivos
Autorización explícita: usuario «autorizo añadir la dependencia», 30/09/2026.
Archivo existente modificado: apps/vitalia/pubspec.yaml.
Cambio: añadir únicamente file_selector: 1.1.0; dependencias anteriores intactas.
Motivo: selector nativo compartido Android/web sin implementar código separado por plataforma.
Consecuencia de no hacerlo: no se puede usar esta biblioteca para la selección multiplataforma.
Efecto: pub get descarga plugin y dependencias transitivas, actualiza pubspec.lock y registros generados de plugins cuando corresponda.
Riesgos: requisitos de SDK/platformas y fallas de acceso/cancelación. Se controla excepción y ciclo de vida.
La pantalla nueva solo consulta nombre/tamaño, no guarda ni transmite archivos.
Comprobado: documentación oficial del plugin y soporte Android/web; lectura de pubspec anterior.
Pendiente: pub get, analyze y pruebas Edge/Android en equipo usuario. No hay Flutter en entorno asistente.
Reversión: restaurar pubspec anterior y regenerar lock con pub get, previa autorización para nuevas modificaciones. Usar entradas previas.
Fuente: https://pub.dev/packages/file_selector
