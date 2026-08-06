#!/usr/bin/env node
/**
 * Busqueda hibrida sobre el pipeline RAG: BM25 (terminos exactos) + vectores
 * densos (Qdrant), fusionados con RRF, y refinados con un reranker local.
 * Ver INVESTIGACION.md secciones 1.2 y 8. Nunca inventa resultados — si el
 * corpus esta vacio o no hay coincidencias, devuelve results: [].
 *
 * Uso:
 *   echo '{"query":"resultados trimestrales AAPL","limit":5}' | npm run rag:search
 */
import { readFileSync } from "node:fs";
import { embedOne } from "./embeddings.js";
import { searchDense } from "./qdrant.js";
import { loadCorpus, searchBm25 } from "./corpus.js";
import { reciprocalRankFusion } from "./rrf.js";
import { rerank } from "./reranker.js";

function readStdin(): string {
  return readFileSync(0, "utf-8");
}

async function main() {
  const fileArgIndex = process.argv.indexOf("--file");
  const raw =
    fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
      ? readFileSync(process.argv[fileArgIndex + 1], "utf-8")
      : readStdin();

  const { query, limit = 5 } = JSON.parse(raw) as { query: string; limit?: number };
  if (!query) throw new Error("Falta 'query'.");

  const bm25Results = searchBm25(query, 20);
  const denseVector = await embedOne(query);
  const denseResults = await searchDense(denseVector, 20);

  const fused = reciprocalRankFusion([
    bm25Results,
    denseResults.map((r) => ({ id: r.id, score: r.score })),
  ]);
  const candidateIds = fused.slice(0, 20).map((f) => f.id);

  const corpus = loadCorpus();
  const byId = new Map(corpus.map((r) => [r.id, r]));
  const candidates = candidateIds
    .map((id) => byId.get(id))
    .filter((c): c is NonNullable<typeof c> => c !== undefined);

  if (candidates.length === 0) {
    process.stdout.write(JSON.stringify({ query, results: [] }, null, 2) + "\n");
    return;
  }

  const rerankScores = await rerank(query, candidates.map((c) => c.text));
  const ranked = candidates
    .map((c, i) => ({ ...c, rerankScore: rerankScores[i] }))
    .sort((a, b) => b.rerankScore - a.rerankScore)
    .slice(0, limit);

  process.stdout.write(
    JSON.stringify(
      {
        query,
        results: ranked.map((r) => ({
          id: r.id,
          documentId: r.documentId,
          text: r.text,
          metadata: r.metadata,
          rerankScore: r.rerankScore,
        })),
      },
      null,
      2
    ) + "\n"
  );
}

main().catch((err) => {
  process.stderr.write(`Error: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
