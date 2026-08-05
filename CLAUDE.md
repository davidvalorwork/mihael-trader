# Instrucciones para Claude en este proyecto

Este archivo es la guía operativa para que Claude (cualquier sesión futura) use las
herramientas de este proyecto de forma segura. Contexto completo en
[`INVESTIGACION.md`](./INVESTIGACION.md) — esto es el resumen ejecutable.

## Qué es este proyecto

Un agente de trading que opera la cuenta de Robinhood de un familiar/amigo (sin
cobro, uso personal, ver INVESTIGACION.md sección 6), corriendo localmente en
su PC (Windows). El plan es que **Claude Code sea el agente** — no un bot
Node.js separado orquestando llamadas a LLM. Telegram se conectará más
adelante como interfaz remota hacia Claude Code (todavía no construido).

## Regla no negociable: ningún número se inventa

Precios, indicadores técnicos, posiciones, saldos y conteos de órdenes del día
**siempre** vienen de una herramienta determinística — nunca de que Claude
"calcule" o "recuerde" un valor. Ver INVESTIGACION.md sección 2.3.

## Regla no negociable: ninguna orden real sin confirmación humana explícita

Antes de llamar `place_equity_order` (o cualquier acción que mueva dinero
real): explicar al usuario qué se va a hacer y por qué, y esperar una
confirmación explícita en el chat. Nunca ejecutar una orden porque "parecía
una buena idea" durante un análisis — el análisis y la ejecución son pasos
separados con un humano en medio. Cuando Telegram esté conectado, la
confirmación vendrá de ahí (botones Aprobar/Rechazar); hasta entonces, viene
del chat de Claude Code directamente.

## Herramientas disponibles

### Robinhood MCP (`agent.robinhood.com/mcp/trading`, registrado en `.mcp.json`)

**Estado: registrado pero sin autenticar todavía** — la autorización OAuth
inicial necesita hacerse en la PC del familiar/amigo, con él presente (su
login + su teléfono con la app de Robinhood, ver INVESTIGACION.md sección
6.2/6.5). Cuando se conecte, aparecerán herramientas como `get_accounts`,
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

### Agent Reach — noticias web y redes sociales (vía WSL2)

Instalado por [`install.ps1`](./install.ps1). Corre dentro de WSL2 (Ubuntu),
no nativo en Windows (ver INVESTIGACION.md sección 8.2). Invocar vía Bash:

```bash
wsl -d Ubuntu -- bash -lc 'export PATH="$HOME/.local/bin:$PATH"; agent-reach doctor'
```

Usar para: sentimiento social sobre un ticker, noticias que los feeds
estructurados no cubrieron. Si Twitter/Reddit devuelven error de sesión,
recordar al usuario que corra `agent-reach configure` él mismo dentro de WSL
(requiere su cookie/sesión real — no automatizar ese paso).

### Búsqueda web en vivo (SearXNG) — pendiente de instalar

Todavía no está en `install.ps1`. Cuando se agregue: autohospedado vía Docker,
gratis, sin límite de peticiones (INVESTIGACION.md sección 1.5/8).

## Qué está construido vs. pendiente (actualizar esta lista al avanzar)

- [x] Investigación completa (`INVESTIGACION.md`)
- [x] Instalador base + Agent Reach vía WSL2 (`install.ps1`)
- [x] Indicadores técnicos deterministicos (`scripts/indicators.ts`)
- [x] Gate de riesgo pre-operación (`scripts/risk-check.ts`)
- [x] Log de auditoría post-operación (`scripts/log-order.ts`)
- [x] MCP de Robinhood registrado (`.mcp.json`) — **falta autenticar en la PC del familiar/amigo**
- [ ] SearXNG autohospedado (búsqueda web en vivo)
- [ ] Pipeline RAG (embeddings BGE-M3 locales, pgvector/Qdrant, reranking)
- [ ] Puente Claude Code ↔ Telegram (el usuario lo conecta más adelante)
- [ ] Consentimiento por escrito del familiar/amigo (fuera del código, ver INVESTIGACION.md 6.4)
- [ ] Ajustar `config/risk-limits.json` con límites reales acordados
- [ ] Primera autorización OAuth con Robinhood en su PC + prueba de `order_type=stop_loss`
