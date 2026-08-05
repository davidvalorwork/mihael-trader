#Requires -Version 5.1
<#
.SYNOPSIS
  Instalador de mihael-trader. Se ejecuta en la PC de destino (Windows) y va
  creciendo con cada pieza del sistema a medida que se construye.

.NOTES
  Pieza actual: Agent Reach (busquedas de noticias web y redes sociales, sin
  necesitar las APIs oficiales de Twitter/Reddit).

  Por que WSL2 y no Windows nativo para Agent Reach:
  Agent Reach depende internamente de scripts bash (transcribe.sh, etc.) con
  supuestos POSIX (usa `bc`, rutas estilo Unix). Confirmado roto en Windows
  nativo / Git Bash en un issue abierto el 4-ago-2026:
  https://github.com/Panniantong/agent-reach/issues/566
  Por eso esta pieza se instala dentro de WSL2 (Ubuntu), no en PowerShell/CMD
  directamente. El resto del sistema (bot de Telegram, MCP de Robinhood, etc.)
  sigue corriendo nativo en Windows - solo Agent Reach vive en WSL2.
#>

[CmdletBinding()]
param(
  [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }

function Test-Wsl2Ready {
  <# Devuelve $true si hay al menos una distro WSL instalada corriendo en version 2. #>
  try {
    $raw = wsl --list --verbose 2>$null
  } catch {
    return $false
  }
  if (-not $raw) { return $false }
  # wsl --list --verbose imprime UTF-16 con espacios raros; normalizamos.
  $lines = $raw | Where-Object { $_ -match '\S' } | ForEach-Object { $_ -replace "`0", "" }
  foreach ($line in $lines) {
    if ($line -match '^\s*\*?\s*(\S+)\s+\S+\s+2\s*$') {
      return $true
    }
  }
  return $false
}

function Install-Wsl2 {
  Write-Step "WSL2 no esta listo — instalando ($WslDistro)"
  Write-Info "Esto requiere permisos de administrador y normalmente pide reiniciar la PC."
  wsl --install -d $WslDistro
  Write-Warn2 "Reinicia la PC si el comando anterior lo pidio, y vuelve a correr este instalador (.\install.ps1) despues del reinicio."
  Write-Warn2 "La primera vez que abras la distro de WSL te va a pedir crear un usuario/contraseña de Linux (independiente del de Windows) — hazlo antes de re-ejecutar el instalador."
  exit 0
}

function Invoke-Wsl([string]$Command) {
  wsl -d $WslDistro -- bash -lc $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Falló dentro de WSL ($WslDistro): $Command"
  }
}

function Install-AgentReach {
  Write-Step "Instalando y configurando Agent Reach dentro de WSL2 ($WslDistro)"

  Write-Info "Verificando/instalando Python 3.10+, pip y pipx en $WslDistro..."
  Invoke-Wsl @'
set -e
if ! command -v python3 >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y python3 python3-pip python3-venv
fi
PYVER=$(python3 -c "import sys; print(sys.version_info[:2] >= (3,10))")
if [ "$PYVER" != "True" ]; then
  echo "Python 3.10+ no disponible via 'python3' por defecto en esta distro — instala una version mas nueva (p.ej. deadsnakes PPA) antes de continuar." >&2
  exit 1
fi
if ! command -v pipx >/dev/null 2>&1; then
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath
fi
'@
  Write-Ok "Python/pipx listos."

  Write-Info "Instalando Agent Reach..."
  Invoke-Wsl @'
set -e
export PATH="$HOME/.local/bin:$PATH"
if command -v agent-reach >/dev/null 2>&1; then
  echo "agent-reach ya está instalado, se omite la instalación inicial."
else
  pipx install agent-reach || pip install --user agent-reach
fi
'@

  Write-Info "Ejecutando el instalador propio de Agent Reach (detecta entorno, instala Node.js/gh CLI/mcporter que le falten)..."
  Invoke-Wsl @'
set -e
export PATH="$HOME/.local/bin:$PATH"
agent-reach install --env=auto
'@

  Write-Info "Chequeo de salud (agent-reach doctor)..."
  try {
    Invoke-Wsl 'export PATH="$HOME/.local/bin:$PATH"; agent-reach doctor'
  } catch {
    Write-Warn2 "agent-reach doctor devolvió un error — normal si aún no configuraste Twitter/Reddit (ver siguiente paso). Revisa la salida arriba."
  }

  Write-Ok "Agent Reach instalado."
  Write-Warn2 "PASO MANUAL PENDIENTE (no se puede ni se debe automatizar a ciegas):"
  Write-Warn2 "  Twitter/Reddit necesitan la sesión/cookie de una cuenta real para leer contenido sin su API oficial."
  Write-Warn2 "  Para configurarlos: abre WSL ('wsl -d $WslDistro'), corre 'agent-reach configure' y sigue las instrucciones"
  Write-Warn2 "  (exportar cookies con Cookie-Editor desde el navegador, o usar el flujo de OpenCLI con sesión de Chrome)."
  Write-Warn2 "  Si algo del flujo de instalación cambió, la fuente de verdad siempre es:"
  Write-Warn2 "  https://raw.githubusercontent.com/Panniantong/agent-reach/main/docs/install.md"
}

# ---- main ----

Write-Host "=== mihael-trader — instalador ===" -ForegroundColor White

if (-not (Test-Wsl2Ready)) {
  Install-Wsl2
}

Install-AgentReach

Write-Step "Listo por ahora."
Write-Info "Este instalador crecerá con cada pieza nueva del sistema (bot de Telegram, MCP de Robinhood, LLM, RAG, etc.)."
