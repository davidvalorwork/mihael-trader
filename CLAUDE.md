# Instrucciones para Claude en este proyecto

Este archivo es la guía operativa para que Claude (cualquier sesión futura) use las
herramientas de este proyecto de forma segura. Contexto completo en
[`INVESTIGACION.md`](./INVESTIGACION.md) — esto es el resumen ejecutable.

## Qué es este proyecto

Un agente de trading que opera la cuenta de Robinhood de un familiar/amigo (sin
cobro, uso personal, ver INVESTIGACION.md sección 6). El plan es que **Claude
Code sea el agente** — no un bot Node.js separado orquestando llamadas a LLM.

## Arquitectura: todo vive dentro de WSL2, aislado de la PC real

Node.js, Docker (SearXNG, Qdrant), Agent Reach y el bot de Telegram corren
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

## Regla no negociable: ningún número se inventa

Precios, indicadores técnicos, posiciones, saldos y conteos de órdenes del día
**siempre** vienen de una herramienta determinística — nunca de que Claude
"calcule" o "recuerde" un valor. Ver INVESTIGACION.md sección 2.3.

## Regla no negociable: ninguna orden real sin confirmación humana explícita

Antes de llamar `place_equity_order` (o cualquier acción que mueva dinero
real): explicar al usuario qué se va a hacer y por qué, y esperar una
confirmación explícita. Nunca ejecutar una orden porque "parecía una buena
idea" durante un análisis — el análisis y la ejecución son pasos separados
con un humano en medio. El bot de Telegram (ver abajo) ya tiene el patrón de
botones Aprobar/Rechazar construido y probado — pero **todavía no está
conectado a Claude Code**, así que hasta que exista ese puente, la
confirmación viene del chat de Claude Code directamente.

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

### `npm run bot` — bot de Telegram

Bot funcional con grammY en modo *long polling* (sin webhook — no necesita
URL pública, corre bien dentro de WSL2). Lee `TELEGRAM_BOT_TOKEN` y
`TELEGRAM_AUTHORIZED_CHAT_ID` de `.env` (copiar de `.env.example`; el token
lo crea el titular hablando con @BotFather, no se automatiza).

Comandos ya construidos: `/start`, `/status`, y `/testalert` (demuestra el
patrón de botones Aprobar/Rechazar con `InlineKeyboard` — no ejecuta nada
real todavía). Solo procesa updates del `chat_id` en la lista blanca; todo lo
demás se ignora en silencio.

**Lo que falta**: conectar este bot con Claude Code, de modo que una señal
real generada por Claude dispare `sendAlert` con botones, y que aprobar/
rechazar desde Telegram sea lo que finalmente autorice `place_equity_order`.
Hoy son dos piezas separadas que funcionan cada una por su lado.

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

### LLM local de respaldo (Ollama) — opcional, solo si hay GPU NVIDIA visible desde WSL2

`scripts/wsl-setup.sh` lo instala y descarga `qwen3:8b` automáticamente si
detecta la GPU. Sin GPU, se omite — el plan por defecto sigue siendo la
rotación de niveles gratuitos en la nube (Groq/Gemini/OpenRouter,
INVESTIGACION.md 8).

## Qué está construido vs. pendiente (actualizar esta lista al avanzar)

- [x] Investigación completa (`INVESTIGACION.md`)
- [x] Arquitectura aislada en WSL2: `install.ps1` (bootstrap desde Windows) +
      `scripts/wsl-setup.sh` (instalador real dentro de la distro)
- [x] Indicadores técnicos deterministicos (`scripts/indicators.ts`)
- [x] Gate de riesgo pre-operación (`scripts/risk-check.ts`)
- [x] Log de auditoría post-operación (`scripts/log-order.ts`)
- [x] Bot de Telegram funcional (`bot/telegram-bot.ts`) — comandos y botones probados, **sin conectar a Claude Code todavía**
- [x] MCP de Robinhood registrado (`.mcp.json`) — **falta autenticar con el titular presente**
- [x] SearXNG y Qdrant corriendo (contenedores) — **falta el código que los use**
- [ ] Pipeline RAG (embeddings BGE-M3 locales, chunking, hybrid search + reranking sobre Qdrant)
- [ ] Enrutamiento de LLM gratuito (Groq/Gemini/OpenRouter) con reintento/espaciado
- [ ] Puente Claude Code ↔ bot de Telegram (hoy son dos piezas separadas)
- [ ] Consentimiento por escrito del familiar/amigo (fuera del código, ver INVESTIGACION.md 6.4)
- [ ] Ajustar `config/risk-limits.json` con límites reales acordados
- [ ] Primera autorización OAuth con Robinhood + prueba de `order_type=stop_loss`
