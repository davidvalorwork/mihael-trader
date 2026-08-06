# Investigación: Sistema RAG de IA para Trading + Telegram + Robinhood

> Documento de investigación previo a la implementación. Última actualización: 5 de agosto de 2026 (v7 — se añadió análisis técnico, elección LLM por suscripción vs API, detalle de copytrading/stop-loss/cierre de posiciones en Robinhood, el escenario específico de operar la cuenta de un familiar/amigo sin cobro, la decisión de despliegue local en su PC personal con Telegram solo para él, una **pasada de verificación doble** de todas las librerías/repos de GitHub recomendadas, la sección 1.5 sobre **búsqueda web de IA en vivo**, y la sección 8 rehecha como **stack 100% gratuito** — requisito confirmado de que nada de esto debe tener costo).
> Objetivo: determinar el mejor esquema/arquitectura RAG de IA para trading, más reciente disponible, e investigar la integración con Telegram y con el broker Robinhood, antes de escribir código.

---

## 0. Resumen ejecutivo

1. **RAG para trading en 2026 ya no es "vector DB + LLM"**: el patrón dominante es **multi-agente** (analistas especializados por tipo de dato → debate Bull/Bear → gestor de riesgo/portafolio que decide), con **recuperación híbrida** (BM25 + vectores + lookups estructurados) y **re-ranking** obligatorio. El framework más citado y activamente mantenido es **TradingAgents**.
2. **El análisis técnico (RSI, MACD, etc.) no debe calcularlo el LLM.** El patrón que usan todos los frameworks serios (TradingAgents, QuantAgent, AlphaAgents) es: una herramienta determinística calcula el indicador con matemática real (librería, no LLM), y el modelo solo *interpreta* el número ya calculado. Esto elimina el riesgo de que el modelo "invente" un valor de RSI.
3. **Sobre usar tu suscripción de Claude/ChatGPT en vez de API de pago — es viable hoy, pero con riesgo real de política y un problema práctico serio para un bot 24/7.** Anthropic ha cambiado esta política **cinco veces** entre enero y junio de 2026. Hoy (ago-2026) el Claude Agent SDK sí permite autenticar con tu suscripción Pro/Max para apps de terceros, pero: (a) la política puede volver a cambiar sin previo aviso, y (b) el token OAuth de suscripción expira cada 8-12h y su refresco automático falla en procesos desatendidos (cron, servidor 24/7) — la comunidad coincide en que **una API key de pago sigue siendo lo único confiable para un bot que corre sin supervisión humana**. Ver sección 3 para la recomendación híbrida.
4. **Hallazgo más importante sobre el broker**: Robinhood lanzó el **27 de mayo de 2026** un **servidor MCP oficial para trading agéntico** (`agent.robinhood.com/mcp/trading`), pensado explícitamente para agentes tipo Claude. Esto es mucho mejor que depender de librerías no oficiales (`robin_stocks`), que rompen recurrentemente y violan los términos de servicio.
5. **Sobre copytrading, stop-loss y cierre de posiciones (lo que pediste específicamente)**: Robinhood **no ofrece copytrading automatizado** — de forma deliberada, por riesgo regulatorio (ver sección 5.2). El **stop-loss dentro del MCP oficial no está confirmado** en la documentación pública; hay que probarlo en vivo o construir un stop-loss sintético como respaldo. **Cerrar una posición no es una operación dedicada**: se hace leyendo la posición actual y colocando una orden de venta opuesta por esa cantidad. Todo esto se detalla en la sección 5.2.
6. **Tu caso específico (operar la cuenta de tu familiar/amigo, sin cobro)**: al no haber compensación, el detonante clásico de necesitar registrarte como asesor de inversiones (RIA) probablemente no aplica. El problema técnico que sí encontramos — que el OAuth de Robinhood solo soporta redirecciones `localhost`, no callbacks HTTPS alojados — **queda resuelto de forma natural** con tu decisión de instalar el sistema directamente en su PC personal (sección 6.5): al correr todo en su propia máquina, el callback `localhost` es literal, no un workaround. Ya no hace falta que tú sostengas su refresh token en un backend remoto.
7. **Despliegue**: **local, en la PC personal de tu familiar/amigo**, no en la nube/Vercel. Esto cambia el bot de Telegram de modo *webhook* (pensado para serverless) a modo ***long polling*** (no necesita URL pública), y cambia la pregunta de "uptime 24/7" por "depende de que su PC esté encendida" — ver sección 6.5 para el detalle y las implicaciones operativas.
8. **Riesgo legal/operativo**: no hay entorno sandbox/paper-trading en Robinhood. Las pruebas iniciales deberían hacerse con montos mínimos en la sub-cuenta "Agentic" aislada que exige el propio flujo de Robinhood.
9. **Búsqueda web de IA (pregunta que hiciste)**: el diseño original de la sección 1 asumía feeds ya curados (noticias, filings, sentimiento), **no** una herramienta de "buscar en la web ahora mismo". Sí conviene agregarla — ver sección 1.5. La versión **gratuita** de esta pieza específica es **SearXNG autohospedado** (ver punto 10), no la herramienta de pago de Claude.
10. **Confirmaste que todo debe ser gratuito — esto reemplaza casi todas las recomendaciones de pago de este documento.** Rehice la sección 8 (stack tecnológico) entera bajo ese criterio: LLM vía combinación de niveles gratuitos (Groq + Gemini + OpenRouter, con inferencia local como respaldo si su PC tiene GPU — **necesito saber qué GPU tiene**), embeddings y reranking corriendo localmente y gratis (BGE-M3, bge-reranker), vector DB autohospedada en su propia PC (pgvector/Qdrant vía Docker, sin costo de nube), datos de mercado/noticias vía Finnhub + Alpaca (niveles gratuitos) + GDELT, sentimiento social vía **Agent Reach** (el repo que compartiste — lee Twitter/Reddit sin necesitar sus APIs oficiales, que hoy están cerradas o con aprobación de semanas) en vez de las APIs oficiales de Reddit/StockTwits, y búsqueda web vía SearXNG autohospedado en vez de la herramienta de pago de Claude/Tavily. **Es viable, pero más frágil que la versión de pago** — ver sección 8.1 para los límites exactos y qué puede fallar.

---

## 0.1 Nota de verificación (5 de agosto de 2026) — cada dato de esta sección fue confirmado por al menos dos fuentes independientes (repo de GitHub + registro npm/PyPI, o dos búsquedas separadas)

**Correcciones críticas que cambian recomendaciones anteriores de este documento:**

- **`keytar` está confirmado muerto** (archivado por su dueño desde dic-2022, sin nueva versión desde 2022). En cualquier lugar de este documento donde se sugirió `keytar` para guardar el token de Robinhood cifrado en Windows, **reemplazar por `@napi-rs/keyring`** (activo, v1.3.0 abr-2026) — es literalmente el remplazo que está usando el propio SDK de Azure de Microsoft para migrar fuera de keytar.
- **`technicalindicators` (npm) está abandonado** (última versión 2020, último commit 2022) — ya no debe mencionarse como alternativa a `trading-signals`, que sigue muy activo (v8.2.0, 2-ago-2026, cero dependencias).
- **NSSM está congelado desde 2014** (sigue funcionando, pero sin desarrollo activo). **WinSW** (github.com/winsw/winsw) es la alternativa moderna y activamente mantenida (pushed 30-jul-2026) — usarla como primera opción para envolver el proceso como servicio de Windows, con NSSM como respaldo simple si WinSW da problemas.
- **`pm2` no tiene soporte nativo de servicio de Windows** — su wrapper comunitario `pm2-windows-service` está sin mantenimiento desde 2018 y reportado como roto en Windows Server 2022/2025. Usar pm2 solo para supervisión/reinicio del proceso, y WinSW (no pm2 solo) para registrarlo como servicio real de Windows.
- **El paquete Python `pandas-ta` original (no el fork) presenta señales de posible compromiso**: su repositorio ahora devuelve 404, la propiedad cambió de mantenedor, el historial de PyPI fue borrado, y el sitio "pandas-ta.dev" que lo reemplaza es descrito por la comunidad como similar a adware. **No usar el paquete `pandas-ta` original bajo ninguna circunstancia** — usar exclusivamente `pandas-ta-classic` (activamente mantenido, 403★, "Production/Stable"), que ya era la recomendación de este documento.
- **TA-Lib avanzó de v0.6.5 a v0.7.1** (16-jul-2026) — actualizar la referencia de versión si se documenta en el código.
- **El proyecto QuantAgent (sección 1.1/2.2/2.3) se renombró a "QuantHarness"** (nuevo paper: "QuantHarness: Price-Driven Multi-Agent LLMs for High-Frequency Trading", arXiv:2509.09995) — el repo es ahora `Y-Research-SBU/QuantHarness`. La URL antigua redirige por ahora, pero usar el nombre/URL nuevo en cualquier referencia.
- **`robin_stocks` está confirmado estancado**: sin commits en ~6 meses (desde feb-2026), y el lanzamiento del MCP oficial de Robinhood en mayo no reactivó su mantenimiento. La comunidad ya inició un fork (`DhruvaBansal00/robin_stocks_v2`) por frustración con el abandono — si algún día se necesita un fallback no oficial, considerar ese fork antes que el original.
- **Robinhood agregó soporte de cripto a su Agentic Trading MCP el 20 de julio de 2026** — esto actualiza la sección 5.1, que decía "cripto: próximamente, sin fecha". Sigue sin haber esquema de parámetros publicado para `place_equity_order`, así que el soporte de stop-loss sigue sin confirmar (la restricción de OAuth solo-`localhost` también sigue vigente, confirmada de nuevo con una reseña del 8-jul-2026).
- **`robinhood-for-agents` (el wrapper no oficial mencionado en la sección 5.2) está más activo de lo que parecía**: lanzó v2.0.0 el 28-jul-2026 con "renovación proactiva de tokens, recuperación de rotación, verificación honesta de sesión" — mejoras directamente relevantes al problema de operación desatendida, aunque sigue sin resolver la limitación de OAuth `localhost`.

**Lo que se confirmó sin cambios** (sigue siendo la recomendación correcta): grammY (v1.45.1), trading-signals (v8.2.0), TradingAgents (95.7k★, v0.3.1 sigue siendo la última), pgvector (v0.8.6), Qdrant (v1.19.0, lanzado hoy mismo), voyage-finance-2 (sin sucesor específico de finanzas todavía).

---

