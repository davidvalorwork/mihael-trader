#!/usr/bin/env node
/**
 * Registra una orden YA EJECUTADA (confirmada por el MCP de Robinhood) en el
 * log de auditoria local. Correr esto despues de place_equity_order, nunca
 * antes — el chequeo previo lo hace scripts/risk-check.ts sin efectos
 * secundarios. Ver INVESTIGACION.md sección 1.4 (guardrails: "registro de
 * auditoría de cada acción aprobada").
 *
 * Uso:
 *   echo '{"symbol":"AAPL","side":"buy","quantity":1,"notionalUsd":230.10,"robinhoodOrderId":"..."}' | npm run log-order
 */
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const STATE_DIR = path.join(ROOT, "state");
const LOG_PATH = path.join(STATE_DIR, "orders-log.json");

function readStdin(): string {
  return readFileSync(0, "utf-8");
}

function main() {
  const fileArgIndex = process.argv.indexOf("--file");
  const raw =
    fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
      ? readFileSync(process.argv[fileArgIndex + 1], "utf-8")
      : readStdin();

  const order = JSON.parse(raw);
  if (!order.symbol || !order.side || !order.quantity) {
    throw new Error("Se requieren al menos: symbol, side, quantity.");
  }

  if (!existsSync(STATE_DIR)) mkdirSync(STATE_DIR, { recursive: true });
  const existing = existsSync(LOG_PATH) ? JSON.parse(readFileSync(LOG_PATH, "utf-8")) : [];

  const entry = { ...order, timestamp: new Date().toISOString() };
  existing.push(entry);
  writeFileSync(LOG_PATH, JSON.stringify(existing, null, 2));

  process.stdout.write(JSON.stringify({ logged: true, entry }, null, 2) + "\n");
}

main();
