#!/usr/bin/env node
/**
 * Gate de riesgo deterministico. Se debe correr SIEMPRE antes de llamar a
 * place_equity_order en el MCP de Robinhood — nunca decidir "esto esta bien"
 * solo con el criterio del LLM. Ver INVESTIGACION.md secciones 1.4 y 9.
 *
 * Uso:
 *   echo '{"symbol":"AAPL","side":"buy","quantity":1,"estimatedPrice":230}' | npm run risk-check
 *
 * Salida (JSON): { approved: boolean, reasons: string[], checkedAt: string }
 * No tiene efectos secundarios — solo lee config/risk-limits.json y
 * state/orders-log.json para contar. Registrar la orden real es trabajo de
 * scripts/log-order.ts, despues de que el MCP confirme la operacion.
 */
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const LIMITS_PATH = path.join(ROOT, "config", "risk-limits.json");
const LOG_PATH = path.join(ROOT, "state", "orders-log.json");

type ProposedOrder = {
  symbol: string;
  side: "buy" | "sell";
  quantity: number;
  estimatedPrice: number;
};

type LoggedOrder = {
  symbol: string;
  side: "buy" | "sell";
  quantity: number;
  notionalUsd: number;
  timestamp: string;
};

function readStdin(): string {
  return readFileSync(0, "utf-8");
}

function loadLimits() {
  return JSON.parse(readFileSync(LIMITS_PATH, "utf-8"));
}

function loadTodaysOrders(): LoggedOrder[] {
  if (!existsSync(LOG_PATH)) return [];
  const all: LoggedOrder[] = JSON.parse(readFileSync(LOG_PATH, "utf-8"));
  const today = new Date().toISOString().slice(0, 10);
  return all.filter((o) => o.timestamp.slice(0, 10) === today);
}

function main() {
  const fileArgIndex = process.argv.indexOf("--file");
  const raw =
    fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
      ? readFileSync(process.argv[fileArgIndex + 1], "utf-8")
      : readStdin();

  const order: ProposedOrder = JSON.parse(raw);
  const limits = loadLimits();
  const reasons: string[] = [];

  const notional = order.quantity * order.estimatedPrice;

  if (limits.allowedSymbols && !limits.allowedSymbols.includes(order.symbol)) {
    reasons.push(
      `El símbolo ${order.symbol} no está en allowedSymbols (config/risk-limits.json).`
    );
  }

  if (notional > limits.maxOrderNotionalUsd) {
    reasons.push(
      `Notional de la orden ($${notional.toFixed(2)}) supera maxOrderNotionalUsd ($${limits.maxOrderNotionalUsd}).`
    );
  }

  const todaysOrders = loadTodaysOrders();
  if (todaysOrders.length >= limits.maxDailyOrders) {
    reasons.push(
      `Ya se registraron ${todaysOrders.length} órdenes hoy (límite: ${limits.maxDailyOrders} en maxDailyOrders).`
    );
  }

  if (limits.requireReviewBeforePlace) {
    reasons.push(
      "RECORDATORIO (no bloqueante): llamar review_equity_order en el MCP de Robinhood antes de place_equity_order — no está garantizado por Robinhood a nivel de protocolo, es una convención de seguridad de este proyecto (ver INVESTIGACION.md 5.2)."
    );
  }

  const blockingReasons = reasons.filter((r) => !r.startsWith("RECORDATORIO"));
  const result = {
    approved: blockingReasons.length === 0,
    notionalUsd: Math.round(notional * 100) / 100,
    ordersTodayBeforeThis: todaysOrders.length,
    reasons,
    checkedAt: new Date().toISOString(),
  };

  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  if (!result.approved) process.exitCode = 1;
}

main();
