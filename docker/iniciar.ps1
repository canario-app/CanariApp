$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function New-Secret { $b = New-Object byte[] 24; $g = [Security.Cryptography.RandomNumberGenerator]::Create(); $g.GetBytes($b); $g.Dispose(); ([BitConverter]::ToString($b)).Replace('-','').ToLower() }

if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    $bin = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
    if (Test-Path (Join-Path $bin 'docker.exe')) { $env:Path = "$bin;$env:Path" } else { throw 'Docker Desktop no está instalado.' }
}
& docker info --format '{{.ServerVersion}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Abra Docker Desktop, espere "Engine running" y vuelva a ejecutar.' }

if (!(Test-Path '.env')) {
    $admin = New-Secret
    (Get-Content '.env.example') `
        -replace '^POSTGRES_PASSWORD=.*', "POSTGRES_PASSWORD=$(New-Secret)" `
        -replace '^DB_PASSWORD=.*', "DB_PASSWORD=$(New-Secret)" `
        -replace '^JWT_SECRET=.*', "JWT_SECRET=$(New-Secret)$(New-Secret)" `
        -replace '^ADMIN_PASSWORD=.*', "ADMIN_PASSWORD=$admin" | Set-Content '.env' -Encoding ascii
    "CanariApp (Docker)`r`nWeb: http://localhost:8080`r`nAPI: http://localhost:8081/api/health`r`nAdministrador: admin@canariapp.cl`r`nClave: $admin`r`n`r`nLos criadores los crea el administrador en la sección Criadores.`r`nArchivo privado: no subir a GitHub." | Set-Content 'ACCESO_LOCAL.txt' -Encoding utf8
}

& docker compose up -d --build --wait --wait-timeout 300
if ($LASTEXITCODE -ne 0) { throw 'No se pudo iniciar. Revise: docker compose logs --tail 100' }
Write-Host 'CanariApp está funcionando en http://localhost:8080' -ForegroundColor Green
Start-Process 'http://localhost:8080'
if (Test-Path 'ACCESO_LOCAL.txt') { Start-Process notepad.exe 'ACCESO_LOCAL.txt' }