## 1. Arquitectura RAG para trading con IA (estado del arte 2024–2026)

### 1.1 Frameworks y papers de referencia

| Framework | Enfoque | Notas clave |
|---|---|---|
| **TradingAgents** ([arXiv:2412.20138](https://arxiv.org/abs/2412.20138), [GitHub](https://github.com/TauricResearch/TradingAgents)) | Multi-agente tipo "mesa de trading": analistas (fundamentales, sentimiento, noticias/macro, técnico) → investigadores Bull/Bear que debaten → agente Trader → Risk Manager/Portfolio Manager que aprueba. | El más maduro y activo (v0.3.1, jul-2026). Construido sobre LangGraph. Guarda memoria de decisiones (`trading_memory.md`) que retroalimenta decisiones futuras. Soporta múltiples proveedores de LLM (incluye modelos Claude). **Es la base de arquitectura recomendada para este proyecto.** |
| **MarketSenseAI 2.0** ([arXiv:2502.00415](https://arxiv.org/html/2502.00415v1)) | RAG + "Chain-of-Agents" para documentos largos (10-K/10-Q, transcripciones), más HyDE para contexto macro. | Resultados reportados: 125.9% retorno acumulado S&P100 (2023-24) vs 73.5% del índice. |
| **AlphaAgents** ([arXiv:2508.11152](https://arxiv.org/html/2508.11152v1)) | 3 agentes: Fundamental (RAG sobre filings), Sentimiento (noticias/ratings), Valuación (cálculo puro, **sin RAG** para evitar alucinar números). | Relevante: separan explícitamente "razonamiento con RAG" de "cálculo numérico con herramientas" para no alucinar cifras. |
| **QuantHarness** (antes "QuantAgent" — renombrado, confirmado en verificación del 5-ago-2026; [GitHub](https://github.com/Y-Research-SBU/QuantHarness), arXiv:2509.09995) | IndicatorAgent (RSI/MACD/Stochastic vía TA-Lib) + PatternAgent + TrendAgent → RiskAgent que fusiona todo numéricamente antes de que el LLM narre la conclusión. | Buen ejemplo de "fusión numérica antes del LLM" — ver sección 2.3. 2.8k★, activamente mantenido. |
| **FinMem** ([arXiv:2311.13743](https://arxiv.org/abs/2311.13743)) | Memoria en capas (trabajo → largo plazo, con resumen/observación/reflexión) inspirada en cognición humana. | Precursor del patrón "memoria como recuperación" que reusan los frameworks posteriores. |
| **FinGPT / FinRobot** ([GitHub AI4Finance](https://github.com/AI4Finance-Foundation/FinRobot)) | Plataforma open-source que combina LLMs + RL + analítica cuant. | Buena referencia de código abierto, menos "producto terminado" que TradingAgents. |
| **AMA / Agent Market Arena** ([arXiv:2510.11695](https://arxiv.org/abs/2510.11695)) | Primer benchmark "lifelong" en vivo (cripto + acciones) comparando arquitecturas de agentes sobre distintos LLMs. | **Conclusión clave: la arquitectura del agente importa más que el LLM subyacente** para el desempeño de trading. Esto valida invertir esfuerzo en el diseño del pipeline RAG/agentes antes que en elegir el modelo "más inteligente" (relevante también para la decisión de la sección 3). |

### 1.2 Diseño del pipeline RAG (recomendaciones concretas)

**Fuentes de datos a ingerir:**
- Datos de mercado en tiempo real (OHLCV, order book, ticks)
- Noticias (wires), filings SEC (10-K/10-Q/8-K), transcripciones de earnings calls
- Sentimiento social (Reddit, StockTwits, X)
- Reportes de analistas, datos macro
- Patrón recomendado por TradingAgents/AlphaAgents: **acceso a datos segmentado por rol** — cada agente especialista solo recupera su propia modalidad, en lugar de un contexto compartido gigante.

**Chunking:**
- El chunking por tokens fijos rompe la jerarquía de un 10-K y da mal recall. Mejor: **chunking consciente de estructura** (respetar encabezados de sección XBRL/HTML) — mejor recall medido (0.877) sobre filings reales.
- Receta con mejor relación costo/beneficio (Snowflake Engineering): **chunks de ~1.800 caracteres + metadata/contexto del documento completo prependido a cada chunk**. Esto importa **más que el modelo generador**: con buen chunking, Llama 70B casi igualó a Claude 3.5 Sonnet en QA financiero.
- Nunca partir tablas de estados financieros a la mitad de una tabla.

**Embeddings:**
- **voyage-finance-2** (Voyage AI, afiliado a Anthropic) — especializado en finanzas, contexto de 32K, ~7-12% mejor que alternativas genéricas en benchmarks de recuperación financiera. Es la opción recomendada si se usa el ecosistema Anthropic/Claude.
- Alternativa genérica competitiva: `text-embedding-3-large` (OpenAI) o `voyage-3-large`.
- Benchmark de referencia para evaluar embeddings en este dominio: **FinMTEB**.

**Vector DB — latencia:**
- **Qdrant**: menor latencia medida (p50 ~4ms, p99 ~25ms) — recomendado si la generación de señales pre-operación necesita recuperación en <10ms.
- **Milvus** (con GPU): ~6ms p50, buena opción self-hosted a escala.
- **Pinecone**: gestionado, más simple operativamente, pero mayor techo de latencia (p99 ~30ms en pods p2).
- **pgvector**: atractivo si se quiere colocar la búsqueda vectorial junto a los datos relacionales/series de tiempo existentes (consistencia transaccional), pero generalmente más lento a escala.
- **Recomendación para este proyecto**: empezar con **pgvector** (vía Postgres del Marketplace de Vercel, p. ej. Neon) para simplicidad operativa inicial, y migrar a Qdrant si la latencia de señales pre-operación se vuelve crítica.

**Recuperación híbrida (no opcional):**
- BM25 puro **supera** a la búsqueda vectorial densa en documentos financieros, porque términos exactos (tickers, períodos fiscales, nombres de métricas) importan más que la paráfrasis semántica.
- Patrón mínimo viable: **BM25 + vectores densos, fusionados vía RRF (Reciprocal Rank Fusion)**, más un tercer canal de **lookups estructurados** (consultas directas a base de datos/API para precio y fundamentales — los números NO se vectorizan, se consultan como herramientas).

**Re-ranking:**
- Pipeline en dos etapas (recuperación híbrida → re-ranker neuronal tipo Cohere Rerank) domina claramente sobre recuperación en una sola etapa: Recall@5 de 0.816 vs 0.695 (solo RRF híbrido) vs 0.587 (solo denso). Considerarlo prácticamente obligatorio.

**Cómo alimenta la decisión de trading:**
- Patrón dominante: recuperación → razonamiento por agente especialista (chain-of-thought) → debate multi-agente (Bull/Bear) → síntesis por un agente Trader/Portfolio Manager → capa de Risk Management (idealmente **determinística, no LLM**) que aprueba o bloquea antes de ejecutar.
- El uso de herramientas (precio, volatilidad, colocación de orden) se trata como canal de "grounding" separado del RAG, precisamente para no alucinar cifras numéricas.

### 1.3 RAG en tiempo real / streaming

- RAG estático (reindexado nocturno) se considera una **falla de diseño** para casos de uso financieros en 2026.
- Patrón "Streaming RAG": ingesta, indexado y recuperación continuos e intercalados (ver [StreamingRAG, arXiv:2501.14101](https://arxiv.org/abs/2501.14101)).
- Tendencia 2026: bases de datos streaming con funciones de embedding integradas en la capa de escritura (embedding automático al insertar).
- **Latencia por modo de razonamiento** (survey [arXiv:2605.19337](https://arxiv.org/html/2605.19337v1)):
  - *Reactivo* (<1ms): reglas/redes superficiales — un LLM es demasiado lento aquí.
  - *Reflexivo* (segundos): razonamiento chain-of-thought — es donde vive el RAG con LLM.
  - *Estratégico* (minutos-horas): planificación/búsqueda en árbol.
- **Riesgo crítico a evitar**: *look-ahead bias* / "publication-lag" — el timestamp de una noticia registra cuándo se publicó, no cuándo estuvo realmente disponible. Es una fuente importante de fuga de información en backtests de sistemas basados en recuperación.

### 1.4 Evaluación, backtesting y guardrails

- Backtestear un agente LLM es caro: si cada barra requiere una llamada LLM (~3s), un backtest de 5 años que en forma vectorizada tarda 200ms puede tardar ~5 horas.
- Auditoría de 19 estudios de agentes de trading: solo 2/19 usan splits de datos consistentes en el tiempo, 1/19 documenta costos de transacción, 0/19 es completamente reproducible. **Tomar con escepticismo cualquier cifra de retorno reportada en papers.**
- **"Oracle Fallacy"**: los episodios de memoria recuperados pueden contener narrativas post-hoc sobre resultados que ya ocurrieron, filtrando información futura al contexto de decisión — vigilar esto especialmente si se implementa memoria tipo FinMem.
- Guardrails recomendados: esquemas de herramientas tipados + motor de riesgo determinístico (el LLM no puede "decidir" violar límites de posición); un almacén de estado de solo lectura para el LLM, actualizado solo por el entorno real (para que el modelo no pueda reescribir su propia verdad); registro de auditoría de cada acción aprobada.

### 1.5 Búsqueda web de IA en vivo — ¿el sistema puede "buscar en la web" para encontrar señales?

Esto responde directamente a la pregunta de si el sistema tiene conexión a búsquedas web de IA. **En el diseño original de esta sección (1.2), no** — se asumía ingesta de feeds ya curados (noticias, filings, sentimiento vía APIs fijas). Investigado el 5-ago-2026: sí conviene agregar una herramienta de búsqueda web en vivo, y hay una opción clara.

**Lo que de verdad hace hoy el framework de referencia (TradingAgents), confirmado revisando su código directamente:** su carpeta `dataflows/` solo tiene integraciones fijas — Alpha Vantage, Yahoo Finance (`yfinance`, incluyendo su feed de noticias), Reddit, StockTwits, Polymarket y FRED. **No tiene ninguna herramienta de búsqueda web genérica.** Hay un issue abierto en su GitHub ([#699](https://github.com/TauricResearch/TradingAgents/issues/699)) donde la propia comunidad señala que el "Social Media Analyst" no tiene, en la práctica, ningún dato social real, y que el analista de noticias depende de ~20 artículos de Yahoo Finance — un vacío real que ni el framework de referencia ha cerrado todavía. La solución que propone la comunidad es un SearXNG autohospedado (metabuscador gratuito), no una API comercial de búsqueda con IA — priorizando costo/control por encima de qué tan "en vivo" es.

**Opciones para agregarla a este proyecto:**

| Opción | Costo | Notas |
|---|---|---|
| **Herramienta `web_search` nativa de Claude** (Messages API) | $10 por 1.000 búsquedas + tokens normales del contenido devuelto | **Recomendada como primera opción**: misma cuenta/facturación que ya se usa para los agentes de decisión (Claude API), sin vendor nuevo. Devuelve citas estructuradas (URL, título, antigüedad de la página) — útil para que el agente de Noticias/Sentimiento pueda respaldar cada afirmación con una fuente, algo valioso para auditar después qué "vio" el sistema antes de una operación. |
| Herramienta de búsqueda web de OpenAI (Responses API) | Mismo orden de precio ($10/1.000) | Sin ventaja clara de costo o frescura sobre la de Claude — no aporta nada si no se va a usar OpenAI para otra cosa; agregaría una cuenta/vendor más sin necesidad. |
| **Tavily** (modo `advanced`) | ~$3-8 por 1.000 según volumen | La opción más recomendada específicamente para frescura "del día" en noticias financieras que se mueven rápido — usada por defecto en varios agentes financieros construidos con LangChain/LangGraph. |
| Brave Search API | ~$4-5 por 1.000 | Índice propio, tiene endpoint de "News" pensado para frescura — alternativa válida a Tavily. |
| Exa | ~$7-15 por 1.000 | Explícitamente señalada como la opción **menos adecuada** para frescura de noticias del mismo día — está optimizada para similitud temática/descubrimiento, no para velocidad. |
| Perplexity Sonar API | Más caro (~$14-22/1.000 en modo Pro Search) + tokens | No es una API de búsqueda pura, es un paquete LLM+búsqueda — redundante si Claude ya es la capa de razonamiento del proyecto. |

**Recomendación concreta**: activar la herramienta `web_search` nativa de Claude para el agente de Noticias/Sentimiento desde el inicio — al volumen esperado (unas pocas decenas de búsquedas al día) el costo es prácticamente nulo (~$0.30-1/día), no hay vendor nuevo que gestionar, y las citas vienen listas para auditoría. **El pipeline RAG curado (wires, filings) sigue siendo la fuente de verdad principal**; la búsqueda web se trata como una herramienta *complementaria* que el agente usa para "descubrir lo que los feeds no cubrieron" — igual que TradingAgents está intentando resolver ese mismo vacío con su propia comunidad. Ninguna de estas opciones (ni la de Claude, ni la de OpenAI, ni las de terceros) publica una garantía de latencia para noticias de "hace segundos" — todas son búsqueda web general, no un feed de wire — así que si en pruebas reales se nota que la búsqueda de Claude llega tarde en tickers muy rápidos, agregar Tavily en modo `advanced` como segunda herramienta explícita, en vez de reemplazar todo el enfoque.

---

## 2. Capa de análisis técnico (RSI, MACD, etc.)

### 2.1 Librerías (estado 2025–2026)

- **TA-Lib**: sigue siendo el estándar de referencia. Su histórico problema de instalación (requería compilar la librería C) **se resolvió en 2025** — desde la v0.6.5 (ago-2025) el paquete de Python trae wheels precompiladas, `pip install` funciona sin toolchain aparte en la mayoría de plataformas.
- **pandas-ta (paquete original, `twopirllc/pandas-ta`): NO USAR — señales de posible compromiso, confirmado en verificación del 5-ago-2026.** El repositorio original ahora devuelve 404, la propiedad del proyecto cambió de mantenedor, el historial de PyPI fue borrado, y el sitio que lo reemplaza ("pandas-ta.dev") es descrito por la comunidad como similar a adware. La comunidad ya lo forkeó como **pandas-ta-classic** ([GitHub](https://github.com/xgboosted/pandas-ta-classic), 403★, "Production/Stable", último commit 25-jul-2026) — **usar exclusivamente ese fork**, nunca el paquete original, si se opta por Python.
- **tulipy** y **finta**: explícitamente no mantenidos, evitar.
- **TA-Lib**: v0.7.1 (16-jul-2026) es la versión vigente — sigue con wheels precompiladas.
- **Para el stack TypeScript/Node de este proyecto (PC local con Windows)**: evitar bindings nativos de TA-Lib (requieren compilar C). Usar **exclusivamente [trading-signals](https://github.com/bennycode/trading-signals)** (npm, v8.2.0 confirmada 2-ago-2026, cero dependencias, streaming-first): cada indicador es un objeto con estado que se actualiza con `.update()` en cada tick, ideal para un pipeline de ingesta en tiempo real (ver 2.3). **No usar `technicalindicators`** — verificado como abandonado (última versión npm de 2020, último commit de 2022).

### 2.2 Qué indicadores usan realmente los frameworks de referencia

- **TradingAgents**: el agente "Technical Analyst" usa MACD y RSI, calculados internamente vía la librería `stockstats` (Python), no matemática hecha por el LLM.
- **AlphaAgents**: RSI(14 y 30), MACD (línea/señal/histograma), posición/ancho de Bollinger Bands, KDJ, reversión a la media (ZMR), cruces de SMA.
- **QuantHarness** (antes "QuantAgent"): RSI, MACD y Oscilador Estocástico vía TA-Lib, calculados por un "IndicatorAgent" dedicado.

### 2.3 Patrón de arquitectura: el LLM nunca calcula el indicador

Este es el punto más importante de esta sección, confirmado revisando directamente el código de TradingAgents y QuantHarness:

- En TradingAgents, `market_analyst.py` define herramientas (`get_stock_data`, `get_indicators`, `get_verified_market_snapshot`) que el LLM invoca vía `bind_tools`. El cálculo real ocurre en `stockstats_utils.py` con pandas — **el LLM nunca hace la aritmética**, solo interpreta el resultado ya calculado.
- El prompt del sistema instruye explícitamente al modelo a **señalar discrepancias en lugar de inventar un número reconciliado** si dos fuentes no coinciden.
- QuantHarness replica el patrón: su "RiskAgent" integra numéricamente las salidas de Indicator + Pattern + Trend **antes** de que cualquier LLM genere la narrativa final.
- Esto reduce directamente el riesgo de alucinación de cifras — atarlo como regla de diseño no negociable para este proyecto: **cualquier número (precio, indicador, posición, saldo) siempre viene de una herramienta/consulta determinística, nunca de la generación del LLM.**

### 2.4 Cómputo en tiempo real / incremental

- Recalcular el indicador completo en cada tick desde el historial completo es simple pero costoso (O(n) por actualización).
- Mejor: indicadores **con estado**, actualizados incrementalmente. En TypeScript, `trading-signals` está diseñada así (`.update(nuevoValor)` muta el estado interno; soporta un modo "replace" para corregir la última vela mientras no cierra). En Python existe el paquete `streaming-indicators` con el mismo patrón (`.update()` / `.compute()`).
- Este enfoque es el que mejor calza con un pipeline de ingesta en Vercel (websocket/cola → `.update()` por tick), evitando recomputar todo el historial en cada invocación serverless.

### 2.5 Combinar señales técnicas con RAG/sentimiento

No hay una fórmula fija de "70% técnico + 30% sentimiento"; el patrón dominante es **debate + voto ponderado por confianza**, no una mezcla lineal:

- TradingAgents: los reportes independientes de cada analista alimentan un debate Bull/Bear, y el Trader compone la decisión final de forma cualitativa (no una suma numérica).
- Patrón más formal (paper "Roundtable Policy"): cada agente emite (postura, confianza, razonamiento), y se agregan por **voto ponderado por confianza** en lugar de mayoría simple. Algunos diseños tratan la **contradicción entre agentes como una señal en sí misma** ("el mercado no se ha decidido") en lugar de forzar una resolución.

---

## 3. Elección del LLM: ¿suscripción o API de pago?

Esta sección responde directamente a la pregunta de usar tu suscripción de Claude o ChatGPT en vez de pagar por token. **Es un área que ha cambiado de política cinco veces solo en los primeros seis meses de 2026** — hay que leerla con esa inestabilidad en mente.

### 3.1 Anthropic (Claude) — cronología de la política

| Fecha 2026 | Cambio |
|---|---|
| 9-ene | Anthropic bloquea del lado del servidor el uso de tokens OAuth de Free/Pro/Max fuera de Claude Code y claude.ai. |
| 20-feb | Se formaliza: los Términos de Consumidor prohíben usar el token OAuth de suscripción "en cualquier otro producto, herramienta o servicio — incluyendo el Agent SDK". |
| 4-abr | Se aplica activamente contra harnesses de terceros (OpenClaw, OpenCode, Cline), terminando el arbitraje de "correr agentes con el plan Max de $200/mes en vez de $1000+/mes de API". |
| 14-may | Anthropic anuncia que el uso del Agent SDK / `claude -p` / apps de terceros pasaría el 15-jun a un crédito mensual **separado**, facturado a tarifa de API completa. |
| 15-jun | **Pausado el mismo día que debía entrar en vigor.** Según el Centro de Ayuda de Claude: "por ahora, nada ha cambiado" — el Agent SDK y las apps de terceros autenticadas por suscripción siguen consumiendo del límite normal del plan, no de un pool medido aparte. |

**Estado actual (confianza media — puede volver a cambiar sin aviso):** el Claude Agent SDK sí funciona hoy con autenticación OAuth de un plan Pro/Max, y usarlo para una app propia (a través del Agent SDK, no reusando el token crudo por fuera) está permitido. Pero el Agent SDK está pensado arquitectónicamente como un SDK de agente de código (herramientas tipo bash/edición de archivos), no como una API de chat ligera — y el terreno de política se ha movido 5 veces en 7 meses.

**Problema práctico independiente de los términos de servicio (muy relevante para un bot 24/7):** múltiples issues abiertos en GitHub (anthropics/claude-code #29896, #50743, #38813, #44945, #12447) reportan que los tokens de acceso OAuth expiran cada 8-12 horas y su refresco automático falla en contextos desatendidos (cron, servidor siempre encendido, sesiones largas) — el refresco manual es bloqueado por Cloudflare (403) cuando no viene de un navegador. El consenso de la comunidad: **"la API de Anthropic con una API key persistente es la única solución confiable para operación desatendida."** Esto importa independientemente del riesgo de ToS, porque un bot de trading necesita correr sin supervisión.

### 3.2 OpenAI (ChatGPT) — no hay puente oficial equivalente

- No existe un puente oficial para usar ChatGPT Plus/Pro como API general. **Codex** es el producto agéntico sancionado ligado a un plan de ChatGPT, pero está diseñado para tareas de código, no como superficie de chat general.
- El **Apps SDK** y **AgentKit/ChatKit** permiten construir apps que corren *dentro* de chatgpt.com o vía la API medida — no un puente de suscripción hacia una app externa.
- Automatizar la interfaz web/app de ChatGPT (fuera de la API oficial) es tratado por consenso de la industria como contrario a los términos — no se pudo confirmar el texto exacto (fetch bloqueado), pero la conclusión práctica es de alta confianza: **no hay ruta de suscripción→API viable para un agente de trading general en el ecosistema OpenAI.**

### 3.3 Wrappers no oficiales — riesgo real, no teórico

- **gpt4free (g4f)**: activamente mantenido, pero encadena endpoints de terceros; viola los términos del backend que esté raspando en cada momento.
- **revChatGPT**: deprecado explícitamente, citado como ejemplo canónico de violación de términos.
- **OpenClaw**: harness legítimo y mantenido, pero fue el detonante de la ofensiva de Anthropic contra reuso de auth de suscripción — hay reportes de facturas que "saltaron de $20 a $500" al activarse el cobro por uso, y de suspensiones de cuenta por "patrones de uso automatizado anómalo".
- **Conclusión**: el riesgo de baneo es real y se ha ejercido activamente por ambas empresas; estas herramientas se rompen cada vez que el proveedor cambia su interfaz interna — una base frágil para algo tan sensible como la ejecución de un bot de trading.

### 3.4 Comparación de costo (si la suscripción fuera viable)

Ejemplo con el volumen típico de este proyecto (debate multi-agente + RAG, ~100 llamadas/día, ~8K tokens de entrada + 2K de salida por llamada, modelo clase Sonnet): **≈$108/mes** solo en tokens — ya supera el crédito implícito del plan Pro ($20) y se acerca al techo del Max 5x ($100). Si se escala a 300 llamadas/día o contextos RAG más grandes (20-30K tokens de entrada), el costo mensual sube a $300-800+, superando incluso el Max 20x ($200).

**Conclusión práctica: aunque el acceso programático por suscripción estuviera 100% permitido, solo gana frente a la API de pago con uso ligero. El volumen real de un sistema de debate multi-agente + RAG probablemente supera cualquier techo de suscripción y termina pagando tarifa de API de todos modos.**

### 3.5 Recomendación híbrida para este proyecto

Dado (a) la inestabilidad de política, (b) el problema de expiración de tokens en operación desatendida, y (c) que el costo real probablemente excede cualquier plan de suscripción:

1. **No apostar la confiabilidad del bot 24/7 a la autenticación por suscripción.** Usar la **API de pago de Anthropic** (Claude Sonnet ~$2/$10 por millón de tokens en ago-2026) para los agentes de decisión crítica (Trader, Risk Manager).
2. Considerar un **modelo de código abierto** vía un proveedor de inferencia barato (Together AI, Fireworks, DeepInfra, Groq) para las llamadas de mayor volumen/menor criticidad (p. ej. el analista técnico interpretando indicadores ya calculados, o el analista de sentimiento escaneando muchos titulares) — 50-90% más barato que las APIs frontera, sin ambigüedad de términos de servicio, sin inversión en GPU propia.
   - Modelos abiertos más fuertes hoy: DeepSeek V4 (Pro/Flash), GLM-5.1/5.2, Kimi K2.6/K3, Qwen3.7, MiniMax M3, gpt-oss-120b/20b. En benchmarks financieros los resultados son mixtos (en un ranking: GPT-5.5 > Opus 4.7 > DeepSeek V4 Pro > Kimi K2.6; en otro, Qwen3.7 Max queda primero) — ningún modelo abierto domina de forma uniforme, pero varios son competitivos.
   - Autohospedar el modelo más grande (DeepSeek V4 Pro, Kimi K3) requiere >1TB de VRAM — territorio de datacenter, no viable para un individuo. DeepSeek V4 Flash es más realista (~170-175GB VRAM, ej. 2×H200). Por eso, para este proyecto, la vía práctica es el **proveedor de inferencia pay-per-token de modelos abiertos**, no autohospedar.
3. Usar el **Vercel AI Gateway** para poder enrutar entre proveedores (Claude para decisiones críticas, modelo abierto barato para volumen alto) con una sola integración, sin acoplar el código a un SDK propietario.
4. Si en algún momento se quiere experimentar con el Claude Agent SDK autenticado por suscripción (p. ej. para desarrollo/pruebas, no para producción 24/7), es viable hoy — pero no construir la ejecución real de órdenes sobre esa base dada la inestabilidad documentada arriba.

---

## 4. Integración con Telegram

### 4.1 Bases del Bot API relevantes

- **Webhook vs long polling**: son mutuamente excluyentes por token de bot. Webhook necesita una URL HTTPS pública (pensado para hosting serverless "scale-to-zero" tipo Vercel Functions). **Dado que el sistema corre en la PC personal de tu familiar/amigo (sección 6.5), la opción correcta aquí es *long polling*** — el proceso local pregunta a Telegram por actualizaciones cada pocos segundos, sin necesitar IP/URL pública ni certificado.
- **Rate limits**: ~30 mensajes/seg global por bot, ~1 msg/seg por chat privado, ~20/min por grupo. Pasarse devuelve HTTP 429 con `retry_after`. Desde principios de 2025, el throttling se rastrea por chat, no solo por token. Con un solo chat autorizado (el suyo), esto casi nunca será un problema práctico.
- **Formato**: `HTML` como `parse_mode` es más seguro que `MarkdownV2` para contenido generado programáticamente (precios, tickers con `.`/`-`/`+` rompen el escapado de MarkdownV2).
- **Botones inline (`InlineKeyboardMarkup`)**: mecanismo estándar para "Aprobar / Rechazar" una señal de trading. El `callback_data` está limitado a 64 bytes — alcanza para un ID de orden + código de acción, no para los detalles completos (hay que buscarlos server-side por ID).

### 4.2 Librerías recomendadas

| Opción | Cuándo usarla |
|---|---|
| **grammY** (TypeScript), modo `bot.start()` (long polling) | **Recomendada** para este proyecto: sigue la última versión del Bot API, tipado fuerte, y el modo polling es tan soportado como webhook — solo cambia una línea de arranque. |
| aiogram / python-telegram-bot (Python) | Alternativa si el resto del stack es Python en lugar de TypeScript. |
| Vercel Chat SDK (`@vercel/chat`) | Ya no aplica de forma directa: está pensado para despliegue serverless con webhook, no para un proceso local con polling. Descartar salvo que en el futuro esto se mueva a la nube. |

### 4.3 Patrones de arquitectura

- **Flujo de alerta (push)**: motor de señales detecta oportunidad → formatea mensaje (HTML) → adjunta botones inline (Aprobar/Rechazar/Posponer) referenciando un ID de orden pendiente → `sendMessage` al chat de tu familiar/amigo.
- **Flujo de comando (`/comprar`, `/vender`, `/estado`)**: **nunca ejecutar la orden directamente desde el comando**. Patrón estándar: el comando crea una orden *pendiente* local → responde con confirmación por botones → solo el `callback_query` posterior (re-validado contra su `chat_id`/`user_id` y contra la orden pendiente aún válida) dispara la llamada real al MCP de Robinhood.
- **Seguridad obligatoria** (adaptada a un solo usuario, corriendo local):
  - Aunque no haya webhook público que proteger con `secret_token`, sigue siendo obligatorio validar en cada update que `chat_id`/`user_id` coincide exactamente con el de tu familiar/amigo — cualquier otro remitente se ignora.
  - Token del bot y token/refresh token de Robinhood, cifrados en disco (ver sección 6.5), nunca en texto plano ni en un repositorio git.
- **Throttling**: con un solo chat, un token-bucket simple en memoria (sin necesidad de Redis) y backoff con jitter ante 429 (`retry_after * random(0.7–1.3)`) es suficiente.

### 4.4 Riesgos documentados

- Terms of Service de Telegram para desarrolladores de bots **deslindan responsabilidad** sobre transacciones financieras entre el bot y sus usuarios, y permiten baneo inmediato y permanente por violaciones.
- Caso documentado (2025): un bot de trading fraudulento operó sin autorización durante 3 semanas, causando pérdidas de +$2.3M en ~840 usuarios. Refuerza: nunca ejecutar trades directamente desde un comando crudo, minimizar qué credenciales de broker vive en el proceso del bot, y mantener log de auditoría de cada acción aprobada.

---

## 5. Integración con el broker: Robinhood

### 5.1 Hallazgo clave — MCP oficial de trading agéntico (mayo 2026)

Robinhood lanzó el **27 de mayo de 2026** ["Robinhood is now open to agents"](https://robinhood.com/us/en/newsroom/robinhood-is-now-open-to-agents/): un servidor **MCP oficial** en `agent.robinhood.com/mcp/trading`, diseñado explícitamente para que agentes de IA (Claude, Claude Code, ChatGPT, Cursor, Grok, y otras plataformas compatibles con MCP) operen directamente.

- **Autenticación**: OAuth — el agente/proveedor de IA nunca ve la contraseña de Robinhood.
- **Aislamiento**: las operaciones solo se ejecutan dentro de una **sub-cuenta "Agentic" dedicada** (una de hasta 10 sub-cuentas auto-dirigidas que puede tener un usuario), nunca en el portafolio principal. Hay que depositar fondos explícitamente en esa sub-cuenta.
- **Herramientas expuestas**: `get_accounts`, `get_portfolio`, `get_equity_positions`, `get_equity_quotes`, `get_equity_orders`, `search`, watchlists, `review_equity_order` (simulación/advertencias pre-operación), `place_equity_order`, `cancel_equity_order`.
- **Estado actual (beta)**: acciones (equities) y, desde el **20 de julio de 2026**, también **cripto** (actualizado en verificación del 5-ago-2026 — antes solo era "próximamente"). Opciones sigue "en despliegue progresivo". Contratos de eventos y futuros: aún sin fecha.
- **Sin límites de rate documentados públicamente.** Tampoco hay, a la fecha de esta verificación, un esquema de parámetros publicado para `place_equity_order` — el soporte de stop-loss sigue sin confirmarse oficialmente (ver 5.2), y el OAuth sigue limitado a redirecciones `localhost` (ver 6.2), ambos re-confirmados en la verificación del 5-ago-2026.
- **Responsabilidad**: Robinhood deslinda expresamente la supervisión del agente una vez conectado — queda bajo los términos de la plataforma de IA usada.
- Reseñas mixtas: una prueba de 3 semanas con Claude ejecutando 8 operaciones ETF en la sub-cuenta aislada no reportó fallas de confiabilidad ni rate-limit ([Saving to Invest](https://savingtoinvest.com/i-let-claude-trade-my-robinhood-agentic-account-heres-what-happened/)); otra reseña calificó el lanzamiento como "a medio hornear" por falta de opciones multi-pata, sin cripto, y sin sandbox ([Medium/Austin Starks](https://medium.com/@austin-starks/i-just-tried-robinhoods-alleged-agentic-trading-i-am-not-impressed-33d3725a23e0)).

**Esto es exactamente el tipo de integración que conviene para este proyecto**, dado que ya se está trabajando dentro del ecosistema de agentes compatibles con MCP (Claude Code). En lugar de scraping no oficial, el flujo de ejecución de órdenes debería hablar con este MCP oficial vía OAuth.

### 5.2 Stop-loss, cierre de posiciones y copytrading — lo que pediste específicamente

**Stop-loss dentro del MCP oficial: NO CONFIRMADO.** No existe documentación pública que enumere qué `order_type` acepta exactamente `place_equity_order` (ni la página de soporte de "Agentic Trading", ni el anuncio de prensa, ni análisis técnicos de terceros como SecProve especifican el esquema de parámetros). Se sabe que el backend general de Robinhood sí soporta stop, stop-limit y trailing stop para órdenes normales — la duda es únicamente si el MCP **expone** esos tipos al agente. Una librería no oficial de terceros (`robinhood-for-agents`, no afiliada a Robinhood) sí implementa stop y trailing en su propio wrapper, lo que confirma que el backend lo permite, pero no dice nada sobre el MCP oficial.
- **Recomendación**: no asumir que el stop-loss funciona vía el MCP hasta probarlo en vivo. Como respaldo, diseñar un **stop-loss sintético**: el propio sistema monitorea `get_equity_quotes` en un loop y dispara una orden `place_equity_order` de venta a mercado cuando el precio cruza el umbral — esto funciona sin depender de que el MCP soporte el tipo de orden nativamente.

**Cerrar una posición no es una operación dedicada.** No hay un tool `close_position`. El patrón oficial documentado: llamar `get_equity_positions` para obtener la cantidad actual, y luego colocar una orden de venta opuesta por esa cantidad vía `place_equity_order`. `cancel_equity_order` solo cancela órdenes pendientes/no ejecutadas, no cierra una posición abierta.
- Patrón defensivo recomendado (visto en `robinhood-for-agents`): separar explícitamente en el código dos acciones distintas — "sell" (cerrar una posición larga existente) vs "sell_short" (abrir una posición corta nueva) — para que el agente nunca confunda "cerrar" con "abrir en corto por error".

**Copytrading: Robinhood NO lo ofrece de forma automatizada — y es una decisión deliberada, no un vacío técnico.** En marzo de 2026 Robinhood lanzó **Robinhood Social** en beta: los usuarios pueden ver las posiciones de traders verificados (KYC real, no influencers falsos) y replicar manualmente con un toque — **explícitamente sin espejo automático de portafolio**. El propio CEO de Robinhood había advertido antes (sept-2025) que el copytrading automatizado hacia las cuentas de otras personas se acerca a "asesoría de inversión no autorizada" bajo el Investment Advisers Act — por eso mantienen el "clic final" en manos del usuario.
- **Esto es la línea legal importante para tu proyecto**: automatizar la réplica de operaciones **hacia tu propia cuenta** (o tus propias sub-cuentas vinculadas) es una actividad de riesgo bajo — es solo tu bot operando tu dinero. Automatizar la réplica de operaciones **hacia las cuentas de otras personas** (ofrecerlo como servicio a terceros) es exactamente lo que Robinhood evitó por razones regulatorias, y probablemente requeriría registro como asesor de inversiones (RIA) si se ofrece a otros.
- **Multi-cuenta**: el MCP oficial permite *leer* todas las cuentas del usuario (`get_accounts`/`get_portfolio`), pero las herramientas de *escritura* (`place_equity_order`, `cancel_equity_order`) están restringidas exclusivamente a la sub-cuenta Agentic aislada — es una restricción dura confirmada, no solo una limitación de la beta. Replicar una operación en las otras sub-cuentas propias no es posible vía el canal oficial; solo sería posible con librerías no oficiales, con el mismo riesgo de ToS/congelamiento ya documentado para `robin_stocks`.
- **Conclusión práctica**: si por "copytrading" te refieres a que **tu propio sistema** replique señales (ya sea generadas por tu RAG, o copiadas de una fuente externa como un canal de Telegram/Discord) hacia **tu propia cuenta Agentic**, eso es perfectamente construible con el MCP oficial — es simplemente tu motor de señales llamando `place_equity_order`. Si te refieres a ofrecer ese copytrading a **otras personas**, eso tiene implicaciones regulatorias serias que habría que resolver antes de construirlo.

**Sobre `review_equity_order`**: existe y simula la orden devolviendo advertencias pre-operación ("Preview Trades" en el lenguaje del anuncio), pero **no es obligatorio a nivel de protocolo** — la propia documentación de soporte de Robinhood dice que "los usuarios pueden configurar sus agentes para ejecutar órdenes sin aprobación si lo han solicitado explícitamente". Es decir, `place_equity_order` puede llamarse sin pasar antes por `review_equity_order`. **Tratar "siempre revisar antes de ejecutar" como una convención de seguridad que el propio proyecto debe imponerse en su lógica de agente**, no como algo que Robinhood garantiza.

### 5.3 Robinhood Crypto Trading API (oficial, separado)

- Lanzada el 30 de mayo de 2024, GA. REST API en `trading.robinhood.com`, docs en `docs.robinhood.com/crypto/trading/`.
- Auth por API key + firma Ed25519 (`x-api-key`, `x-timestamp`, `x-signature`).
- Cubre **solo cripto**: cotizaciones, holdings, pares de trading, colocar/consultar/cancelar órdenes (market, limit, stop-loss, stop-limit).
- Sin sandbox. Rate limits no documentados públicamente.
- Relevante solo si el alcance del proyecto incluye cripto además de acciones — hoy son dos superficies de API separadas (Crypto API vs Agentic MCP).

### 5.4 Librería no oficial (`robin_stocks`) — solo como referencia de riesgo

- Sigue siendo la más conocida (2.1k★, MIT), pero **confirmado en la verificación del 5-ago-2026: está efectivamente sin mantenimiento** — sin commits desde febrero de 2026 (hace ~6 meses), y el lanzamiento del MCP oficial en mayo no reactivó al mantenedor. 295+ issues abiertos, rupturas recurrentes cada vez que Robinhood cambia su flujo interno de MFA/verificación de dispositivo (issues #530, #521, #533, #296, #1621), y el propio issue #1609 ("¿alguien sigue actualizando esto?") sin respuesta.
- La comunidad ya inició un fork por frustración: **`DhruvaBansal00/robin_stocks_v2`** (referenciado desde el issue #1650) — si en algún momento se necesita este camino no oficial como respaldo, preferir el fork activo sobre el original abandonado.
- Caso documentado de **cuenta congelada** por trading vía API no oficial (issue #1604).
- Viola los términos de servicio de la cuenta estándar (acceso restringido a interfaces oficiales, discreción total de Robinhood para restringir/cerrar cuentas).
- **Recomendación: evitar esta ruta ahora que existe el MCP oficial**, salvo como fallback muy consciente del riesgo y solo en una cuenta de prueba desechable.

### 5.5 Restricciones prácticas a considerar

- **Regla PDT**: según reportes secundarios, FINRA eliminó el requisito de Pattern Day Trader (umbral de $25k) el 4 de junio de 2026, y Robinhood lo implementó el mismo día. **Esto necesita verificación contra fuente primaria (FINRA/SEC) antes de asumirlo como definitivo** — la investigación solo encontró confirmación secundaria.
- **Tipos de orden**: opciones solo soportan órdenes limit (no market); acciones/cripto soportan market, limit, stop-loss, stop-limit **a nivel de backend general** (ver 5.2 sobre la duda específica de si el MCP los expone).
- **Horario extendido**: disponible vía Robinhood Gold.
- **Niveles de opciones**: 4 niveles (0 a 3), gatillados por cuestionario de idoneidad; nivel 3 (spreads multi-pata) suele requerir cuenta de margen.
- **No hay entorno sandbox/paper-trading** en ningún canal (ni Crypto API ni Agentic MCP). Las pruebas se hacen con dinero real en la sub-cuenta aislada — hay que empezar con montos mínimos.

### 5.6 Alternativas de broker (contexto, no se está recomendando cambiar)

Si en algún punto las limitaciones de Robinhood (sin sandbox, solo acciones en el MCP, sin opciones multi-pata, stop-loss no confirmado) bloquean el proyecto, las alternativas con APIs oficiales más maduras son:

| Broker | Fortaleza |
|---|---|
| **Alpaca** | Mejor opción para bots: REST + WebSocket documentado, rate limits publicados (200/min gratis, 1000/min con fondos), **entorno paper-trading completo**. |
| Interactive Brokers | Cobertura global/multi-activo más amplia, rate limits documentados (~50 msg/seg), mayor complejidad de integración. |
| Tradier | API de ciclo de vida de órdenes simple, documentada. |
| Charles Schwab (post-TD Ameritrade) | API real para acciones/opciones, útil si ya se es cliente Schwab. |

---

## 6. Tu escenario específico: operar la cuenta de tu familiar/amigo (sin cobro), sosteniendo tú el OAuth

Confirmaste dos cosas importantes: (a) no hay compensación — es un familiar/amigo, no un cliente pagado —, y (b) serías tú (el desarrollador) quien sostiene el acceso OAuth/credenciales de su cuenta, no él operando su propio agente. Esto cambia el análisis de la sección 5.2 en dos direcciones distintas: reduce el riesgo regulatorio clásico, pero expone un problema técnico real que no estaba resuelto.

### 6.1 El ángulo legal se relaja, pero no desaparece (no es asesoría legal)

- La definición federal de "asesor de inversiones" bajo el Investment Advisers Act generalmente requiere **compensación** como uno de sus tres elementos (junto con "estar en el negocio de" y "asesorar sobre valores"). Al no haber cobro, ese detonante específico probablemente no se activa.
- **FINRA Rule 3260** (autorización escrita para operar con discreción sobre la cuenta de otra persona) rige a broker-dealers y representantes registrados — no aplica directamente a un arreglo informal entre familiares/amigos.
- Esto **no es una autorización legal general**: las reglas varían por estado, y un arreglo "sin cobro" puede perder esa característica si se vuelve recurrente, se expande a más personas, o si en algún momento aceptas algo de valor a cambio (incluso no monetario). Si esto crece más allá de una sola persona de confianza, vale la pena una consulta legal puntual.
- Lo que **sí** falta, incluso sin problema regulatorio: no hay estructura de deber fiduciario, licencia, seguro, ni mecanismo de resolución de disputas — si algo sale mal, es enteramente una cuestión de confianza entre ustedes dos, no algo que un regulador vaya a arbitrar.

### 6.2 El problema técnico real: el OAuth de Robinhood hoy solo soporta `localhost`

Este es el hallazgo más concreto de esta sección, y afecta la viabilidad misma de un backend que sostenga el token de otra persona:

- El OAuth de Agentic Trading de Robinhood **no está restringido a una lista fija de plataformas** (Claude/ChatGPT/Cursor/Grok) — es un flujo OAuth 2.1 + PKCE + registro dinámico de cliente relativamente estándar, y la propia Robinhood dice que se puede conectar "otros agentes" y "agentes personalizados". Técnicamente, cualquier desarrollador puede intentar conectarse.
- **Pero solo acepta redirecciones `http://localhost:...`** — no hay soporte hoy para un callback HTTPS alojado en un servidor. Un desarrollador real (Austin Starks, creador de NexusTrade, una SaaS de trading multi-broker que ya integra Alpaca/Public/Tradier/TradeStation) intentó cablear Robinhood en producción y fue rebotado a una página de error — tuvo que **retirar** la integración de Robinhood de su producto por esta razón exclusivamente.
- **Consecuencia práctica para tu caso**: la autorización inicial necesita hacerse en una máquina que pueda recibir el callback en `localhost`, con el teléfono de tu familiar/amigo con la app de Robinhood instalada y con sesión iniciada (Robinhood pide una verificación desde el celular). Es decir: **para el paso inicial, tu familiar necesita estar físicamente presente** (o darte acceso a su teléfono+login ese momento) — no es algo que puedas hacer 100% a distancia sin que él intervenga.
- El camino que usan herramientas no oficiales (OpenClaw, `robinhood-for-agents`) es: completar ese único intercambio local/con navegador una vez, y luego **persistir el `refresh_token` resultante en tu propio backend** (en una bóveda cifrada, keychain del sistema, o AES-256), para operar sin supervisión desde ese momento. Esto funciona, pero:
  - **No está documentado ni sancionado oficialmente por Robinhood** — podría romperse sin aviso en una futura actualización.
  - Hay indicios de que el refresh token puede ser de un solo uso/rotativo — si dos procesos intentan refrescarlo a la vez, se puede invalidar la cadena. Diseña con eso en mente (un solo proceso dueño del token, con logging de fallos de autenticación).

### 6.3 Qué dicen los términos de Robinhood sobre que otra persona sostenga el acceso

- La documentación de Agentic Trading usa lenguaje de "tú autorizas a un agente de IA de terceros... en tu nombre" y "tú eres responsable en última instancia de las operaciones que haga tu agente de IA" — está pensada para que el titular sea quien controla el agente.
- No se encontró una cláusula explícita que prohíba o permita que **otra persona** (tú) sea quien sostenga el resultado de esa autorización — es un área no cubierta directamente en la documentación pública (10 semanas después del lanzamiento, sigue siendo escasa).
- Los acuerdos generales de cuenta de Robinhood tienden a poner el compartir acceso "bajo tu propio riesgo" — no lo prohíben de forma tajante, pero trasladan toda la responsabilidad al titular de la cuenta.

### 6.4 Recomendaciones concretas para este escenario

1. **Consentimiento por escrito, aunque sea informal**: un mensaje de texto o correo de tu familiar/amigo confirmando qué puede hacer el bot, los límites de monto/posición, que es sin cobro, y que el acceso es revocable cuando él quiera. No sustituye asesoría legal, pero deja constancia clara si algo se disputa después.
2. **Nunca pidas su contraseña real.** Haz que la autorización inicial (el paso `localhost` + verificación desde su teléfono) la complete él mismo, contigo presente si hace falta técnicamente — el resultado es un token OAuth, no su contraseña ni su sesión completa.
3. **Kill switch independiente**: Robinhood permite al titular desconectar el agente directamente desde su propia app en cualquier momento, y le notifica cada operación que el agente realiza — no intentes ocultar o suprimir esa visibilidad; es su seguro de vida independiente de tu backend.
4. **Usa la sub-cuenta Agentic aislada como límite de daño**: que tu familiar solo deposite ahí el dinero que está genuinemente dispuesto a arriesgar con un bot experimental.
5. **Higiene de secretos real**: el refresh/access token va en un gestor de secretos (no texto plano, no control de versiones). Monitorea fallos de autenticación activamente, ya que este patrón no está oficialmente soportado y puede romperse sin aviso.
6. **No conviertas esto en un "producto"** sin repensar la sección 5.2 — el marco de "sin cobro, una sola persona de confianza" se sostiene para este caso puntual; si en el futuro quieres ofrecerlo a más personas o cobrar por ello, hay que volver a evaluar el ángulo regulatorio desde cero.

### 6.5 Decisión confirmada: instalación local en su PC personal + Telegram solo para él

Confirmaste que el sistema se instalará directamente en la PC personal de tu familiar/amigo, y que el bot de Telegram será solo para él (no multi-usuario). Esto es un cambio de arquitectura real, no solo un detalle de despliegue, y en general **simplifica** varios de los problemas de las secciones anteriores:

**Lo que se resuelve solo:**
- **El problema de OAuth `localhost` (sección 6.2) desaparece como problema.** Como el proceso que recibe el callback de Robinhood corre en la misma máquina donde él abre el navegador para autorizar, el redirect `http://localhost:...` es exactamente lo que Robinhood soporta hoy — no es un workaround, es el flujo normal. Ya no necesitas exportar su `refresh_token` a un backend tuyo en la nube; el token vive y se usa en su propia PC.
- **Reduce (aunque no elimina) el problema de custodia de credenciales**: si el proceso corre bajo su usuario de Windows, en su disco, el token nunca sale de su máquina hacia infraestructura que tú controlas remotamente — sigue siendo importante guardarlo cifrado (ver más abajo), pero el modelo de riesgo es mejor que "backend tuyo en Vercel con su token".

**Lo que cambia y hay que diseñar distinto:**
- **Telegram: usar *long polling*, no webhook.** Un webhook requiere una URL HTTPS pública a la que Telegram pueda enviar el POST — su PC personal normalmente no tiene eso (NAT/router doméstico, sin certificado). *Long polling* (el proceso local pregunta a Telegram "¿hay algo nuevo?" cada pocos segundos) no necesita URL pública y es el modo estándar para un bot que corre en un escritorio. grammY lo soporta igual de bien que webhook — solo cambia `bot.start()` (polling) en vez de `webhookCallback()`.
- **Uptime = "cuando su PC está encendida", no 24/7 garantizado.** Si apaga la PC o se reinicia Windows, el bot deja de recibir comandos y de vigilar el mercado hasta que vuelva a encenderla. Antes de construir, alinear expectativas con él: ¿la PC se queda encendida siempre (con Windows configurado para no dormir/hibernar), o el bot es más bien "algo que revisamos cuando la prendemos"? Esto determina si vale la pena invertir en arranque automático.
- **Arranque automático y resiliencia** (actualizado con verificación del 5-ago-2026): usar **pm2** para supervisar/reiniciar el proceso Node.js si crashea, pero pm2 **no tiene soporte nativo de servicio de Windows** (su wrapper comunitario `pm2-windows-service` está sin mantenimiento desde 2018 y reportado como roto en Windows recientes) — para registrarlo como servicio real de Windows (arranque automático al iniciar el sistema, no solo al iniciar sesión), usar **WinSW** ([GitHub](https://github.com/winsw/winsw), activamente mantenido, 14k★) en vez de NSSM, que sigue funcionando pero está congelado desde 2014 sin desarrollo activo.
- **Monitoreo remoto**: si tú (el desarrollador) no vas a estar físicamente frente a esa PC, necesitas alguna forma de saber si el bot sigue vivo o si la autenticación con Robinhood falló — lo más simple es que el propio bot te avise por Telegram (a un chat separado tuyo, o al mismo canal) si detecta un fallo de auth o un error no manejado, en vez de depender de revisar logs en su máquina.
- **Actualizaciones de código**: sin un pipeline de CI/CD como tendrías en Vercel, actualizar el bot significa acceso remoto a su PC (TeamViewer/AnyDesk/Escritorio remoto de Windows) o un mecanismo simple de auto-actualización (p. ej., el proceso revisa un repositorio git al iniciar). Definir esto antes de que el sistema esté en producción con dinero real.
- **Recursos de la PC**: para el pipeline RAG (sección 1) y el análisis técnico (sección 2), una PC de consumo puede correr perfectamente la orquestación, el cálculo de indicadores y las llamadas a APIs externas (LLM, embeddings, vector DB) — no hace falta GPU local si los embeddings/LLM se consumen vía API en la nube, que es justamente lo recomendado en las secciones 1 y 3. Si su PC tiene una GPU decente y en algún momento se quiere evitar por completo el costo de API, un modelo abierto pequeño (ej. Qwen3.7 7B/14B o gpt-oss-20b) podría correr localmente, pero es una optimización posterior, no un requisito de partida.

**Recomendación concreta de stack para este despliegue**: un único proceso Node.js/TypeScript local (o un ejecutable empaquetado) que incluya: el cliente MCP de Robinhood (con el token guardado cifrado en disco vía **`@napi-rs/keyring`** — no `keytar`, que está archivado/muerto desde dic-2022, confirmado en verificación del 5-ago-2026; `@napi-rs/keyring` es su reemplazo activo, usado incluso por el propio SDK de Azure de Microsoft para migrar fuera de keytar, y soporta el Administrador de credenciales de Windows nativamente), el bot de grammY en modo polling, el pipeline de indicadores técnicos, y las llamadas salientes a las APIs de LLM/embeddings/vector DB en la nube. Ver sección 7 para el diagrama actualizado y sección 8 para el stack completo.

### 6.6 Refinamiento final: todo el sistema vive dentro de WSL2, no en Windows nativo

Decisión posterior: en vez de que solo Agent Reach corra en WSL2 (sección 8.2) y el resto del proceso corra nativo en Windows, **todo el sistema se aisló dentro de una sola distro WSL2** (Node.js, Docker, Agent Reach, bot de Telegram, y Claude Code mismo). Motivación: aislar el sistema de trading de la instalación de Windows que tu familiar/amigo usa para su día a día — si algo en el sistema falla o se compromete, el daño queda contenido a esa distro Linux, no al resto de su PC.

Esto simplifica varias cosas del resto de esta sección:
- El punto de custodia de credenciales pasa de "su usuario de Windows" a "su distro WSL2" — sigue siendo su misma PC física, pero con un límite de aislamiento adicional entre el sistema de trading y el resto de lo que hace en esa máquina.
- `@napi-rs/keyring` sigue aplicando (WSL2 puede acceder al Administrador de credenciales de Windows, o usarse con un keyring de Linux dentro de la distro — cualquiera de los dos evita texto plano).
- El callback `localhost` del OAuth de Robinhood (sección 6.2) sigue funcionando igual: WSL2 reenvía automáticamente `localhost` entre Windows y la distro, así que el navegador de Windows puede completar la autorización sin fricción aunque el proceso que la recibe corra en Linux.
- `install.ps1` pasó de ser el instalador completo a ser un **bootstrap**: en Windows solo asegura que WSL2 exista y clona el repo dentro de la distro; el instalador real (`scripts/wsl-setup.sh`) corre en Linux e instala todo lo demás — incluyendo ahora Docker Engine nativo de Linux en vez de Docker Desktop para Windows, evitando esa dependencia extra en el lado de Windows.
- El bot de Telegram (sección 4) no cambia su diseño (long polling, sin webhook) — solo cambia dónde corre.

---

## 7. Arquitectura propuesta (visión de alto nivel)

```
┌────────────────────────────────────────────────────────────────────────────┐
│  PC personal de tu familiar/amigo (proceso Node.js/TS local, 1 sola cuenta) │
│                                                                              │
│   ┌─────────────────────────────┐        ┌─────────────────────────────┐   │
│   │  Ingesta de datos            │        │  Indicadores técnicos        │   │
│   │  (precio en vivo, noticias,  │───────▶│  (trading-signals, streaming, │   │
│   │   filings, sentimiento)      │        │   RSI/MACD/BB — matemática    │   │
│   └──────────────┬───────────────┘        │   real, NO calculada por LLM) │   │
│                  │                        └──────────────┬───────────────┘   │
│                  ▼                                       │                   │
│   ┌─────────────────────────────┐                        │                   │
│   │  Pipeline RAG                │                       │                   │
│   │  - Chunking consciente de     │                      │                   │
│   │    estructura                 │                      │                   │
│   │  - Híbrido BM25+denso+RRF     │                      │                   │
│   │  - Re-ranking                 │                      │                   │
│   └──────────────┬───────────────┘                       │                   │
│                  └───────────────────────┬────────────────┘                  │
│                                          ▼                                   │
│              ┌───────────────────────────────────────────────┐               │
│              │  Agentes especializados (llamadas salientes a  │              │
│              │  API de LLM/embeddings/vector DB en la nube)    │              │
│              │  Fundamental · Sentimiento · Técnico · Macro    │              │
│              └──────────────────────┬──────────────────────────┘             │
│                                     ▼                                        │
│                    ┌─────────────────────────────┐                          │
│                    │  Debate Bull/Bear → Trader   │                          │
│                    │  → Risk Manager (reglas       │                          │
│                    │    determinísticas, no LLM)   │                          │
│                    └──────────────┬───────────────┘                          │
│                                   │ señal aprobada                           │
│                    ┌──────────────┴───────────────┐                          │
│                    ▼                              ▼                          │
│        ┌─────────────────────┐      ┌─────────────────────────────┐          │
│        │  Bot de Telegram      │      │  Cliente MCP de Robinhood     │          │
│        │  (grammY, long polling,│◄────►│  (OAuth localhost nativo,    │          │
│        │  solo su chat)         │      │  sub-cuenta Agentic aislada,  │          │
│        │  - Alerta + botones     │      │  token cifrado en disco:      │          │
│        │    Aprobar/Rechazar     │      │  place_equity_order,          │          │
│        └─────────────────────┘      │  get_equity_positions (cierre │          │
│                                     │  = venta opuesta), stop-loss   │          │
│                                     │  sintético si el MCP no lo     │          │
│                                     │  soporta nativamente)          │          │
│                                     └─────────────────────────────┘          │
│                                                                              │
│   Supervisado por: Programador de tareas de Windows / PM2 / NSSM            │
│   (arranque automático + reinicio si crashea)                              │
└────────────────────────────────────────────────────────────────────────────┘
```

**Flujo crítico de seguridad**: la señal nunca ejecuta la orden automáticamente. Pasa por: (1) Risk Manager determinístico → (2) mensaje de Telegram con confirmación por botones (al chat de tu familiar/amigo) → (3) solo tras aprobación humana explícita (`callback_query` validado) se llama a `place_equity_order` vía el MCP de Robinhood, corriendo localmente en su propia PC.

---

## 8. Stack tecnológico recomendado — versión 100% gratuita (requisito confirmado 5-ago-2026)

Confirmaste que todo debe ser gratuito, sin excepción. Esto invalida varias recomendaciones de pago de las secciones anteriores (Claude API de pago, voyage-finance-2, Cohere Rerank, Qdrant Cloud/Neon como only-option, la herramienta `web_search` de Claude). La tabla de abajo reemplaza a la anterior con la versión gratuita de cada capa; la sección 8.1 explica qué se sacrifica y qué puede romperse.

| Capa | Recomendación gratuita | Por qué / respaldo |
|---|---|---|
| Despliegue | Proceso Node.js/TypeScript local en la PC de tu familiar/amigo (Windows), supervisado por **pm2** + **WinSW** | Sin costo de nube — ya era gratis. |
| Orquestación de agentes | LangGraph o MCP nativo, corriendo en el mismo proceso local | Software libre, sin costo. |
| LLM | **Combinación de niveles gratuitos, rotando entre proveedores**: Groq (30 RPM / 1.000 RPD por modelo, Llama 3.3 70B/Qwen3-32B/DeepSeek R1 Distill), Gemini 3 Flash (10 RPM / 1.500 RPD), OpenRouter (modelos `:free`, 20 RPM / 50-1.000 RPD) | **Claude/GPT de pago quedan fuera del alcance por el requisito de $0** — Anthropic confirmado sin nivel gratuito sostenido (solo ~$5 de crédito único de prueba). Ver 8.1 para el cálculo de si esto alcanza para el volumen del sistema. |
| LLM — respaldo local | Si su PC tiene GPU ≥12GB VRAM: Qwen3 14B o Phi-4 vía Ollama (ilimitado, sin límite de peticiones, 100% gratis para siempre) | **Necesito saber qué tarjeta gráfica tiene su PC** — esto determina si este respaldo es real o no. Sin GPU decente, la inferencia por CPU es demasiado lenta (15-40s por llamada) para un debate multi-agente ágil, aunque sí alcanza para un ciclo de "revisar unas pocas veces al día". |
| Análisis técnico | `trading-signals` v8.2.0 (TS) | Ya era gratis — software libre, sin cambios. |
| Embeddings | **BGE-M3** o **Qwen3-Embedding-0.6B**, corriendo localmente vía Ollama | Gratis e ilimitado, sin llamadas a API. BGE-M3 es lo que usan hoy la mayoría de stacks RAG en producción según la verificación. Sin equivalente gratuito afinado a finanzas todavía — se pierde la ventaja de voyage-finance-2. |
| Reranking | **bge-reranker-v2-m3** local (CPU, sin GPU necesaria) | Gratis. Saltarse el reranking del todo pierde ~17% de recall relativo en documentos financieros (0.816 con reranker vs 0.695 sin él) — vale la pena correrlo localmente, el costo de cómputo es trivial a esta escala. |
| Vector DB | **pgvector o Qdrant autohospedados en la misma PC vía Docker Desktop** | Gratis, sin límites de uso, sin riesgo de que un proveedor borre el cluster por inactividad (ver 8.1 sobre por qué evitar el free tier de Qdrant Cloud). |
| Búsqueda (sobre datos ya indexados) | Híbrida (BM25 + denso + RRF) + reranker local | Ya era software libre. |
| Búsqueda web en vivo | **SearXNG autohospedado** (Docker, gratis, sin límite de peticiones) | Reemplaza la herramienta de pago de Claude/Tavily. Es literalmente la misma solución que la propia comunidad de TradingAgents propuso para el mismo vacío (ver su issue #699). |
| Datos de mercado (precio/OHLCV) | **Finnhub** (60 req/min, cuasi-tiempo-real) + **Alpaca** (200 req/min, tiempo real solo bolsa IEX, plan de datos gratuito) | Cubren cómodamente 5-20 tickers monitoreados cada pocos minutos. |
| Noticias financieras | **Finnhub** (misma cuota) + **GDELT** (gratis, sin límite, sin clave) | Alpha Vantage (25/día) y NewsAPI (100/día, **prohibido para producción por sus propios términos**) solo sirven como apoyo ocasional/pruebas locales, no como fuente en vivo. |
| Sentimiento social | **[Agent Reach](https://github.com/Panniantong/agent-reach)** (lee Twitter/Reddit/YouTube sin necesitar sus APIs oficiales, cero costo de API) — **corriendo dentro de WSL2**, ver 8.2 | La API oficial de Reddit ahora exige aprobación manual (2-4 semanas) desde nov-2025, y el registro de StockTwits está cerrado — Agent Reach evita ambos cuellos de botella. Si de todas formas quieres la vía oficial de Reddit, vale la pena iniciar esa solicitud ya, en paralelo. |
| Bot de mensajería | grammY v1.45.1 (TS), modo long polling | Ya era gratis. |
| Broker | Robinhood Agentic Trading MCP (OAuth localhost nativo, sub-cuenta aislada) | Ya era gratis — no hay cuota de Robinhood por usar su MCP. |
| Custodia del token de Robinhood | `@napi-rs/keyring` v1.3.0 (Administrador de credenciales de Windows) | Ya era gratis — software libre. |

### 8.1 Qué se sacrifica y qué puede romperse en la versión 100% gratuita

- **El LLM es el punto más frágil.** Estimación de volumen para este sistema (15 tickers × ~6 llamadas por ticker entre analistas+debate+riesgo × 3 revisiones/día) ≈ **270 llamadas/día**, o de forma más conservadora 150-500/día. Groq + Gemini + OpenRouter combinados **cubren ese volumen en el total diario**, pero: (a) los picos al abrir el mercado (evaluar muchos tickers en pocos minutos) sí pueden golpear los límites por minuto de cada proveedor individual — hay que espaciar/encolar las peticiones, no dispararlas todas juntas; (b) el listado de modelos gratuitos de OpenRouter rota mensualmente según qué proveedores donan capacidad gratis — no es un compromiso estable a largo plazo; (c) ninguno de estos proveedores publica una garantía de disponibilidad para su nivel gratuito — Gemini ya recortó sus cuotas gratuitas 50-80% en diciembre de 2025 y quitó Pro del nivel gratuito en abril de 2026, sin aviso previo. **Hay que diseñar el sistema para degradar con gracia** (saltarse un ciclo de revisión, reducir el número de agentes que opinan) en vez de asumir que el nivel gratuito siempre va a estar disponible.
- **Advertencia de términos de servicio que hay que leer con cuidado**: la política de uso prohibido de Gemini restringe explícitamente pipelines automatizados **sin supervisión humana en dominios de alto riesgo, incluyendo finanzas** — justo el tipo de sistema que estamos construyendo. El patrón que ya tenemos (nunca ejecutar una orden sin aprobación humana explícita por Telegram) ayuda a mantenerse del lado correcto de esa política, porque sí hay un humano en el loop antes de cualquier acción real — pero vale la pena leer esa política completa antes de depender de Gemini para producción. Cohere queda descartado por completo: su clave de prueba está explícitamente prohibida para uso de producción.
- **Se pierde la ventaja de un embedding afinado a finanzas** (voyage-finance-2) — no existe todavía un equivalente gratuito pulido; BGE-M3/Qwen3-Embedding son de propósito general. Es una pérdida de calidad aceptada a cambio de costo cero.
- **Autohospedar pgvector en Windows tiene más friction que en Linux** (mejor camino: Docker Desktop, evitando compilar con Visual Studio Build Tools). Igual con Qdrant — su binario nativo de Windows no tiene soporte oficial, usar su imagen Docker.
- **Evitar el nivel gratuito de Qdrant Cloud como dependencia real**: sus clusters gratuitos se suspenden tras 1 semana inactivos y se **borran** tras 4 semanas — un riesgo real si el bot pasa temporadas sin usarse. Autohospedar en la misma PC no tiene ese riesgo.
- **Fuentes de datos de mercado/noticias gratuitas con límites duros**: Alpha Vantage (25 peticiones/día, compartidas entre precio y noticias), NewsAPI (100/día, **prohibido explícitamente para producción por sus propios términos** — solo sirve para pruebas locales), Polygon/Massive.com (5/min, solo datos de fin de día). IEX Cloud ya no existe (cerró en 2024). Ninguna de estas debe tratarse como fuente principal en vivo — están para respaldo/pruebas.
- **Reddit y StockTwits oficiales están más cerrados que antes**: Reddit exige aprobación manual desde nov-2025 (2-4 semanas de espera, sin registro automático); StockTwits tiene su registro de desarrollador cerrado por revisión. Por eso Agent Reach es la vía práctica recomendada — si en algún momento se prefiere la ruta oficial de Reddit, hay que solicitar el acceso ya, porque el trámite tarda semanas.

### 8.2 Agent Reach corre en WSL2, no en Windows nativo

Confirmado el 5-ago-2026: Agent Reach depende internamente de scripts bash (`transcribe.sh`, etc.) con supuestos POSIX (usa `bc`, rutas estilo Unix) que **están rotos en Windows nativo/Git Bash** — hay un issue abierto ese mismo día ([#566](https://github.com/Panniantong/agent-reach/issues/566)) reportando 8 problemas, incluyendo `doctor` devolviendo estado nulo para las plataformas que requieren login. El repositorio no tiene ni un solo archivo `.ps1`/`.bat`, solo `.sh`.

**Solución**: correr Agent Reach dentro de **WSL2** (Ubuntu), no directamente en PowerShell/CMD. El resto del sistema (bot de Telegram, MCP de Robinhood, LLM, RAG) sigue corriendo nativo en Windows — solo esta pieza específica vive en WSL2, y se comunica con el resto del proceso vía CLI (`wsl -d Ubuntu -- agent-reach ...`) o un pequeño puente HTTP si se necesita invocarlo desde el proceso Node.js principal.

**Instalador**: [`install.ps1`](./install.ps1) en la raíz del repo automatiza esto — detecta si falta WSL2 y lo instala (`wsl --install`, puede pedir reinicio), luego instala Agent Reach dentro de la distro (Python 3.10+, pipx, `agent-reach install --env=auto`, `agent-reach doctor`). El paso de configurar Twitter/Reddit (requieren cookie/sesión de una cuenta real, no una API key) queda deliberadamente manual — no se debe automatizar a ciegas el manejo de credenciales de sesión de otra plataforma; se le indica al usuario correr `agent-reach configure` él mismo dentro de WSL.

---

## 9. Riesgos y disclaimers a tener presentes

- **No hay sandbox en Robinhood.** Las primeras pruebas del sistema completo deben hacerse con capital mínimo real en la sub-cuenta aislada.
- **El stop-loss vía el MCP oficial no está confirmado** — probarlo en vivo antes de depender de él; tener el stop-loss sintético como respaldo desde el día uno.
- **El OAuth de Robinhood hoy solo soporta callback `localhost`** — al instalar el sistema en su propia PC (sección 6.5) esto ya no es un problema, pero la autorización inicial sigue requiriendo su presencia/participación (su login + su teléfono con la app de Robinhood).
- **Copytrading hacia cuentas de terceros (más allá de tu única persona de confianza, o si empieza a haber cobro) implica riesgo regulatorio serio** (posible necesidad de registro como asesor de inversiones) — el marco actual (sin cobro, una sola persona) se sostiene, pero re-evaluar si esto crece.
- **La política de Anthropic sobre uso de suscripción para agentes de terceros ha cambiado 5 veces en 2026** — nota: con el requisito de gratuidad confirmado, esto queda mayormente sin efecto (ya no se usa Claude de pago ni por suscripción para producción), pero se deja documentado por si el presupuesto cambia en el futuro.
- **La política de uso prohibido de Gemini restringe explícitamente pipelines automatizados sin supervisión humana en dominios financieros** — el nivel gratuito de Gemini es parte del stack recomendado en la sección 8; el patrón de aprobación humana por Telegram antes de cualquier orden real ayuda a cumplir con esto, pero léela completa antes de depender de Gemini en producción. Los niveles gratuitos en general (Gemini, Groq, OpenRouter) pueden reducirse o revocarse sin aviso — diseñar el sistema para degradar con gracia (sección 8.1), no para asumir disponibilidad garantizada.
- **La regla PDT y otros cambios regulatorios recientes (jun-2026) necesitan verificación con fuente primaria** antes de que el sistema asuma ciertos límites de day-trading.
- **Nada de esto es asesoría financiera ni asesoría legal.** El sistema que se construya no debe presentarse como asesoría profesional a tu familiar/amigo; conviene dejar por escrito (aunque sea informal) que es un experimento sin garantías.
- **Reproducibilidad de resultados de papers de trading con LLM es baja** (0/19 estudios auditados fueron completamente reproducibles) — cualquier cifra de retorno de los frameworks mencionados debe tratarse como orientativa, no como garantía.
- **Riesgo de look-ahead bias** en el pipeline RAG si las noticias se indexan con timestamp de publicación en lugar de timestamp de disponibilidad real — vigilar esto al construir el backtester.

---

## 10. Próximos pasos sugeridos

1. **Averiguar qué GPU tiene la PC de tu familiar/amigo** — determina si la inferencia local (respaldo gratuito real, sección 8) es viable o si hay que depender por completo de la rotación entre Groq/Gemini/OpenRouter.
2. Conseguir el consentimiento por escrito de tu familiar/amigo (aunque sea un mensaje/correo simple) antes de tocar su cuenta — ver plantilla de puntos en la sección 6.4.
3. Confirmar con él si su PC va a quedarse encendida de forma continua (para uptime alto) o si el bot es más bien algo que se revisa cuando la prende — esto decide si vale la pena configurar arranque automático (sección 6.5) desde el día uno.
4. Coordinar el momento de la autorización OAuth inicial en su propia PC (necesita su teléfono con la app de Robinhood y su login — sección 6.2/6.5) y decidir cómo se cifra el token en su disco (`@napi-rs/keyring`).
5. Hacer una prueba en vivo mínima del MCP de Robinhood (`review_equity_order` / `place_equity_order`) específicamente para confirmar si acepta `order_type=stop_loss` — esto determina si se necesita el stop-loss sintético desde el inicio.
6. Confirmar alcance inicial: ¿solo acciones (lo que ya cubre el MCP de Robinhood) o también cripto (requeriría integrar además la Crypto Trading API por separado)?
7. Configurar la rotación entre proveedores de LLM gratuitos (Groq/Gemini/OpenRouter) con lógica de reintento y espaciado de peticiones para no chocar contra los límites por minuto en los picos de apertura de mercado (sección 8.1).
8. Instalar y probar SearXNG autohospedado (Docker) y evaluar Agent Reach para sentimiento social — y, en paralelo, iniciar la solicitud de acceso a la API oficial de Reddit si se prefiere esa vía a futuro (tarda 2-4 semanas en aprobarse).
9. Definir el mecanismo de monitoreo remoto y actualización de código (sección 6.5) antes de dejarlo operando con dinero real sin que estés presente.
10. Prototipar el flujo Telegram (polling) → confirmación → Robinhood MCP de punta a punta con una sola señal simulada, corriendo ya en su PC, antes de construir el pipeline RAG y de análisis técnico completos.
11. Si esto llegara a crecer más allá de esta única persona de confianza sin cobro (más personas, o cualquier forma de compensación), volver a evaluar el ángulo regulatorio — idealmente con una consulta legal puntual — antes de escalarlo.
