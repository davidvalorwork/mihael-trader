# Instrucciones para Claude en este proyecto

Este archivo es la guía operativa para que Claude (cualquier sesión futura) use las
herramientas de este proyecto de forma segura. Contexto completo en
[`INVESTIGACION.md`](./INVESTIGACION.md) — esto es el resumen ejecutable.

## Qué es este proyecto

Un agente de trading que opera la cuenta de Robinhood de un familiar/amigo (sin
cobro, uso personal, ver INVESTIGACION.md sección 6). El plan es que **Claude
Code sea el agente** — no un bot Node.js separado orquestando llamadas a LLM.

## Arquitectura: todo vive dentro de WSL2, aislado de la PC real

Node.js, Docker (SearXNG, Qdrant), Agent Reach y Claude Code mismo corren
**dentro de una distro WSL2 (Ubuntu)**, en `~/mihael-trader` — no en la
instalación de Windows. `install.ps1` es solo un bootstrap: asegura que WSL2
exista y clona/actualiza el repo ahí dentro; el trabajo real lo hace
[`scripts/wsl-setup.sh`](./scripts/wsl-setup.sh), corriendo en Linux.

**Claude Code debe correr dentro de esa misma distro WSL2** (abrir la distro,
`cd ~/mihael-trader`, correr `claude` ahí) — así todas las herramientas son
comandos nativos (`npm run indicators`, `docker ps`, etc.), sin tener que
envolver cada llamada con `wsl -d Ubuntu -- ...` desde Windows. El
reenvío automático de `localhost` de WSL2 hace que el flujo OAuth de
Robinhood (que necesita un callback `localhost`, ver INVESTIGACION.md 6.2)
funcione igual desde ahí, abriendo el navegador de Windows normalmente.

**No hay ningún LLM/API separado que instalar, mantener ni pagar.** Claude
Code (esta misma sesión, corriendo vía suscripción/CLI) *es* el motor de
razonamiento del sistema — no un enrutador entre Groq/Gemini/OpenRouter, ni
un modelo local vía Ollama. Esas opciones se investigaron en
INVESTIGACION.md secciones 3 y 8 para el escenario de un bot autónomo
separado, pero ya no aplican: aquí el análisis y la decisión los hace
directamente esta sesión de Claude Code.

## Regla no negociable: todo por CLI, nada que dependa de una GUI

Cada pieza de este sistema tiene que ser algo que Claude Code pueda invocar
por línea de comandos (`npm run ...`, `agent-reach ...`, `docker ...`,
`curl ...`) — nunca una app de escritorio o un panel web que haya que operar
a mano. Las únicas excepciones son acciones humanas de una sola vez que
Robinhood/Telegram exigen por diseño y que no se deben automatizar de todos
modos: la autorización OAuth con Robinhood (navegador + teléfono del
titular) y crear el bot con @BotFather. Por eso ya no se instala Docker
Desktop (app de Windows) sino Docker Engine nativo dentro de WSL2, y por eso
no hay Ollama en el stack — todo lo que queda es CLI de punta a punta.

## Regla no negociable: ningún número se inventa

Precios, indicadores técnicos, posiciones, saldos y conteos de órdenes del día
**siempre** vienen de una herramienta determinística — nunca de que Claude
"calcule" o "recuerde" un valor. Ver INVESTIGACION.md sección 2.3.

## Regla no negociable: ninguna orden real sin confirmación humana explícita

Antes de llamar `place_equity_order` (o cualquier acción que mueva dinero
real): explicar al usuario qué se va a hacer y por qué, y esperar una
confirmación explícita. Nunca ejecutar una orden porque "parecía una buena
idea" durante un análisis — el análisis y la ejecución son pasos separados
con un humano en medio. Esa confirmación viene del chat — directamente en
Claude Code hoy, o por Telegram una vez conectado el plugin (ver abajo): usar
la herramienta `send_buttons` con botones tipo "✅ Aprobar" / "❌ Rechazar"
(cada uno con un `value` corto que identifique la orden, p. ej.
`approve:<id>`/`reject:<id>`) — es preferible a pedir una respuesta en texto
libre, porque no hay ambigüedad que interpretar. Un tap llega de vuelta como
mensaje normal de canal: `"Pressed button: approve:<id>"`.

## Herramientas disponibles

Todas viven en `~/mihael-trader` dentro de WSL2. Ejemplos de invocación
asumen que Claude Code ya está corriendo ahí (ver arquitectura arriba).

### Robinhood MCP (`agent.robinhood.com/mcp/trading`, registrado en `.mcp.json`)

**Estado: registrado pero sin autenticar todavía** — la autorización OAuth
inicial necesita hacerse con el titular de la cuenta presente (su login + su
teléfono con la app de Robinhood, ver INVESTIGACION.md sección 6.2/6.5).
Cuando se conecte, aparecerán herramientas como `get_accounts`,
`get_portfolio`, `get_equity_positions`, `get_equity_quotes`,
`get_equity_orders`, `review_equity_order`, `place_equity_order`,
`cancel_equity_order`.

