-- Inventario del esquema implementado. No consulta registros de pacientes.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_pretty(jsonb_build_object(
  'database', current_database(),
  'captured_at', CURRENT_TIMESTAMP,
  'tables', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'schema', n.nspname,
      'name', c.relname,
      'comment', obj_description(c.oid, 'pg_class'),
      'columns', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'position', a.attnum, 'name', a.attname,
          'type', format_type(a.atttypid, a.atttypmod),
          'nullable', NOT a.attnotnull,
          'default', pg_get_expr(d.adbin, d.adrelid),
          'identity', a.attidentity, 'generated', a.attgenerated,
          'comment', col_description(c.oid, a.attnum)
        ) ORDER BY a.attnum)
        FROM pg_attribute a
        LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
      ), '[]'::jsonb),
      'constraints', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'name', k.conname,
          'kind', CASE k.contype WHEN 'p' THEN 'primary_key'
            WHEN 'f' THEN 'foreign_key' WHEN 'u' THEN 'unique'
            WHEN 'c' THEN 'check' WHEN 'x' THEN 'exclusion'
            ELSE k.contype::text END,
          'definition', pg_get_constraintdef(k.oid, true),
          'columns', COALESCE((
            SELECT jsonb_agg(a.attname ORDER BY x.ord)
            FROM unnest(k.conkey) WITH ORDINALITY x(num, ord)
            JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=x.num
          ), '[]'::jsonb),
          'referenced_schema', rn.nspname,
          'referenced_table', rc.relname,
          'referenced_columns', COALESCE((
            SELECT jsonb_agg(a.attname ORDER BY x.ord)
            FROM unnest(k.confkey) WITH ORDINALITY x(num, ord)
            JOIN pg_attribute a ON a.attrelid=k.confrelid AND a.attnum=x.num
          ), '[]'::jsonb)
        ) ORDER BY k.conname)
        FROM pg_constraint k
        LEFT JOIN pg_class rc ON rc.oid=k.confrelid
        LEFT JOIN pg_namespace rn ON rn.oid=rc.relnamespace
        WHERE k.conrelid=c.oid
      ), '[]'::jsonb),
      'indexes', COALESCE((
        SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid)
        FROM pg_index i WHERE i.indrelid=c.oid
      ), '[]'::jsonb)
    ) ORDER BY n.nspname, c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN ('r','p')
  ), '[]'::jsonb)
)) AS schema_inventory;
COMMIT;
