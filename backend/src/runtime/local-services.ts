// Destinos fijos: no se acepta una URL arbitraria desde el cliente o el entorno.
export function ollamaUrl(path:'chat'|'tags',env:NodeJS.ProcessEnv=process.env){
 const container=env.VITALIA_RUNTIME==='container';
 const service=env.VITALIA_OLLAMA_SERVICE??(container?'ollama':'loopback');
 if(!['loopback',...(container?['ollama','host']:[])].includes(service))throw new Error('Destino local de IA inválido.');
 const host=service==='ollama'?'ollama':service==='host'?'host.docker.internal':'127.0.0.1';
 return `http://${host}:11434/api/${path}`;
}
