param([ValidateSet('Docker','Local')][string]$Modo='Docker')
$ErrorActionPreference='Stop'
$raiz=Split-Path $PSScriptRoot -Parent
$destino=if($Modo -eq 'Docker'){Join-Path $raiz '.env'}else{Join-Path $raiz 'backend/.env'}
if(Test-Path $destino){throw 'La configuración ya existe. No se reemplaza; revísala en tu editor.'}
function Texto([string]$pregunta){return Read-Host $pregunta}
function Secreto([string]$pregunta){
 $valor=Read-Host $pregunta -AsSecureString
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($valor)
 try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}
$region=Texto 'Región del bucket S3 (por ejemplo us-east-2)'
$bucket=Texto 'Nombre del bucket S3 privado de pruebas'
$access=Texto 'AWS Access Key ID de tu acceso autorizado para ese bucket'
$secret=Secreto 'AWS Secret Access Key (no se muestra)'
$token=Secreto 'AWS Session Token si usas credenciales temporales; si no, presiona Enter'
if(!$region -or !$bucket -or !$access -or !$secret){throw 'Faltan datos de AWS. No se creó configuración.'}
if($Modo -eq 'Docker'){
 $bytes=New-Object byte[] 32
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $password=([BitConverter]::ToString($bytes)).Replace('-','').ToLower()
 $user='vitalia';$database='vitalia';$hostPg='postgres';$runtime='container';$hostApi='0.0.0.0'
}else{
 $database=Texto 'Nombre de tu base PostgreSQL existente'
 $user=Texto 'Usuario PostgreSQL con permisos de migración'
 $password=Secreto 'Contraseña PostgreSQL'
 $hostPg='127.0.0.1';$runtime='local';$hostApi='127.0.0.1'
 if(!$database -or !$user -or !$password){throw 'Faltan datos de PostgreSQL.'}
}
$valores=[ordered]@{VITALIA_RUNTIME=$runtime;PGHOST=$hostPg;PGPORT='5432';PGDATABASE=$database;PGUSER=$user;PGPASSWORD=$password;HOST=$hostApi;PORT='3000';AWS_REGION=$region;S3_BUCKET=$bucket;AWS_ACCESS_KEY_ID=$access;AWS_SECRET_ACCESS_KEY=$secret}
if($token){$valores['AWS_SESSION_TOKEN']=$token}
$lineas=foreach($clave in $valores.Keys){
 $valor=[string]$valores[$clave]
 if($valor -match "['\r\n]"){throw 'Los valores no pueden contener saltos de línea ni comillas simples.'}
 "$clave='$valor'"
}
[IO.File]::WriteAllLines($destino,[string[]]$lineas,(New-Object Text.UTF8Encoding($false)))
$secret='';$token='';$password=''
Write-Host 'Configuración local creada. No la subas al repositorio ni la compartas.'
