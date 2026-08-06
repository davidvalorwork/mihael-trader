#!/usr/bin/env bash
# Instalador real de mihael-trader — corre DENTRO de WSL2 (Ubuntu), nunca en
# Windows directamente. Todo el sistema (Node, Docker, Agent Reach, bot de
# Telegram, contenedores) vive aislado aquí, separado de la PC real. Se
# invoca desde install.ps1 (Windows), pero también se puede correr a mano
# dentro de WSL: bash scripts/wsl-setup.sh
#
# Idempotente: correrlo varias veces es seguro, cada paso revisa su estado
# antes de actuar.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

log_step() { echo -e "\n==> $1"; }
log_info() { echo "    $1"; }
log_warn() { echo "    ⚠ $1"; }
log_ok()   { echo "    ✓ $1"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# 1. Node.js (via NodeSource, system-wide — funciona igual en shells de
#    login y no-login, importante porque install.ps1 lo invoca sin login shell)
# ---------------------------------------------------------------------------
install_nodejs() {
  log_step "Node.js"
  if command_exists node; then
    log_ok "Ya instalado: $(node --version)"
    return 0
  fi
  log_info "Instalando Node.js 24.x LTS via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - || {
    log_warn "No se pudo configurar el repositorio de NodeSource. Instala Node.js manualmente."
    return 1
  }
  sudo apt-get install -y nodejs
  log_ok "Node.js instalado: $(node --version)"
}

# ---------------------------------------------------------------------------
# 2. Dependencias del proyecto
# ---------------------------------------------------------------------------
install_project_dependencies() {
  log_step "Dependencias de mihael-trader (npm install)"
  (cd "$REPO_DIR" && npm install) && log_ok "Dependencias instaladas." || log_warn "npm install falló — revisa el log arriba."
}

# ---------------------------------------------------------------------------
# 3. Agent Reach (noticias/redes sociales sin API oficial)
# ---------------------------------------------------------------------------
install_agent_reach() {
  log_step "Agent Reach"

  if ! command_exists python3; then
    log_info "Instalando Python 3..."
    sudo apt-get update -y && sudo apt-get install -y python3 python3-pip python3-venv
  fi
  if ! python3 -c "import sys; exit(0 if sys.version_info[:2] >= (3,10) else 1)"; then
    log_warn "Python 3.10+ no disponible via 'python3' — instala una version mas nueva (p.ej. deadsnakes PPA) antes de continuar."
    return 1
  fi
  if ! command_exists pipx; then
    python3 -m pip install --user pipx
    python3 -m pipx ensurepath
  fi
  export PATH="$HOME/.local/bin:$PATH"

  if command_exists agent-reach; then
    log_ok "Ya instalado."
  else
    log_info "Instalando Agent Reach..."
    pipx install agent-reach || pip install --user agent-reach
  fi

  log_info "Ejecutando el instalador propio de Agent Reach (detecta entorno, instala Node.js/gh CLI/mcporter que le falten)..."
  agent-reach install --env=auto || log_warn "agent-reach install --env=auto devolvió un error — revisa el log arriba."

  log_info "Chequeo de salud (agent-reach doctor)..."
  agent-reach doctor || log_warn "agent-reach doctor devolvió un error — normal si aún no configuraste Twitter/Reddit."

  log_ok "Agent Reach listo."
  log_warn "PASO MANUAL PENDIENTE (a propósito, no se automatiza a ciegas):"
  log_warn "  Twitter/Reddit necesitan la sesión/cookie de una cuenta real. Corre 'agent-reach configure' cuando quieras configurarlos."
  log_warn "  Fuente de verdad si algo cambió: https://raw.githubusercontent.com/Panniantong/agent-reach/main/docs/install.md"
}

# ---------------------------------------------------------------------------
# 4. Docker Engine NATIVO dentro de WSL2 (no Docker Desktop — todo debe vivir
#    aislado aquí, sin depender de una app instalada en Windows).
# ---------------------------------------------------------------------------
systemd_is_active() {
  [ -d /run/systemd/system ]
}

ensure_systemd_enabled() {
  if systemd_is_active; then
    return 0
  fi
  log_warn "systemd no está activo en esta distro WSL2 — Docker lo necesita para arrancar solo."
  if ! grep -q "^\[boot\]" /etc/wsl.conf 2>/dev/null || ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
    log_info "Agregando systemd=true a /etc/wsl.conf (necesita sudo)..."
    printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf > /dev/null
  fi
  log_warn "Necesario reiniciar WSL para que esto tome efecto:"
  log_warn "  1. Cierra esta terminal."
  log_warn "  2. En PowerShell (Windows): wsl --shutdown"
  log_warn "  3. Vuelve a abrir WSL y corre este script de nuevo (o .\\install.ps1 desde Windows)."
  return 1
}

install_docker_engine() {
  log_step "Docker Engine (nativo en WSL2 — para SearXNG y Qdrant, gratis)"

  if command_exists docker && docker info > /dev/null 2>&1; then
    log_ok "Docker ya está instalado y corriendo."
    return 0
  fi

  if ! ensure_systemd_enabled; then
    return 1
  fi

  if ! command_exists docker; then
    log_info "Instalando Docker Engine (script oficial get.docker.com)..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log_warn "Te agregué al grupo 'docker' — necesitas cerrar y volver a abrir la sesión de WSL para que aplique."
  fi

  sudo systemctl enable --now docker 2>/dev/null || sudo service docker start

  if docker info > /dev/null 2>&1; then
    log_ok "Docker corriendo."
    return 0
  else
    log_warn "Docker se instaló pero el motor no responde todavía. Cierra y reabre WSL, y vuelve a correr este script."
    return 1
  fi
}

