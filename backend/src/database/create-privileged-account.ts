import {type Pool} from 'pg';
import {createPrivilegedAccount,parsePrivilegedArguments,PrivilegedInputError} from '../accounts/privileged';
import {DuplicateEmailError} from '../accounts/repository';
import {readSecret,SecretInputError} from '../cli/secret-input';
import {readDatabaseConfig} from './config';
import {createDatabasePool} from './pool';
import {checkDatabaseAvailability} from './availability';

async function main(){
 let pool:Pool|undefined;
 try{
  const args=parsePrivilegedArguments(process.argv.slice(2));
  if(!process.stdin.isTTY||!process.stdout.isTTY)throw new SecretInputError();
  pool=createDatabasePool(readDatabaseConfig(process.env));
  await checkDatabaseAvailability(pool);
  console.info(`Creación local de cuenta ${args.role}. No modifica cuentas existentes.`);
  let password=await readSecret('Contraseña (mínimo 12 caracteres; no se muestra): ');
  let confirmation=await readSecret('Repite la contraseña: ');
  try{
   const account=await createPrivilegedAccount(pool,{...args,password,confirmation});
   console.info(JSON.stringify({id:account.id,role:account.role},null,2));
   console.info('Cuenta creada. Inicia sesión en la aplicación con el correo y contraseña elegidos.');
  }finally{password='';confirmation='';}
 }catch(error){
  process.exitCode=1;
  if(error instanceof PrivilegedInputError||error instanceof DuplicateEmailError||error instanceof SecretInputError)console.error(error.message);
  else console.error('No se pudo crear la cuenta. Revisa PostgreSQL, configuración y migraciones.');
  console.error('Uso: node --env-file=.env dist/database/create-privileged-account.js --role administrador|profesional --email CORREO');
 }finally{if(pool)await pool.end().catch(()=>{process.exitCode=1;});}
}
void main();
