/**
 * Corpus local para la mitad BM25 de la búsqueda híbrida (INVESTIGACION.md
 * sección 1.2). A escala personal (unos pocos miles de chunks) es
 * suficiente reconstruir el índice BM25 en memoria en cada búsqueda — nada
 * de infraestructura extra.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

// wink-bm25-text-search / wink-nlp-utils son CommonJS puro — createRequire
// evita depender de que el interop ESM de tsx/esbuild las resuelva bien.
const require = createRequire(import.meta.url);
const BM25 = require("wink-bm25-text-search");
const winkUtils = require("wink-nlp-utils");

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const CORPUS_PATH = path.join(ROOT, "state", "rag", "corpus.jsonl");

export type CorpusRecord = {
  id: string;
  documentId: string;
  text: string;
  metadata?: Record<string, unknown>;
};

export function loadCorpus(): CorpusRecord[] {
  if (!existsSync(CORPUS_PATH)) return [];
  const raw = readFileSync(CORPUS_PATH, "utf-8");
  return raw
    .split("\n")
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line) as CorpusRecord);
}

export function appendToCorpus(records: CorpusRecord[]): void {
  if (records.length === 0) return;
  const dir = path.dirname(CORPUS_PATH);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const existing = loadCorpus();
  const byId = new Map(existing.map((r) => [r.id, r]));
  for (const r of records) byId.set(r.id, r); // upsert: mismo id = reemplaza

  const lines = Array.from(byId.values()).map((r) => JSON.stringify(r));
  writeFileSync(CORPUS_PATH, lines.join("\n") + "\n");
}

export function searchBm25(query: string, limit = 20): { id: string; score: number }[] {
  const records = loadCorpus();
  if (records.length === 0) return [];

  const engine = BM25();
  engine.defineConfig({ fldWeights: { body: 1 } });
  engine.definePrepTasks([winkUtils.string.lowerCase, winkUtils.string.tokenize0]);
  for (const r of records) engine.addDoc({ body: r.text }, r.id);
  engine.consolidate();

  const results = engine.search(query) as [string, number][];
  return results.slice(0, limit).map(([id, score]) => ({ id, score }));
}
