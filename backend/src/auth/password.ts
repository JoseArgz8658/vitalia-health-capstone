import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const FORMAT = 'scrypt-v1';
const SALT_BYTES = 16;
const KEY_BYTES = 64;
const MAX_PASSWORD_BYTES = 1024;
// Parámetros fijos: el contenido almacenado nunca controla el coste del cálculo.
const OPTIONS = { N: 131072, r: 8, p: 1, maxmem: 192 * 1024 * 1024 };

function validInput(password: string): boolean {
  return typeof password === 'string' && password.length > 0
    && Buffer.byteLength(password, 'utf8') <= MAX_PASSWORD_BYTES;
}

function derive(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, KEY_BYTES, OPTIONS, (error, key) => {
      if (error) { reject(error); return; }
      resolve(key);
    });
  });
}

// Produce un hash con sal aleatoria; no permite recuperar la contraseña.
export async function hashPassword(password: string): Promise<string> {
  if (!validInput(password)) throw new Error('Contraseña fuera del límite técnico permitido.');
  const salt = randomBytes(SALT_BYTES);
  const key = await derive(password, salt);
  return [FORMAT, salt.toString('hex'), key.toString('hex')].join('$');
}

// Una representación inválida o una contraseña distinta no concede acceso.
export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  if (!validInput(password) || typeof storedHash !== 'string') return false;
  const parts = storedHash.split('$');
  if (parts.length !== 3 || parts[0] !== FORMAT
    || !/^[a-f0-9]{32}$/.test(parts[1])
    || !/^[a-f0-9]{128}$/.test(parts[2])) return false;

  const expected = Buffer.from(parts[2], 'hex');
  const actual = await derive(password, Buffer.from(parts[1], 'hex'));
  return timingSafeEqual(actual, expected);
}
