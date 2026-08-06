#!/usr/bin/env node
/**
 * Ingiere documentos al pipeline RAG: los parte en chunks, calcula
 * embeddings (BGE-M3 local, sin API) y los guarda en Qdrant (búsqueda
 * densa) y en el corpus local (búsqueda BM25). Ver INVESTIGACION.md
 * secciones 1.2 y 8.
 *
 * Uso:
 *   echo '[{"id":"news-1","text":"...","metadata":{"ticker":"AAPL","source":"Finnhub","title":"...","publishedAt":"2026-08-05"}}]' | npm run rag:ingest
 *   npm run rag:ingest -- --file documentos.json
 *
 * La primera vez tarda más (descarga el modelo de embeddings, ~1GB).
 */
import { readFileSync } from "node:fs";
import { chunkDocuments, type SourceDocument } from "./chunk.js";
import { embed } from "./embeddings.js";
import { upsertChunks } from "./qdrant.js";
import { appendToCorpus } from "./corpus.js";

function readStdin(): string {
  return readFileSync(0, "utf-8");
}

async function main() {
  const fileArgIndex = process.argv.indexOf("--file");
  const raw =
    fileArgIndex !== -1 && process.argv[fileArgIndex + 1]
      ? readFileSync(process.argv[fileArgIndex + 1], "utf-8")
      : readStdin();

  const docs: SourceDocument[] = JSON.parse(raw);
  if (!Array.isArray(docs) || docs.length === 0) {
    throw new Error("La entrada debe ser un array no vacío de documentos {id, text, metadata?}.");
  }

  const chunks = chunkDocuments(docs);
  process.stderr.write(`Generados ${chunks.length} chunk(s) de ${docs.length} documento(s). Calculando embeddings...\n`);

  const vectors = await embed(chunks.map((c) => c.text));

  await upsertChunks(
    chunks.map((c, i) => ({
      id: c.id,
      vector: vectors[i],
      payload: {
        documentId: c.documentId,
        chunkIndex: c.chunkIndex,
        text: c.text,
        ...(c.metadata ?? {}),
      },
    }))
  );

  appendToCorpus(
    chunks.map((c) => ({ id: c.id, documentId: c.documentId, text: c.text, metadata: c.metadata }))
  );

  process.stdout.write(
    JSON.stringify({ ingested: chunks.length, documentIds: docs.map((d) => d.id) }, null, 2) + "\n"
  );
}

main().catch((err) => {
  process.stderr.write(`Error: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 1;
});
