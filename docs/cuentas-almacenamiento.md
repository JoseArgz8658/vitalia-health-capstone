# Dónde se guardan los datos
Entorno local actual:
- PostgreSQL configurado en backend/.env: tabla public.vitalia_accounts contiene id, email,
  password_hash, role_code y created_at. La contraseña no se almacena en texto plano.
- public.vitalia_sessions guarda la huella del token y su expiración.
- public.vitalia_documents guarda metadatos y clave interna S3.
- public.vitalia_document_audit registra acciones de documentos.
- S3 guarda el contenido de PDF/imágenes. No guarda las cuentas de paciente.

Para consultar cuentas en pgAdmin: Servers → servidor PostgreSQL 16 → Databases →
base configurada en PGDATABASE → Schemas → public → Tables → vitalia_accounts.
Botón derecho → View/Edit Data → All Rows.
No editar roles manualmente para conceder acceso durante pruebas del flujo de paciente.

Consulta sin hashes:
SELECT id, email, role_code, created_at FROM public.vitalia_accounts ORDER BY created_at DESC;

Que S3 esté en AWS no convierte PostgreSQL local en una base en la nube.
Al desplegar, configurar una instancia PostgreSQL y migraciones; los datos locales
no se trasladan automáticamente al desplegar código.
