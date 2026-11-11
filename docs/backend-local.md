# Probar el backend en Windows
## Descargar rama
Desde raíz y con git status limpio:
```powershell
git fetch origin
git switch --track origin/fase-3/base-backend
cd backend
node --version
npm --version
```
Si Node no está instalado, detente e informa; no ejecutes npm con herramientas inexistentes.
Esta base no cambia tu instalación local. Node debe admitir --env-file-if-exists (>=20.19).
## Instalar y comprobar
Primera instalación:
```powershell
npm install
npm run check
npm test
npm run build
npm start
```
Esperado: comprobación TypeScript sin errores, cinco pruebas aprobadas y servidor iniciado.
El comando npm test ya compila; npm run build separado es opcional si tests completaron.
No necesita cuenta externa ni base de datos en esta etapa. No hace falta .env: usa localhost y puerto 3000 por defecto.
Abre http://127.0.0.1:3000/api/health en el navegador. Debe mostrar status ok y service vitalia-api.
No hay interfaces web en este puerto; Flutter sigue ejecutándose aparte.
Detén servidor con Ctrl+C.
## Configuración opcional
Solo si necesitas otro puerto:
Copy-Item .env.example .env
Edita PORT localmente. No sobrescribas .env preexistente.
git check-ignore .env debe mostrar el archivo.
No compartas variables, tokens o registros sensibles.
## Fijar instalación
npm install genera package-lock.json. Revisa git status y guarda únicamente el lock:
git add package-lock.json
git commit -m "chore: fijar dependencias backend"
git push
En otros computadores, con lock versionado, usar npm ci.
No incluir node_modules ni dist. No usar npm audit fix --force automáticamente.
