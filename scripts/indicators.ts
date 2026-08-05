#!/usr/bin/env node
/**
 * Calcula indicadores tecnicos de forma deterministica (matematica real via
 * `trading-signals`) a partir de una serie de precios — nunca los calcula
 * un LLM. Ver INVESTIGACION.md secciones 2.3/2.4.
 *
 * Uso:
 *   echo '[100, 101, 99.5, ...]' | npm run indicators
 *   npm run indicators -- --file precios.json
 *
 * Entrada (JSON, por stdin o --file): number[] (solo cierres) o
 * { close: number, high?: number, low?: number, volume?: number }[]
 *
 * Salida (JSON por stdout): valores de cada indicador, o null si aun no hay
 * suficientes datos ("isStable" == false) — nunca un numero inventado.
 */
import { readFileSync } from "node:fs";
import { RSI, SMA, EMA, MACD, BollingerBands, ATR } from "trading-signals";

type Candle = { close: number; high?: number; low?: number; volume?: number };

function readStdin(): string {
  return readFileSync(0, "utf-8");
}

function parseInput(raw: string): Candle[] {
  const data = JSON.parse(raw);
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error("La entrada debe ser un array no vacío de precios o velas OHLC.");
  }
  return data.map((item: unknown) =>
    typeof item === "number" ? { close: item } : (item as Candle)
  );
}

function computeIndicators(candles: Candle[]) {
  const rsi14 = new RSI(14);
  const sma20 = new SMA(20);
  const ema20 = new EMA(20);
  const macd = new MACD(new EMA(12), new EMA(26), new EMA(9));
  const bb20 = new BollingerBands(20, 2);
  const hasHighLow = candles.every((c) => c.high !== undefined && c.low !== undefined);
  const atr14 = hasHighLow ? new ATR(14) : null;

  for (const c of candles) {
    rsi14.add(c.close);
    sma20.add(c.close);
    ema20.add(c.close);
    macd.add(c.close);
    bb20.add(c.close);
    if (atr14 && c.high !== undefined && c.low !== undefined) {
      atr14.add({ high: c.high, low: c.low, close: c.close });
    }
  }

  const safe = <T>(fn: () => T): T | null => {
    try {
      return fn();
    } catch {
      return null; // no hay suficientes datos todavia — nunca inventar un valor
    }
  };

  return {
    inputCandles: candles.length,
    rsi14: safe(() => rsi14.getResultOrThrow()),
    sma20: safe(() => sma20.getResultOrThrow()),
    ema20: safe(() => ema20.getResultOrThrow()),
    macd_12_26_9: safe(() => macd.getResultOrThrow()),
    bollingerBands_20_2: safe(() => bb20.getResultOrThrow()),
    atr14: atr14 ? safe(() => atr14.getResultOrThrow()) : "no disponible: faltan high/low en la entrada",
  };
}

function main() {
  const fileArgIndex = process.argv.indexOf("--file");
  const raw =
    fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
      ? readFileSync(process.argv[fileArgIndex + 1], "utf-8")
      : readStdin();

  const candles = parseInput(raw);
  const result = computeIndicators(candles);
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}

main();