Reglas de uso (INVESTIGACION.md sección 5.1/5.2):
- Todas las operaciones ocurren dentro de la sub-cuenta "Agentic" aislada —
  nunca en el portafolio principal. No hay forma de operar otra cuenta desde
  este MCP; si `get_accounts` muestra otra cuenta, es solo lectura.
- **Antes de `place_equity_order`**: correr `npm run risk-check` (ver abajo)
  con la orden propuesta. Si `approved: false`, no llamar a `place_equity_order`
  — explicar al usuario por qué se bloqueó.
- Llamar `review_equity_order` antes de `place_equity_order` como práctica de
  este proyecto (Robinhood no lo exige a nivel de protocolo — es nuestra
  convención de seguridad, no la suya).
- **Cerrar una posición** = leer la cantidad actual con `get_equity_positions`
  y colocar una orden de venta opuesta por esa cantidad. No existe un tool
  dedicado para esto.
- **Stop-loss**: no confirmado si `place_equity_order` acepta
  `order_type=stop_loss` (sin esquema de parámetros publicado). Probarlo en
  vivo con montos mínimos antes de depender de él. Si no funciona, el
  respaldo es un stop-loss sintético: monitorear `get_equity_quotes` y
  disparar una venta a mercado cuando el precio cruce el umbral.
- **Después de cualquier orden ejecutada exitosamente**: correr
  `npm run log-order` con los datos de la orden (ver abajo) — es el registro
  de auditoría.

### `npm run indicators` — indicadores técnicos deterministicos

```bash
echo '[100, 101, 99.5, ...]' | npm run indicators
# o con velas OHLC completas (para ATR):
echo '[{"close":100,"high":101,"low":99}, ...]' | npm run indicators
# o desde un archivo:
npm run indicators -- --file precios.json
```

Devuelve RSI(14), SMA(20), EMA(20), MACD(12,26,9), Bollinger Bands(20,2), y
ATR(14) si hay high/low en la entrada. Si no hay suficientes datos, devuelve
`null` en ese campo — **nunca un valor inventado**. Usar esto para cualquier
razonamiento sobre indicadores técnicos; no calcularlos mentalmente.

### `npm run risk-check` — gate de riesgo pre-operación

```bash
echo '{"symbol":"AAPL","side":"buy","quantity":1,"estimatedPrice":230}' | npm run risk-check
```

Lee límites de `config/risk-limits.json` (notional máximo por orden, máximo
de órdenes por día, lista blanca de símbolos opcional) y el historial de hoy
en `state/orders-log.json`. Devuelve `{approved, reasons, ...}`. Código de
salida distinto de 0 si `approved: false`. No tiene efectos secundarios — se
puede correr tantas veces como se quiera sin registrar nada.

**Ajustar `config/risk-limits.json` con el usuario antes de operar con dinero
real** — los valores actuales son conservadores por defecto, no están
pensados como los límites finales.

### `npm run log-order` — registro de auditoría post-operación

```bash
echo '{"symbol":"AAPL","side":"buy","quantity":1,"notionalUsd":230.10,"robinhoodOrderId":"..."}' | npm run log-order
```

Correr **solo después** de que el MCP de Robinhood confirme que la orden se
ejecutó. Alimenta el conteo de `risk-check` del día siguiente/mismo día.

### Telegram — plugin oficial `telegram@claude-plugins-official`, no un bot propio

**Este proyecto no tiene su propio bot de Telegram.** Se usa el plugin
oficial de Claude Code (ya disponible en `~/.claude/plugins/marketplaces/
claude-plugins-official/external_plugins/telegram/`), que corre un servidor
MCP (con `bun`) y conecta Telegram **directamente a esta sesión de Claude
Code** — los mensajes entrantes llegan como contexto de la conversación, no
a un proceso separado con comandos hardcodeados.

**Herramientas que expone al asistente**: `reply` (mandar texto/archivos a
un `chat_id`, con threading opcional), `react` (reaccionar con un emoji del
whitelist fijo de Telegram), `edit_message` (editar un mensaje propio previo
— útil para "analizando..." → resultado), y **`send_buttons`** (ver nota
abajo — no viene de fábrica, se agregó para este proyecto).

**`send_buttons` — agregado a mano en `server.ts`, no es parte del plugin oficial.**
El plugin de fábrica no traía tool de botones para uso general (solo tenía
`InlineKeyboard` cableado internamente a su propio flujo de permisos de
Claude Code). Se extendió `server.ts` para exponer un tool genérico:

