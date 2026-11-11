#!/bin/sh
# Ensayo exclusivamente en PostgreSQL temporal sin red ni puertos.
set -eu

if [ "${VITALIA_ISOLATED_REHEARSAL:-}" != "YES" ] ||
   [ "${PGDATABASE:-}" != "vitalia_restored" ] ||
   [ "${PGUSER:-}" != "vitalia_restore" ] ||
   [ "${PGHOST:-}" != "/var/run/postgresql" ]; then
  echo "BLOQUEADO: solo se permite el ensayo en la copia aislada." >&2
  exit 1
fi

workdir=/tmp/vitalia-migration-rehearsal
dir="$workdir/migrations"
plan="$workdir/plan.sql"
steps="$workdir/migrations.sql"
umask 077
: > "$steps"

cat > "$plan" <<'SQL'
DO $$
BEGIN
  IF current_database() <> 'vitalia_restored' OR current_user <> 'vitalia_restore'
    OR inet_server_addr() IS NOT NULL THEN
    RAISE EXCEPTION 'BLOQUEADO: conexion fuera de la copia aislada';
  END IF;
END $$;

CREATE TEMP TABLE expected_ledger (version text PRIMARY KEY, checksum text NOT NULL);
SQL

n=1
while [ "$n" -le 32 ]; do
  prefix="$(printf '%03d' "$n")"
  set -- "$dir"/"$prefix"_*.sql
  if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "BLOQUEADO: se esperaba un solo archivo SQL para $prefix." >&2
    exit 1
  fi
  file="$1"
  version="$(basename "$file" .sql)"
  if ! printf '%s\n' "$version" | LC_ALL=C grep -Eq '^[0-9]{3}_[a-z_]+$'; then
    echo "Nombre de archivo no permitido." >&2
    exit 1
  fi
  case "$n:$version" in
    12:012_profiles_locations|32:032_sil_audit_download) ;;
    12:*|32:*) echo "Migracion inesperada para $prefix." >&2; exit 1 ;;
  esac

  # PowerShell entrego UTF-8 sin BOM y LF. Hash de los mismos bytes que lee psql.
  hash_line="$(sha256sum "$file")"
  checksum="${hash_line%% *}"
  if ! printf '%s\n' "$checksum" | LC_ALL=C grep -Eq '^[a-f0-9]{64}$'; then
    echo "Huella SHA256 invalida para $version." >&2
    exit 1
  fi
  printf "INSERT INTO expected_ledger VALUES ('%s','%s');\n" "$version" "$checksum" >> "$plan"
  if [ "$n" -ge 12 ]; then
    printf '\\echo Ensayando: %s\n\\i %s\n' "$version" "$file" >> "$steps"
    printf "INSERT INTO public.vitalia_schema_migrations(version,checksum) VALUES('%s','%s');\n" "$version" "$checksum" >> "$steps"
  fi
  n=$((n + 1))
done

cat >> "$plan" <<'SQL'
CREATE TEMP TABLE historical_ledger AS TABLE public.vitalia_schema_migrations;
DO $$
DECLARE
  mismatched_versions text;
BEGIN
  IF (SELECT count(*) FROM historical_ledger) <> 12
    OR NOT EXISTS (
      SELECT FROM historical_ledger
      WHERE version='012_preliminary_assistant' AND checksum ~ '^[a-f0-9]{64}$'
    )
    OR to_regclass('public.vitalia_account_roles') IS NOT NULL
    OR NOT EXISTS (
      SELECT FROM information_schema.columns
      WHERE table_schema='public' AND table_name='vitalia_exam_assistant_threads'
        AND column_name='processing_id' AND data_type='uuid'
    )
    OR NOT EXISTS (
      SELECT FROM information_schema.columns
      WHERE table_schema='public' AND table_name='vitalia_exam_assistant_threads'
        AND column_name='review_id' AND is_nullable='YES'
    ) THEN
    RAISE EXCEPTION 'BLOQUEADO: historial o esquema 012 legado distinto al esperado';
  END IF;

  SELECT string_agg(expected.version, ', ' ORDER BY expected.version)
    INTO mismatched_versions
    FROM expected_ledger expected
    LEFT JOIN historical_ledger historic USING (version)
    WHERE left(expected.version,3) BETWEEN '001' AND '011'
      AND historic.checksum IS DISTINCT FROM expected.checksum;
  IF mismatched_versions IS NOT NULL THEN
    RAISE EXCEPTION 'BLOQUEADO: migraciones historicas ausentes o con huella diferente: %', mismatched_versions;
  END IF;
END $$;

-- Solo existen en esta sesion y nunca se imprimen filas ni hashes de cuentas.
CREATE TEMP TABLE protected_relations AS
  SELECT tablename::text AS relation
  FROM pg_tables WHERE schemaname='public' AND left(tablename,8)='vitalia_'
    AND tablename NOT IN ('vitalia_schema_migrations','vitalia_sessions');
