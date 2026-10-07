import { Pool } from 'pg';
import { type DatabaseConfig } from './config';

// Reutiliza conexiones con límites de cantidad y tiempo.
export function createDatabasePool(config: DatabaseConfig): Pool {
  const pool = new Pool({
    ...config,
    max: 5,
    connectionTimeoutMillis: 3000,
    idleTimeoutMillis: 10000,
    query_timeout: 5000,
    statement_timeout: 5000,
    ssl: false, // Loopback o red interna Docker; un despliegue remoto requiere TLS.
  });
  pool.on('error', () => {
    console.error('Se perdió una conexión inactiva con PostgreSQL.');
  });
  return pool;
}
