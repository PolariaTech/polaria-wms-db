# Aplica migraciones de polaria-wms-db al proyecto Supabase remoto.
# Uso: .\scripts\apply-remote-migrations.ps1
# Requiere: Node/npm, acceso a internet, contraseña de la base de datos.

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot

# Cargar .env si existe (SUPABASE_DB_PASSWORD, SUPABASE_PROJECT_REF)
$envFile = Join-Path $RepoRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($name -and -not [string]::IsNullOrWhiteSpace($value)) {
                Set-Item -Path "env:$name" -Value $value
            }
        }
    }
}

$ProjectRef = if ($env:SUPABASE_PROJECT_REF) { $env:SUPABASE_PROJECT_REF } else { "zmdokvjewvqaftnvulsr" }

Write-Host "Proyecto Supabase: $ProjectRef" -ForegroundColor Cyan
Write-Host ""

if (-not $env:SUPABASE_DB_PASSWORD) {
    $secure = Read-Host "Contraseña de la base de datos (Settings -> Database)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $env:SUPABASE_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

Write-Host "1/3 Login (se abre el navegador si hace falta)..." -ForegroundColor Yellow
npx supabase login

Write-Host "2/3 Enlazar repo con Supabase..." -ForegroundColor Yellow
npx supabase link --project-ref $ProjectRef --password $env:SUPABASE_DB_PASSWORD --yes

Write-Host "3/3 Aplicar migraciones (db push)..." -ForegroundColor Yellow
npx supabase db push --yes

Write-Host ""
Write-Host "Listo. Verifica en Table Editor: rol, empresa, usuario, cuenta" -ForegroundColor Green
Write-Host "SQL: SELECT COUNT(*) FROM rol;  -- esperado: 9" -ForegroundColor Green
