#Requires -Version 5.1
<#
.SYNOPSIS
  Instalador de mihael-trader. Se corre en la PC de destino (Windows) y deja
  lista toda la infraestructura del stack 100% gratuito descrito en
  INVESTIGACION.md sección 8. Es idempotente: correrlo varias veces es seguro,
  cada paso revisa si ya está hecho antes de intentarlo de nuevo.

.PARAMETER SkipDocker
  Omite Docker Desktop, SearXNG y la base de datos vectorial (Qdrant).

.PARAMETER SkipOllama
  Omite el LLM local de respaldo (Ollama), aunque se detecte una GPU NVIDIA.

.PARAMETER WslDistro
  Nombre de la distro de WSL2 donde vive Agent Reach. Por defecto "Ubuntu".

.NOTES
  Lo que este script NO puede automatizar, a propósito:
  - La autorización OAuth con Robinhood (necesita al titular de la cuenta
    presente, con su teléfono — ver CLAUDE.md e INVESTIGACION.md 6.2/6.5).
  - La configuración de cookies/sesión de Twitter y Reddit para Agent Reach
    (necesita la cuenta real de una persona, no se debe automatizar a ciegas).
  - El primer arranque de Docker Desktop (acepta su licencia/GUI una vez).
#>

[CmdletBinding()]
param(
  [string]$WslDistro = "Ubuntu",
  [switch]$SkipDocker,
  [switch]$SkipOllama
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Info($msg)  { Write-Host "    $msg" -ForegroundColor Gray }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Test-CommandExists($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# 1. Node.js — necesario para todos los scripts del "core" (indicadores,
#    risk-check, log-order).
# ---------------------------------------------------------------------------
function Install-NodeJs {
  Write-Step "Node.js"
  if (Test-CommandExists "node") {
    Write-Ok "Ya instalado: $(node --version)"
    return
  }
  if (-not (Test-CommandExists "winget")) {
    Write-Warn2 "winget no está disponible — instala Node.js 24 LTS manualmente desde https://nodejs.org y vuelve a correr este script."
    exit 1
  }
  Write-Info "Instalando Node.js LTS via winget..."
  winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
  Write-Warn2 "Si 'node' sigue sin reconocerse después de esto, abre una terminal nueva (PATH no se actualiza en la sesión actual) y vuelve a correr .\install.ps1."
}

# ---------------------------------------------------------------------------
# 2. Dependencias del proyecto (package.json: trading-signals, tsx, etc.)
# ---------------------------------------------------------------------------
function Install-ProjectDependencies {
  Write-Step "Dependencias de mihael-trader (npm install)"
  Push-Location $RepoRoot
  try {
    npm install
    Write-Ok "Dependencias instaladas."
  } finally {
    Pop-Location
  }
}

# ---------------------------------------------------------------------------
# 3. WSL2 + Agent Reach (búsqueda de noticias/redes sociales sin API oficial)
# ---------------------------------------------------------------------------
function Test-Wsl2DistroReady([string]$DistroName) {
  <# Devuelve $true solo si LA DISTRO INDICADA (no cualquier distro — Docker
     Desktop instala su propia distro interna "docker-desktop" que no sirve
     para esto) está instalada y corriendo en version 2. #>
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

function Install-AgentReach([string]$DistroName) {
  Write-Step "Agent Reach dentro de WSL2 ($DistroName)"

  Write-Info "Verificando/instalando Python 3.10+, pip y pipx..."
  Invoke-Wsl $DistroName @'
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

  Write-Info "Instalando Agent Reach (si no está ya instalado)..."
  Invoke-Wsl $DistroName @'
set -e
export PATH="$HOME/.local/bin:$PATH"
if command -v agent-reach >/dev/null 2>&1; then
  echo "agent-reach ya está instalado, se omite."
else
  pipx install agent-reach || pip install --user agent-reach
fi
'@

  Write-Info "Ejecutando el instalador propio de Agent Reach (detecta entorno, instala Node.js/gh CLI/mcporter que le falten)..."
  Invoke-Wsl $DistroName @'
set -e
export PATH="$HOME/.local/bin:$PATH"
agent-reach install --env=auto
'@

  Write-Info "Chequeo de salud (agent-reach doctor)..."
  try {
    Invoke-Wsl $DistroName 'export PATH="$HOME/.local/bin:$PATH"; agent-reach doctor'
  } catch {
    Write-Warn2 "agent-reach doctor devolvió un error — normal si aún no configuraste Twitter/Reddit (ver siguiente paso)."
  }

  Write-Ok "Agent Reach instalado."
  Write-Warn2 "PASO MANUAL PENDIENTE (a propósito, no se automatiza a ciegas):"
  Write-Warn2 "  Twitter/Reddit necesitan la sesión/cookie de una cuenta real. Corre 'wsl -d $DistroName' y luego 'agent-reach configure'."
  Write-Warn2 "  Fuente de verdad si algo cambió: https://raw.githubusercontent.com/Panniantong/agent-reach/main/docs/install.md"
}

# ---------------------------------------------------------------------------
# 4. Docker Desktop + SearXNG (búsqueda web en vivo) + Qdrant (vector DB)
# ---------------------------------------------------------------------------
function Test-DockerRunning {
  if (-not (Test-CommandExists "docker")) { return $false }
  docker info > $null 2>&1
  return ($LASTEXITCODE -eq 0)
}

function Install-DockerDesktop {
  Write-Step "Docker Desktop (para SearXNG y Qdrant, autohospedados y gratis)"
  if (Test-DockerRunning) {
    Write-Ok "Docker ya está instalado y corriendo."
    return $true
  }
  if (Test-CommandExists "docker") {
    Write-Warn2 "Docker está instalado pero el motor no responde — abre Docker Desktop manualmente (primer arranque pide aceptar la licencia una vez) y vuelve a correr .\install.ps1."
    return $false
  }
  if (-not (Test-CommandExists "winget")) {
    Write-Warn2 "winget no disponible — instala Docker Desktop manualmente desde https://www.docker.com/products/docker-desktop/."
    return $false
  }
  Write-Info "Instalando Docker Desktop via winget..."
  winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
  Write-Warn2 "Docker Desktop necesita abrirse una vez a mano (acepta la licencia, activa el backend WSL2 si lo pide) antes de que 'docker' funcione."
  Write-Warn2 "Ábrelo, espera a que diga 'Engine running', y vuelve a correr .\install.ps1 para continuar con SearXNG y Qdrant."
  return $false
}

function Start-DockerContainer {
  param(
    [string]$Name,
    [string]$RunArgs
  )
  $existing = docker ps -a --filter "name=^$Name$" --format "{{.Names}}" 2>$null
  if ($existing -eq $Name) {
    $running = docker ps --filter "name=^$Name$" --format "{{.Names}}" 2>$null
    if ($running -eq $Name) {
      Write-Ok "$Name ya está corriendo."
    } else {
      Write-Info "$Name existe pero está detenido — arrancándolo..."
      docker start $Name | Out-Null
      Write-Ok "$Name arrancado."
    }
    return
  }
  Write-Info "Creando contenedor $Name..."
  Invoke-Expression "docker run -d --name $Name $RunArgs"
  Write-Ok "$Name creado y corriendo."
}

function Install-SearXNG {
  Write-Step "SearXNG (búsqueda web en vivo, autohospedada — INVESTIGACION.md 1.5/8)"
  Start-DockerContainer -Name "mihael-searxng" -RunArgs "-p 8888:8080 -e 'BASE_URL=http://localhost:8888/' searxng/searxng:latest"
  Write-Info "Disponible en http://localhost:8888 — esta es una instalación mínima de un solo contenedor (sin cache Valkey/Redis); suficiente para uso personal."
}

function Install-Qdrant {
  Write-Step "Qdrant (vector DB para el pipeline RAG — autohospedado, INVESTIGACION.md 8)"
  Start-DockerContainer -Name "mihael-qdrant" -RunArgs "-p 6333:6333 -v mihael_qdrant_storage:/qdrant/storage qdrant/qdrant:latest"
  Write-Info "Disponible en http://localhost:6333 — el código del pipeline RAG que lo consuma todavía no está construido (ver CLAUDE.md, sección pendiente)."
}

# ---------------------------------------------------------------------------
# 5. Ollama (LLM local gratis, respaldo si esta PC tiene GPU decente)
# ---------------------------------------------------------------------------
function Test-NvidiaGpu {
  try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -ExpandProperty Name
    return ($gpus -join ", ") -match "NVIDIA"
  } catch {
    return $false
  }
}

function Install-Ollama {
  Write-Step "Ollama (LLM local, respaldo 100% gratis — INVESTIGACION.md 8/8.1)"
  if (-not (Test-NvidiaGpu)) {
    Write-Info "No se detectó GPU NVIDIA — se omite. Sin GPU decente, la inferencia por CPU es demasiado lenta para un debate multi-agente ágil (ver INVESTIGACION.md 8.1)."
    Write-Info "El sistema sigue funcionando con la rotación de niveles gratuitos en la nube (Groq/Gemini/OpenRouter) descrita en la sección 8."
    return
  }
  Write-Ok "GPU NVIDIA detectada."
  if (Test-CommandExists "ollama") {
    Write-Ok "Ollama ya está instalado: $(ollama --version 2>&1)"
  } elseif (Test-CommandExists "winget") {
    Write-Info "Instalando Ollama via winget..."
    winget install --id Ollama.Ollama -e --accept-package-agreements --accept-source-agreements
  } else {
    Write-Warn2 "winget no disponible — instala Ollama manualmente desde https://ollama.com/download y vuelve a correr este script."
    return
  }
  Write-Info "Descargando un modelo pequeño de respaldo (qwen3:8b, ~5GB — ajústalo según cuánta VRAM tenga la tarjeta)..."
  try {
    ollama pull qwen3:8b
    Write-Ok "Modelo listo. Pruébalo con: ollama run qwen3:8b"
  } catch {
    Write-Warn2 "No se pudo descargar qwen3:8b automáticamente — revisa https://ollama.com/library y descarga el que mejor calce con la VRAM disponible."
  }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
Write-Host "=== mihael-trader — instalador ===" -ForegroundColor White

Install-NodeJs
Install-ProjectDependencies

if (-not (Test-Wsl2DistroReady $WslDistro)) {
  Install-Wsl2Distro $WslDistro
}
Install-AgentReach $WslDistro

$dockerReady = $false
if (-not $SkipDocker) {
  $dockerReady = Install-DockerDesktop
  if ($dockerReady) {
    Install-SearXNG
    Install-Qdrant
  }
} else {
  Write-Step "Docker/SearXNG/Qdrant omitidos (-SkipDocker)"
}

if (-not $SkipOllama) {
  Install-Ollama
} else {
  Write-Step "Ollama omitido (-SkipOllama)"
}

Write-Step "Resumen"
Write-Info "Node.js:        $(if (Test-CommandExists 'node') { node --version } else { 'FALTA' })"
Write-Info "Agent Reach:    instalado en WSL2 ($WslDistro) — Twitter/Reddit requieren 'agent-reach configure' manual"
Write-Info "SearXNG:        $(if ($dockerReady) { 'http://localhost:8888' } else { 'pendiente (Docker no estaba listo)' })"
Write-Info "Qdrant:         $(if ($dockerReady) { 'http://localhost:6333' } else { 'pendiente (Docker no estaba listo)' })"
Write-Info "Ollama:         $(if (Test-CommandExists 'ollama') { 'instalado' } else { 'omitido o sin GPU NVIDIA' })"
Write-Warn2 "Robinhood MCP:  pendiente de autorización OAuth — abre Claude Code en esta carpeta y sigue CLAUDE.md."
Write-Host "`nEste instalador crecerá con cada pieza nueva del sistema (bot de Telegram, pipeline RAG, etc.)." -ForegroundColor White
