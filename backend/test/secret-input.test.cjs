const {PassThrough}=require('node:stream');
const {readSecret,SecretInputError}=require('../dist/cli/secret-input');
function tty(){
 const input=new PassThrough();input.isTTY=true;input.isRaw=false;
 input.setRawMode=jest.fn(value=>{input.isRaw=value;});
 const output={isTTY:true,write:jest.fn()};
 return {input,output};
}
test('no imprime secreto y restaura terminal y listeners al terminar',async()=>{
 const {input,output}=tty();const reading=readSecret('Clave: ',input,output);
 input.emit('keypress','secretoñ',{});input.emit('keypress',undefined,{name:'backspace'});
 input.emit('keypress','\r',{name:'return'});
 expect(await reading).toBe('secreto');expect(output.write.mock.calls.flat().join('')).toBe('Clave: \n');
 expect(input.isRaw).toBe(false);expect(input.isPaused()).toBe(true);expect(input.listenerCount('keypress')).toBe(0);
 input.destroy();
});
test.each(['c','d'])('cancelación Ctrl+%s no devuelve contraseña',async name=>{
 const {input,output}=tty();const reading=readSecret('Clave: ',input,output);
 input.emit('keypress','no imprimir',{});input.emit('keypress',undefined,{ctrl:true,name});
 await expect(reading).rejects.toBeInstanceOf(SecretInputError);expect(input.isRaw).toBe(false);expect(output.write.mock.calls.flat().join('')).not.toContain('no imprimir');input.destroy();
});
test('entrada redirigida se rechaza antes de leer',async()=>{
 const {input,output}=tty();input.isTTY=false;
 await expect(readSecret('Clave: ',input,output)).rejects.toBeInstanceOf(SecretInputError);expect(output.write).not.toHaveBeenCalled();input.destroy();
});
test('límite técnico y error de stream restauran terminal',async()=>{
 for(const cause of ['limit','stream']){
  const {input,output}=tty();const reading=readSecret('Clave: ',input,output);
  if(cause==='limit')input.emit('keypress','a'.repeat(1025),{});else input.emit('error',new Error('error interno'));
  await expect(reading).rejects.toBeInstanceOf(SecretInputError);expect(input.isRaw).toBe(false);input.destroy();
 }
});
