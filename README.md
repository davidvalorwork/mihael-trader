# mihael-trader

Asistente de trading con IA (RAG + análisis técnico) que se conecta a **Telegram** para alertas/confirmaciones y ejecuta operaciones a través del **MCP oficial de Robinhood Agentic Trading**. Pensado para instalarse y correr aislado dentro de WSL2, para un único usuario.

> **Estado del proyecto: core en construcción.** Ya hay herramientas reales (indicadores técnicos, gate de riesgo, bot de Telegram, instalador) — falta el pipeline RAG y el puente entre el bot y Claude Code.
>
> 👉 Ver [`INVESTIGACION.md`](./INVESTIGACION.md) para el detalle completo de la investigación, y [`CLAUDE.md`](./CLAUDE.md) para la guía operativa de qué hay construido y cómo usarlo.

## Qué queremos lograr

Un sistema que:

1. **Analiza mercado con un pipeline RAG + análisis técnico**: combina recuperación híbrida sobre noticias/filings/sentimiento con indicadores técnicos (RSI, MACD, etc.) calculados de forma determinística — nunca por el LLM — siguiendo el patrón de frameworks como [TradingAgents](https://github.com/TauricResearch/TradingAgents).
2. **Nunca ejecuta una orden sin aprobación humana.** Cada señal generada por el sistema se envía como alerta a Telegram con botones de Aprobar/Rechazar; solo tras la confirmación explícita se llama al broker.
3. **Ejecuta a través de Robinhood** usando su servidor MCP oficial de trading agéntico (`agent.robinhood.com/mcp/trading`, OAuth, operando siempre dentro de una sub-cuenta "Agentic" aislada, nunca en el portafolio principal).
4. **Corre aislado dentro de WSL2**, separado de la instalación real de Windows, conectado a su propio bot de Telegram (uso personal, un solo usuario, sin cobro) — no es un servicio multiusuario ni una app en la nube.

## Por qué está diseñado así (resumen — ver INVESTIGACION.md para el detalle)

- **El LLM nunca calcula números.** Indicadores técnicos, precios, posiciones y saldos siempre vienen de una herramienta determinística; el LLM solo interpreta el resultado ya calculado. Esto elimina el riesgo de que el modelo "invente" un valor.
- **Todo vive dentro de WSL2, aislado de la PC real.** Node.js, Docker, Agent Reach y el bot de Telegram corren en una distro Linux separada de Windows — no en el sistema operativo con el que el usuario final hace su vida diaria. También resuelve de forma nativa el callback `localhost` que necesita el OAuth de Robinhood.
- **Telegram en modo *long polling*, no webhook** — no necesita URL pública, funciona igual dentro de WSL2.
- **Sin cobro, un solo usuario de confianza.** El sistema está pensado para uso personal informal (no un producto/servicio para terceros) — ver la sección 6 de la investigación sobre las implicaciones legales de este límite y por qué no debe convertirse en un servicio multiusuario o remunerado sin volver a evaluar ese ángulo.
- **Nada de esto es asesoría financiera.** Es un proyecto experimental; el capital que se opera con él debe ser dinero que el usuario esté genuinamente dispuesto a arriesgar.

## Stack técnico (versión 100% gratuita)

Ver la sección 8 de [`INVESTIGACION.md`](./INVESTIGACION.md) para la tabla completa con versiones verificadas. En resumen: Node.js/TypeScript, `grammY` (Telegram), `trading-signals` (indicadores técnicos), LLM vía niveles gratuitos (Groq/Gemini/OpenRouter, con Ollama local como respaldo si hay GPU), embeddings BGE-M3 locales, Qdrant autohospedado, SearXNG autohospedado para búsqueda web, [Agent Reach](https://github.com/Panniantong/agent-reach) para sentimiento social/noticias sin APIs oficiales, y el MCP oficial de Robinhood para ejecución — **todo corriendo dentro de WSL2**.

## Instalador

En la PC de destino (Windows), en PowerShell:

```powershell
.\install.ps1
```

Es un **bootstrap**: en Windows solo se asegura de que WSL2 exista, y clona/actualiza el repo real dentro de la distro (`~/mihael-trader`). El trabajo real lo hace [`scripts/wsl-setup.sh`](./scripts/wsl-setup.sh), corriendo dentro de WSL2 — instala Node.js, las dependencias del proyecto, Agent Reach, Docker Engine nativo (no Docker Desktop), SearXNG, Qdrant, Ollama (si hay GPU NVIDIA), y prepara el `.env` del bot de Telegram. Es idempotente: correrlo varias veces es seguro.

**Por qué todo dentro de WSL2 y no en Windows nativo**: Agent Reach está confirmado roto en Windows nativo/Git Bash por sus propios scripts internos ([issue #566](https://github.com/Panniantong/agent-reach/issues/566)); en vez de aislar solo esa pieza, todo el sistema vive en la distro Linux — separado de la PC real del usuario, con un único punto de entrada (`wsl -d Ubuntu`).

Pasos manuales que el instalador deja pendientes a propósito (no se automatizan a ciegas):
- **Twitter/Reddit** para Agent Reach necesitan sesión/cookie de una cuenta real — corre `agent-reach configure` dentro de WSL cuando quieras configurarlos.
- **El bot de Telegram** necesita su propio token — habla con [@BotFather](https://t.me/BotFather) y llena `.env` (el instalador te crea la plantilla).
- **La autorización OAuth con Robinhood** necesita al titular de la cuenta presente, con su teléfono.

## Requisitos para instalar

- PC con Windows 10/11 con permisos de administrador (para instalar WSL2 la primera vez).
- Cuenta de Robinhood con Agentic Trading habilitado, con fondos depositados en la sub-cuenta Agentic aislada.
- Bot de Telegram propio (token vía [@BotFather](https://t.me/BotFather)) y el `chat_id` del usuario autorizado.
- La autorización OAuth inicial con Robinhood requiere hacerse *en esa misma PC*, con el teléfono del titular de la cuenta a la mano (verificación desde la app de Robinhood).

## Seguridad

- Los tokens (Telegram, OAuth de Robinhood) nunca se commitean — ver `.gitignore`. `.env` es local y solo vive dentro de WSL2.
- Este repo no contiene, y no debe llegar a contener, credenciales reales, tokens, números de cuenta, ni datos personales identificables del usuario final.

## Disclaimer

Este es un proyecto experimental sin garantías. No es asesoría financiera ni de inversión. El uso de este sistema implica riesgo real de pérdida de capital.
