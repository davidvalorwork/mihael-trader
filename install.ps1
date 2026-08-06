#Requires -Version 5.1
<#
.SYNOPSIS
  Bootstrap de mihael-trader. Corre en Windows pero su unico trabajo es
  asegurar que WSL2 exista y clonar/actualizar el repo real DENTRO de esa
  distro Linux — todo el sistema (Node, Docker, Agent Reach, bot de
  Telegram, contenedores) vive aislado ahi, no en la instalacion de Windows.
  El trabajo real lo hace scripts/wsl-setup.sh, corriendo dentro de WSL2.

.PARAMETER WslDistro
  Nombre de la distro de WSL2 donde vive todo el sistema. Por defecto "Ubuntu".

.PARAMETER RepoUrl
  URL del repo a clonar dentro de WSL2. Por defecto el repo publico de este proyecto.

.NOTES
  Este script es intencionalmente autosuficiente: no depende de que el resto
  del repo ya este en Windows. Se puede copiar solo este archivo a la PC de
  destino y correrlo - el clona todo lo demas dentro de WSL2 el mismo.

  Lo que este script NO puede automatizar, a proposito:
  - La autorizacion OAuth con Robinhood (necesita al titular de la cuenta
    presente, con su telefono - ver CLAUDE.md e INVESTIGACION.md 6.2/6.5).
  - Crear el bot de Telegram y obtener su token (via @BotFather - es una
    accion del titular de la cuenta de Telegram, no se automatiza).
  - La configuracion de cookies/sesion de Twitter y Reddit para Agent Reach.
#>

[CmdletBinding()]
param(
  [string]$WslDistro = "Ubuntu",
  [string]$RepoUrl = "https://github.com/davidvalorwork/mihael-trader.git"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg)  { Write-Host "    $msg" -ForegroundColor Gray }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }

function Test-Wsl2DistroReady([string]$DistroName) {
  <# Devuelve $true solo si LA DISTRO INDICADA (no cualquier distro — Docker
     Desktop, si estuviera instalado, trae su propia distro interna
     "docker-desktop" que no sirve para esto) esta instalada y en version 2. #>
  try {
    $raw = wsl --list --verbose 2>$null
  } catch {
    return $false
  }
  if (-not $raw) { return $false }
  $lines = $raw | Where-Object { $_ -match '\S' } | ForEach-Object { $_ -replace "`0", "" }
  foreach ($line in $lines) {
    if ($line -match "^\s*\*?\s*$([regex]::Escape($DistroName))\s+\S+\s+2\s*$") {
      return $true
    }
  }
  return $false
}

function Install-Wsl2Distro([string]$DistroName) {
  Write-Step "WSL2 ($DistroName) no está listo — instalando"
  Write-Info "Esto requiere permisos de administrador y normalmente pide reiniciar la PC."
  wsl --install -d $DistroName
  Write-Warn2 "Reinicia la PC si el comando anterior lo pidió, y vuelve a correr .\install.ps1 después del reinicio."
  Write-Warn2 "La primera vez que abras la distro te va a pedir crear un usuario/contraseña de Linux (independiente del de Windows) — hazlo antes de re-ejecutar el instalador."
  exit 0
}

function Invoke-Wsl([string]$DistroName, [string]$Command) {
  wsl -d $DistroName -- bash -lc $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Falló dentro de WSL ($DistroName): $Command"
  }
}

function Sync-RepoIntoWsl([string]$DistroName, [string]$Url) {
  Write-Step "Clonando/actualizando el repo dentro de WSL2 ($DistroName)"
  Invoke-Wsl $DistroName @"
set -e
if ! command -v git >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y git
fi
if [ -d "`$HOME/mihael-trader/.git" ]; then
  echo 'Repo ya existe — actualizando (git pull)...'
  git -C "`$HOME/mihael-trader" pull --ff-only
else
  echo 'Clonando repo por primera vez...'
  git clone "$Url" "`$HOME/mihael-trader"
fi
"@
  Write-Ok "Repo listo en ~/mihael-trader dentro de WSL2."
}

function Invoke-WslSetupScript([string]$DistroName) {
  Write-Step "Corriendo el instalador real dentro de WSL2 (scripts/wsl-setup.sh)"
  wsl -d $DistroName -- bash -lc 'chmod +x ~/mihael-trader/scripts/wsl-setup.sh && bash ~/mihael-trader/scripts/wsl-setup.sh'
  if ($LASTEXITCODE -ne 0) {
    Write-Warn2 "wsl-setup.sh terminó con avisos/errores — revisa la salida arriba. Puedes volver a correr .\install.ps1 cuando los resuelvas (es seguro repetirlo)."
  }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
Write-Host "=== mihael-trader — bootstrap (Windows -> WSL2) ===" -ForegroundColor White
Write-Info "Todo el sistema real vive dentro de WSL2 ($WslDistro), aislado de esta instalación de Windows."

if (-not (Test-Wsl2DistroReady $WslDistro)) {
  Install-Wsl2Distro $WslDistro
}

Sync-RepoIntoWsl $WslDistro $RepoUrl
Invoke-WslSetupScript $WslDistro

Write-Step "Listo"
Write-Info "Para entrar al sistema: wsl -d $WslDistro, luego 'cd ~/mihael-trader'."
Write-Info "Para correr el bot de Telegram: dentro de WSL, 'npm run bot' (después de llenar .env)."
Write-Warn2 "Robinhood MCP: pendiente de autorización OAuth — abre Claude Code y sigue CLAUDE.md."
Write-Host "`nEste bootstrap crecerá poco — el trabajo real vive en scripts/wsl-setup.sh, dentro de WSL2." -ForegroundColor White
