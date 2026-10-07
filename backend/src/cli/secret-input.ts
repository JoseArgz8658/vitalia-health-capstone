import {emitKeypressEvents} from 'node:readline';

export class SecretInputError extends Error {
 constructor(){super('Entrada cancelada o terminal interactiva no disponible.');}
}
// Sin eco ni argumentos de contraseña. Restaurar la terminal incluso al cancelar.
export function readSecret(label:string,input:NodeJS.ReadStream=process.stdin,
 output:Pick<NodeJS.WriteStream,'write'|'isTTY'>=process.stdout):Promise<string>{
 if(!input.isTTY||!output.isTTY||typeof input.setRawMode!=='function')return Promise.reject(new SecretInputError());
 emitKeypressEvents(input);
 return new Promise((resolve,reject)=>{
  let value='';
  const wasRaw=input.isRaw;
  const wasFlowing=input.readableFlowing===true;
  let finished=false;
  const cleanup=()=>{
   input.removeListener('keypress',onKey);
   input.removeListener('error',onError);
   input.removeListener('end',onError);
   input.setRawMode(Boolean(wasRaw));
   if(!wasFlowing)input.pause();
   output.write('\n');
  };
  const finish=(error?:Error)=>{
   if(finished)return;finished=true;
   const secret=value;value='';
   try{cleanup();}catch{reject(new SecretInputError());return;}
   if(error)reject(error);else resolve(secret);
  };
  const onError=()=>finish(new SecretInputError());
  const onKey=(text:string|undefined,key:{name?:string;ctrl?:boolean;meta?:boolean}={})=>{
   if(key.ctrl&&(key.name==='c'||key.name==='d')){onError();return;}
   if(key.name==='return'||key.name==='enter'){finish();return;}
   if(key.name==='backspace'){value=Array.from(value).slice(0,-1).join('');return;}
   if(!text||key.ctrl||key.meta||/[\x00-\x1f\x7f]/.test(text))return;
   if(Buffer.byteLength(value+text,'utf8')>1024){onError();return;}
   value+=text;
  };
  input.on('keypress',onKey);input.once('error',onError);input.once('end',onError);
  try{input.setRawMode(true);output.write(label);input.resume();}catch{onError();}
 });
}