- `send_buttons({chat_id, text, buttons: [{label, value}, ...], reply_to?})` — manda el mensaje con hasta 8 botones en una fila.
- Un tap llega a esta sesión como un mensaje de canal normal: `content: "Pressed button: <value>"` — no hay un tool de callback separado, se trata igual que cualquier mensaje de texto entrante.
- Mismo nivel de seguridad que los botones de permisos del propio plugin: solo remitentes en `allowFrom` (DM, no grupos) pueden disparar un botón.
- El mensaje se edita después del tap para mostrar qué se eligió (mismo patrón visual que usa el plugin para sus propios botones de permiso).

**⚠️ Riesgo de mantenimiento**: esto vive en
`~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram/server.ts`,
un archivo **global y gestionado por el marketplace de plugins** — no es
parte de este repo. Una futura `/plugin update` de `telegram@claude-plugins-official`
puede sobreescribir este archivo y borrar el cambio. Si `send_buttons` deja
de aparecer en la lista de herramientas, hay que volver a aplicar esta
extensión — el diff está descrito aquí y en INVESTIGACION.md sección 4.5;
consiste en: (1) un nuevo tool `send_buttons` en `ListToolsRequestSchema`,
(2) su handler en `CallToolRequestSchema` (arma un `InlineKeyboard`,
`callback_data` con prefijo `btn:`), y (3) una rama al inicio de
`bot.on('callback_query:data', ...)` que reconoce el prefijo `btn:` y
reenvía el valor como `notifications/claude/channel`.

**Configuración (dentro de una sesión interactiva de `claude`, no se puede
scriptear — son slash commands):**

```
/plugin install telegram@claude-plugins-official
/reload-plugins
/telegram:configure <token de @BotFather>
```
Luego reiniciar la sesión con el flag de canal:
```
claude --channels plugin:telegram@claude-plugins-official
```
Mandarle un mensaje al bot desde Telegram → responde con un código de pareo →
`/telegram:access pair <código>` → y por último, bloquear el acceso:
`/telegram:access policy allowlist` (política por defecto es `pairing`,
pensada solo para capturar IDs, no para quedarse así).

Detalle completo, control de acceso, grupos, y formato de `access.json` en
`~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram/ACCESS.md`.

**Requisito**: `bun` (lo instala `scripts/wsl-setup.sh`) — el servidor MCP
del plugin corre con `bun run`, no con Node.

**Estado**: plugin disponible, sin configurar todavía (falta el token del
bot real y el pareo con el `chat_id` del titular).

### Agent Reach — noticias web y redes sociales

Ya vive en la misma distro WSL2 que todo lo demás (ver arquitectura arriba),
instalado por `scripts/wsl-setup.sh`. Invocar directamente:

```bash
agent-reach doctor
```

Usar para: sentimiento social sobre un ticker, noticias que los feeds
estructurados no cubrieron. Si Twitter/Reddit devuelven error de sesión,
recordar al usuario que corra `agent-reach configure` él mismo (requiere su
cookie/sesión real — no automatizar ese paso).

### Búsqueda web en vivo (SearXNG) — infraestructura lista, sin código todavía

Contenedor Docker en `http://localhost:8888` (accesible tanto desde dentro de
WSL2 como desde Windows). No hay todavía ningún script que lo consulte — para
usarlo hoy, hacer una petición HTTP directa (p. ej.
`curl 'http://localhost:8888/search?q=...&format=json'`) hasta que exista una
herramienta dedicada.

### Vector DB (Qdrant) — infraestructura lista, sin código todavía

Contenedor Docker en `http://localhost:6333`. El pipeline RAG que lo llene y
lo consulte (embeddings, chunking, hybrid search) todavía no está construido.

## Qué está construido vs. pendiente (actualizar esta lista al avanzar)

- [x] Investigación completa (`INVESTIGACION.md`)
- [x] Arquitectura aislada en WSL2: `install.ps1` (bootstrap desde Windows) +
      `scripts/wsl-setup.sh` (instalador real dentro de la distro)
- [x] Indicadores técnicos deterministicos (`scripts/indicators.ts`)
- [x] Gate de riesgo pre-operación (`scripts/risk-check.ts`)
- [x] Log de auditoría post-operación (`scripts/log-order.ts`)
- [x] `install.ps1`/`wsl-setup.sh` instalan `bun` y el CLI de Claude Code dentro de WSL2
- [x] MCP de Robinhood registrado (`.mcp.json`) — **falta autenticar con el titular presente**
- [x] SearXNG y Qdrant corriendo (contenedores) — **falta el código que los use**
- [ ] Pipeline RAG (embeddings BGE-M3 locales, chunking, hybrid search + reranking sobre Qdrant)
- [x] `send_buttons` agregado al plugin de Telegram (fork local, ver advertencia arriba)
- [ ] Configurar el plugin de Telegram de verdad: token real, pareo, `policy allowlist` (pasos en la sección de arriba)
- [ ] Consentimiento por escrito del familiar/amigo (fuera del código, ver INVESTIGACION.md 6.4)
- [ ] Ajustar `config/risk-limits.json` con límites reales acordados
- [ ] Primera autorización OAuth con Robinhood + prueba de `order_type=stop_loss`
