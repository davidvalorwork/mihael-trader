# mihael-trader

Asistente de trading con IA (RAG + análisis técnico) que se conecta a **Telegram** para alertas/confirmaciones y ejecuta operaciones a través del **MCP oficial de Robinhood Agentic Trading**. Pensado para instalarse y correr localmente en una sola PC, para un único usuario.

> **Estado del proyecto: fase de investigación/planeación.** Todavía no hay código de la aplicación — este repo por ahora contiene la investigación técnica completa que sustenta las decisiones de arquitectura, para tenerla lista cuando se instale en la PC de destino.
>
> 👉 Ver [`INVESTIGACION.md`](./INVESTIGACION.md) para el detalle completo (arquitecturas RAG de referencia, análisis técnico, elección de LLM, integración con Telegram, y todo lo relacionado a Robinhood: MCP oficial, stop-loss, cierre de posiciones, copytrading, y el escenario específico de este proyecto).

## Qué queremos lograr

Un sistema que:

1. **Analiza mercado con un pipeline RAG + análisis técnico**: combina recuperación híbrida sobre noticias/filings/sentimiento con indicadores técnicos (RSI, MACD, etc.) calculados de forma determinística — nunca por el LLM — siguiendo el patrón de frameworks como [TradingAgents](https://github.com/TauricResearch/TradingAgents).
2. **Nunca ejecuta una orden sin aprobación humana.** Cada señal generada por el sistema se envía como alerta a Telegram con botones de Aprobar/Rechazar; solo tras la confirmación explícita se llama al broker.
3. **Ejecuta a través de Robinhood** usando su servidor MCP oficial de trading agéntico (`agent.robinhood.com/mcp/trading`, OAuth, operando siempre dentro de una sub-cuenta "Agentic" aislada, nunca en el portafolio principal).
4. **Corre localmente**, en la PC personal del usuario final (Windows), conectado a su propio bot de Telegram (uso personal, un solo usuario, sin cobro) — no es un servicio multiusuario ni una app en la nube.

## Por qué está diseñado así (resumen — ver INVESTIGACION.md para el detalle)

- **El LLM nunca calcula números.** Indicadores técnicos, precios, posiciones y saldos siempre vienen de una herramienta determinística; el LLM solo interpreta el resultado ya calculado. Esto elimina el riesgo de que el modelo "invente" un valor.
- **Se ejecuta en la PC del usuario, no en la nube**, porque el OAuth de Robinhood hoy solo soporta redirecciones `localhost` — correr todo localmente hace que ese flujo funcione de forma nativa, sin workarounds.
- **Telegram en modo *long polling*, no webhook**, porque una PC personal no tiene una URL pública a la que Telegram pueda enviarle mensajes.
- **Sin cobro, un solo usuario de confianza.** El sistema está pensado para uso personal informal (no un producto/servicio para terceros) — ver la sección 6 de la investigación sobre las implicaciones legales de este límite y por qué no debe convertirse en un servicio multiusuario o remunerado sin volver a evaluar ese ángulo.
- **Nada de esto es asesoría financiera.** Es un proyecto experimental; el capital que se opera con él debe ser dinero que el usuario esté genuinamente dispuesto a arriesgar.

## Stack técnico (planeado)

Ver la sección 8 de [`INVESTIGACION.md`](./INVESTIGACION.md) para la tabla completa con versiones verificadas. En resumen: Node.js/TypeScript, `grammY` (Telegram), `trading-signals` (indicadores técnicos), Claude API + un modelo abierto barato para volumen alto, embeddings `voyage-finance-2`, `pgvector`/Qdrant para RAG, y el MCP oficial de Robinhood para ejecución — todo supervisado en Windows con `pm2` + `WinSW`.

## Requisitos para instalar (cuando el código esté listo)

- PC con Windows con Node.js instalado.
- Cuenta de Robinhood con Agentic Trading habilitado, con fondos depositados en la sub-cuenta Agentic aislada.
- Bot de Telegram propio (token vía [@BotFather](https://t.me/BotFather)) y el `chat_id` del usuario autorizado.
- La autorización OAuth inicial con Robinhood requiere hacerse *en esa misma PC*, con el teléfono del titular de la cuenta a la mano (verificación desde la app de Robinhood).

## Seguridad

- Los tokens (Telegram, OAuth de Robinhood) nunca se commitean — ver `.gitignore`. Se guardan cifrados en disco vía el Administrador de credenciales de Windows.
- Este repo no contiene, y no debe llegar a contener, credenciales reales, tokens, números de cuenta, ni datos personales identificables del usuario final.

## Disclaimer

Este es un proyecto experimental sin garantías. No es asesoría financiera ni de inversión. El uso de este sistema implica riesgo real de pérdida de capital.