CREATE TEMP TABLE protected_rows (relation text, snapshot jsonb);
DO $$
DECLARE
  relation_name text;
BEGIN
  FOR relation_name IN
    SELECT relation FROM protected_relations
  LOOP
    EXECUTE format('INSERT INTO protected_rows SELECT %L, to_jsonb(t) FROM public.%I t',
                   relation_name, relation_name);
  END LOOP;
END $$;
-- 027 agrega al catalogo los dos roles SIL, sin asignarlos a cuentas.
INSERT INTO protected_rows VALUES
  ('vitalia_roles','{"code":"operador_laboratorio"}'),
  ('vitalia_roles','{"code":"validador_laboratorio"}');

-- 017 asigna el modo legado. En este respaldo anterior a 017, todas las
-- sesiones reciben ese mismo rol y ninguna cumple el criterio de baja de 018.
CREATE TEMP TABLE expected_sessions AS
  SELECT to_jsonb(s) || jsonb_build_object('active_role', a.role_code) AS snapshot
  FROM public.vitalia_sessions s JOIN public.vitalia_accounts a ON a.id=s.account_id;
SQL

cat "$steps" >> "$plan"

cat >> "$plan" <<'SQL'
SET CONSTRAINTS ALL IMMEDIATE;
DO $$
DECLARE
  relation_name text;
  changed boolean;
BEGIN
  FOR relation_name IN
    SELECT relation FROM protected_relations
  LOOP
    EXECUTE format(
      'WITH before_rows AS (SELECT snapshot FROM protected_rows WHERE relation=$1),
       after_rows AS (
         SELECT CASE WHEN $1=''vitalia_documents'' AND to_jsonb(t)->''care_flow''=''false''::jsonb
                     THEN to_jsonb(t)-''care_flow'' ELSE to_jsonb(t) END AS snapshot FROM public.%I t
       )
       SELECT EXISTS ((TABLE before_rows EXCEPT ALL TABLE after_rows)
                     UNION ALL (TABLE after_rows EXCEPT ALL TABLE before_rows))',
      relation_name
    ) INTO changed USING relation_name;
    IF changed THEN
      RAISE EXCEPTION 'ERROR: se alteraron datos historicos en %', relation_name;
    END IF;
  END LOOP;

  IF EXISTS (
    (SELECT snapshot FROM expected_sessions EXCEPT ALL SELECT to_jsonb(s) FROM public.vitalia_sessions s)
    UNION ALL
    (SELECT to_jsonb(s) FROM public.vitalia_sessions s EXCEPT ALL SELECT snapshot FROM expected_sessions)
  ) THEN
    RAISE EXCEPTION 'ERROR: la 017/018 no preservo las sesiones legadas con su modo original';
  END IF;

  IF (SELECT count(*) FROM public.vitalia_account_roles) <> (SELECT count(*) FROM public.vitalia_accounts)
    OR EXISTS (
      SELECT FROM public.vitalia_accounts a
      LEFT JOIN public.vitalia_account_roles r ON r.account_id=a.id AND r.role_code=a.role_code
      WHERE r.active IS DISTINCT FROM true OR r.grant_source IS DISTINCT FROM 'legacy'
        OR r.invitation_id IS NOT NULL OR r.password_hash IS NOT NULL
    ) THEN
    RAISE EXCEPTION 'ERROR: permisos legados inconsistentes tras 017/018';
  END IF;

  IF (SELECT count(*) FROM public.vitalia_schema_migrations) <> 33
    OR EXISTS (
      TABLE historical_ledger EXCEPT ALL TABLE public.vitalia_schema_migrations
    )
    OR EXISTS (
      SELECT version,checksum FROM expected_ledger
      EXCEPT ALL SELECT version,checksum FROM public.vitalia_schema_migrations
    )
    OR to_regclass('public.vitalia_people') IS NULL
    OR to_regclass('public.vitalia_sil_orders') IS NULL
    OR to_regclass('public.vitalia_sil_external_reports') IS NULL THEN
    RAISE EXCEPTION 'ERROR: historial o esquema final incompleto';
  END IF;
END $$;
SQL

# Limita el reporte a mensajes de control, versiones y errores sin valores de filas.
# La transaccion revierte incluso si falla una comprobacion al final.
PGCLIENTENCODING=UTF8 PGOPTIONS='-c client_min_messages=warning' psql -X -q --no-password \
  --host=/var/run/postgresql --username=vitalia_restore --dbname=vitalia_restored \
  --set=ON_ERROR_STOP=1 --set=VERBOSITY=terse --single-transaction --file="$plan"

echo "ENSAYO DE MIGRACIONES 012-032 APROBADO"
echo "Migraciones en copia: 33. Historial 012 legado y 012 de perfiles preservados."
echo "Cuentas, sesiones, documentos y auditoria: filas historicas verificadas."
echo "Migraciones 033-037: NO ejecutadas."