start_container() {
  local name="$1" run_args="$2"
  if docker ps -a --filter "name=^${name}\$" --format '{{.Names}}' | grep -q "^${name}\$"; then
    if docker ps --filter "name=^${name}\$" --format '{{.Names}}' | grep -q "^${name}\$"; then
      log_ok "$name ya está corriendo."
    else
      log_info "$name existe pero está detenido — arrancándolo..."
      docker start "$name" > /dev/null
      log_ok "$name arrancado."
    fi
    return 0
  fi
  log_info "Creando contenedor $name..."
  # shellcheck disable=SC2086
  docker run -d --name "$name" $run_args
  log_ok "$name creado y corriendo."
}

install_searxng() {
  log_step "SearXNG (búsqueda web en vivo, autohospedada)"
  start_container "mihael-searxng" "-p 8888:8080 -e BASE_URL=http://localhost:8888/ searxng/searxng:latest"
  log_info "Disponible en http://localhost:8888 (dentro de WSL2 — accesible desde Windows también vía localhost)."
}

install_qdrant() {
  log_step "Qdrant (vector DB para el pipeline RAG, autohospedado)"
  start_container "mihael-qdrant" "-p 6333:6333 -v mihael_qdrant_storage:/qdrant/storage qdrant/qdrant:latest"
  log_info "Disponible en http://localhost:6333"
}

# ---------------------------------------------------------------------------
# 5. Bun — lo exige el plugin oficial de Telegram para Claude Code
#    (~/.claude/plugins/.../telegram corre su servidor MCP con bun, no node).
# ---------------------------------------------------------------------------
install_bun() {
  log_step "Bun (lo necesita el plugin oficial de Telegram para Claude Code)"
  if command_exists bun; then
    log_ok "Ya instalado: $(bun --version)"
    return 0
  fi
  log_info "Instalando Bun..."
  curl -fsSL https://bun.sh/install | bash || {
    log_warn "No se pudo instalar Bun automáticamente — instálalo a mano: https://bun.sh"
    return 1
  }
  log_ok "Bun instalado. Puede que necesites abrir una terminal nueva para que el PATH lo reconozca."
}

# ---------------------------------------------------------------------------
# 6. Claude Code CLI — debe correr DENTRO de esta distro (ver CLAUDE.md)
# ---------------------------------------------------------------------------
install_claude_code() {
  log_step "Claude Code CLI"
  if command_exists claude; then
    log_ok "Ya instalado: $(claude --version 2>&1)"
    return 0
  fi
  log_info "Instalando Claude Code CLI (npm global)..."
  npm install -g @anthropic-ai/claude-code || {
    log_warn "No se pudo instalar automáticamente — instálalo a mano: https://docs.claude.com/en/docs/claude-code"
    return 1
  }
  log_ok "Claude Code instalado."
}

# ---------------------------------------------------------------------------
# 7. Bot de Telegram — vía el plugin oficial de Claude Code, no un bot propio
# ---------------------------------------------------------------------------
remind_telegram_plugin_setup() {
  log_step "Bot de Telegram (plugin oficial de Claude Code)"
  log_info "Este proyecto NO tiene su propio bot — usa el plugin 'telegram@claude-plugins-official'"
  log_info "que ya viene con Claude Code y conecta Telegram directamente a la sesión."
  log_warn "Pasos manuales (dentro de una sesión interactiva de 'claude', ver CLAUDE.md para el detalle):"
  log_warn "  1. Habla con @BotFather en Telegram, /newbot, copia el token."
  log_warn "  2. /plugin install telegram@claude-plugins-official && /reload-plugins"
  log_warn "  3. /telegram:configure <token>"
  log_warn "  4. Reiniciar: claude --channels plugin:telegram@claude-plugins-official"
  log_warn "  5. Mensaje al bot en Telegram -> copia el codigo de pareo -> /telegram:access pair <codigo>"
  log_warn "  6. /telegram:access policy allowlist (para que nadie mas pueda parear)"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
echo "=== mihael-trader — instalador (dentro de WSL2) ==="
echo "Repo: $REPO_DIR"

install_nodejs
install_project_dependencies
install_agent_reach

docker_ready=1
install_docker_engine && docker_ready=0
if [ "$docker_ready" -eq 0 ]; then
  install_searxng
  install_qdrant
fi

install_bun
install_claude_code
remind_telegram_plugin_setup

log_step "Resumen"
log_info "Node.js:      $(command_exists node && node --version || echo FALTA)"
log_info "Claude Code:  $(command_exists claude && echo instalado || echo FALTA)"
log_info "Bun:          $(command_exists bun && bun --version || echo FALTA) (lo necesita el plugin de Telegram)"
log_info "Agent Reach:  $(command_exists agent-reach && echo instalado || echo FALTA) (Twitter/Reddit: correr 'agent-reach configure' manualmente)"
if [ "$docker_ready" -eq 0 ]; then
  log_info "SearXNG:      http://localhost:8888"
  log_info "Qdrant:       http://localhost:6333"
else
  log_info "SearXNG/Qdrant: pendientes (Docker no quedó listo — revisa los avisos arriba)"
fi
log_info "LLM:          Claude Code (ningún LLM/API separado que instalar o mantener)"
log_warn "Bot Telegram: instalar el plugin oficial dentro de una sesión de 'claude' (ver pasos arriba y CLAUDE.md)."
log_warn "Robinhood MCP: pendiente de autorización OAuth — abre Claude Code y sigue CLAUDE.md."
echo -e "\nTodo el sistema vive dentro de esta distro de WSL2 — aislado de la instalación real de Windows."
