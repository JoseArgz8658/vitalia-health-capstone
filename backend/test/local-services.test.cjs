const {ollamaUrl}=require('../dist/runtime/local-services');
const {readDatabaseConfig}=require('../dist/database/config');
test('mantiene loopback por defecto y solo permite destinos internos explícitos',()=>{
 expect(ollamaUrl('chat',{})).toBe('http://127.0.0.1:11434/api/chat');
 expect(ollamaUrl('tags',{VITALIA_RUNTIME:'container'})).toBe('http://ollama:11434/api/tags');
 expect(ollamaUrl('chat',{VITALIA_RUNTIME:'container',VITALIA_OLLAMA_SERVICE:'host'})).toBe('http://host.docker.internal:11434/api/chat');
 expect(()=>ollamaUrl('chat',{VITALIA_OLLAMA_SERVICE:'ollama'})).toThrow();
 expect(()=>ollamaUrl('chat',{VITALIA_RUNTIME:'container',VITALIA_OLLAMA_SERVICE:'https://cloud.example'})).toThrow();
});
test('PostgreSQL conserva restricciones locales y acepta postgres solo en contenedores',()=>{
 const base={PGDATABASE:'vitalia',PGUSER:'vitalia',PGPASSWORD:'synthetic'};
 expect(()=>readDatabaseConfig({...base,PGHOST:'postgres'})).toThrow();
 expect(readDatabaseConfig({...base,PGHOST:'postgres',VITALIA_RUNTIME:'container'}).host).toBe('postgres');
 expect(()=>readDatabaseConfig({...base,PGHOST:'remote.example',VITALIA_RUNTIME:'container'})).toThrow();
});
