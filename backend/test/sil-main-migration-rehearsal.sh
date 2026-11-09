#!/bin/sh
# IMPORTANTE: SOLO sobre PostgreSQL temporal sin red ni puertos.
# Ejecutado desde deploy/rehearse-main-sil-migrations.ps1.
# No ejecutar directamente en contenedores productivos.
set -eu

if [ "$VITALIA_ISOLATED_REHEARSAL" != "YES" ] || [ "$PGDATABASE" != "vitalia_restored" ] || [ "$PGUSER" != "vitalia_restore" ]; then
  echo "BLOQUEADO: solo se permite el ensayo en la copia aislada." >&2
  exit 1
fi

dir="/tmp/vitalia-migration-rehearsal/migrations"
log="/tmp/vitalia-migration-rehearsal/steps.log"
psql_check() {
  psql -X --set=ON_ERROR_STOP=1 --no-align --tuples-only --command="$1"
}

baseline_ok="$(psql_check "SELECT current_database()='vitalia_restored' AND (SELECT count(*)=12 FROM public.vitalia_schema_migrations) AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='012_preliminary_assistant') AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='011_exam_assistant') AND NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='012_profiles_locations') AND NOT EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version LIKE '013_%');")"
if [ "$baseline_ok" != "t" ]; then
  echo "BLOQUEADO: historial del respaldo distinto al esperado." >&2
  exit 1
fi

if [ ! -d "$dir" ]; then
  echo "No se encontraron los SQL dentro del contenedor temporal." >&2
  exit 1
fi

baseline_counts="$(psql_check "SELECT (SELECT count(*) FROM public.vitalia_accounts)::text || '|' || (SELECT count(*) FROM public.vitalia_sessions)::text || '|' || (SELECT count(*) FROM public.vitalia_documents)::text || '|' || (SELECT count(*) FROM public.vitalia_document_audit)::text;")"
echo "Historial original: 12 migraciones. Cuentas/sesiones/documentos/auditoria: $baseline_counts"
: > "$log"

# Solo 012_profiles_locations..032. No ejecuta 033–037 porque
# todavía contienen estructuras especificas de demostracion.
n=12
while [ "$n" -le 32 ]; do
  prefix="$(printf '%03d' "$n")"
  set -- "$dir/$prefix"_"*.sql"
  if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "BLOQUEADO: se esperaba un solo archivo SQL para $prefix." >&2
    exit 1
  fi
  file="$1"
  version="$(basename "$file" .sql)"
  case "$version" in
    [0-9][0-9][0-9]_[a-z_]*) ;;
    *) echo "Nombre de archivo no permitido." >&2; exit 1 ;;
  esac
  checksum="$(sed 's/\r$//' "$file" | sha256sum | cut -c1-64)"
  case "$checksum" in
    *[!0-9a-f]*|'') echo "SHA256 inválido." >&2; exit 1 ;;
  esac
  if [ "$(printf '%s' "$checksum" | wc -c)" -ne 64 ]; then
    echo "Longitud de huella inválida." >&2
    exit 1
  fi

  echo "Ensayando: $version"
  # Una unica transaccion por archivo + registro de huella; todo
  # ejecutado EXCLUSIVAMENTE en la base temporal restaurada.
  if ! psql -X --set=ON_ERROR_STOP=1 --single-transaction \
    --file="$file" \
    --command="INSERT INTO public.vitalia_schema_migrations(version,checksum) VALUES('$version','$checksum');" \
    > "$log" 2>&1; then
    echo "FALLÓ MIGRACIÓN: $version (solo en copia temporal)." >&2
    tail -n 26 "$log" >&2
    exit 1
  fi
  n=$((n + 1))
done

final_counts="$(psql_check "SELECT (SELECT count(*) FROM public.vitalia_accounts)::text || '|' || (SELECT count(*) FROM public.vitalia_sessions)::text || '|' || (SELECT count(*) FROM public.vitalia_documents)::text || '|' || (SELECT count(*) FROM public.vitalia_document_audit)::text;")"
if [ "$final_counts" != "$baseline_counts" ]; then
  echo "ERROR: cambiaron los recuentos de datos originales en la copia." >&2
  echo "Antes: $baseline_counts; despues: $final_counts" >&2
  exit 1
fi

roles_ok="$(psql_check "SELECT (SELECT count(*) FROM public.vitalia_account_roles)=(SELECT count(*) FROM public.vitalia_accounts) AND (SELECT count(*) FROM public.vitalia_sessions WHERE active_role IS NULL)=0;")"
if [ "$roles_ok" != "t" ]; then
  echo "ERROR: permisos o sesiones no consistentes." >&2
  exit 1
fi

complete="$(psql_check "SELECT (SELECT count(*)=33 FROM public.vitalia_schema_migrations) AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='012_preliminary_assistant') AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='012_profiles_locations') AND EXISTS(SELECT 1 FROM public.vitalia_schema_migrations WHERE version='032_sil_audit_download') AND to_regclass('public.vitalia_sil_orders') IS NOT NULL AND to_regclass('public.vitalia_sil_external_reports') IS NOT NULL;")"
if [ "$complete" != "t" ]; then
  echo "ERROR: estado final del esquema incompleto." >&2
  exit 1
fi

echo "ENSAYO DE MIGRACIONES 012-032 APROBADO"
echo "Migraciones en copia: 33"
echo "Historiales 012 legado y 012 de perfiles: preservados."
echo "Cuentas/sesiones/documentos/auditoria: $final_counts (sin cambios)"
echo "Migraciones 033-037: NO ejecutadas."
echo "No se escribio en Vitalia principal."
