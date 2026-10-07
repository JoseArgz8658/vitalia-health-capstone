const {createPrivilegedAccount,parsePrivilegedArguments,PrivilegedInputError}=require('../dist/accounts/privileged');
const {DuplicateEmailError}=require('../dist/accounts/repository');
const {verifyPassword}=require('../dist/auth/password');
const {createCredentialAuthenticator}=require('../dist/auth/credentials');
const password='Clave ficticia larga 2026';
const id='11111111-1111-4111-8111-111111111111';
function database(){
 let row;
 return {query:jest.fn(async(sql,args)=>{
  if(sql.startsWith('INSERT')){
   row={id:args[0],email:args[1],password_hash:args[2],role_code:args[3],created_at:new Date()};
   return {rows:[row]};
  }
  return {rows:row?[row]:[]};
 })};
}
test.each(['administrador','profesional'])('crea %s con hash real y permite autenticación',async role=>{
 const db=database();
 const result=await createPrivilegedAccount(db,{email:'  Prueba@EXAMPLE.com ',role,password,confirmation:password});
 expect(result.role).toBe(role);expect(result.email).toBe('prueba@example.com');expect(result.passwordHash).toBeUndefined();
 const [sql,args]=db.query.mock.calls[0];expect(sql).not.toContain(password);expect(sql).not.toContain('UPDATE');
 expect(args[2]).toMatch(/^scrypt-v1\$/);expect(await verifyPassword(password,args[2])).toBe(true);
 const login=await createCredentialAuthenticator(db);
 expect((await login({email:'prueba@example.com',password})).role).toBe(role);
 expect(await login({email:'prueba@example.com',password:'incorrecta'})).toBeNull();
});
test.each([
 {role:'paciente'}, {role:'medico'}, {email:'inválido'}, {password:'corta',confirmation:'corta'},
 {confirmation:'no coincide'}, {extra:'campo'}, {password:'a'.repeat(1025),confirmation:'a'.repeat(1025)},
])('entrada inválida no accede a DB %j',async overrides=>{
 const db=database();await expect(createPrivilegedAccount(db,{email:'test@example.com',role:'administrador',password,confirmation:password,...overrides})).rejects.toBeInstanceOf(PrivilegedInputError);
 expect(db.query).not.toHaveBeenCalled();
});
test('correo duplicado no cambia rol ni contraseña existente',async()=>{
 const query=jest.fn().mockRejectedValue({code:'23505',constraint:'vitalia_accounts_email_key'});
 await expect(createPrivilegedAccount({query},{email:'test@example.com',role:'administrador',password,confirmation:password})).rejects.toBeInstanceOf(DuplicateEmailError);
 expect(query).toHaveBeenCalledTimes(1);expect(query.mock.calls[0][0]).not.toMatch(/UPDATE|ON CONFLICT/);
});
test('fallo de DB no se acepta como creación',async()=>{
 const db={query:jest.fn().mockResolvedValue({rows:[]})};
 await expect(createPrivilegedAccount(db,{email:'test@example.com',role:'profesional',password,confirmation:password})).rejects.toThrow();
});
test('argumentos permiten solo rol y correo, nunca contraseña',()=>{
 expect(parsePrivilegedArguments(['--role','profesional','--email',' PRUEBA@example.com '])).toEqual({role:'profesional',email:'prueba@example.com'});
 for(const args of [[],['--role','paciente','--email','p@example.com'],['--role','administrador','--email','p@example.com','--password',password]])expect(()=>parsePrivilegedArguments(args)).toThrow(PrivilegedInputError);
});
