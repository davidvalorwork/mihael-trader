/**
 * Cliente de Qdrant (vector DB autohospedada, ver INVESTIGACION.md sección
 * 8). Qdrant exige que el id de un punto sea un entero sin signo o un UUID
 * — no un string arbitrario (verificado en vivo el 5-ago-2026) — por eso
 * derivamos un UUID determinístico del id real del chunk (hash SHA-1) y
 * guardamos el id original en el payload para poder recuperarlo.
 */
import { createHash } from "node:crypto";
import { QdrantClient } from "@qdrant/js-client-rest";
import { EMBEDDING_DIM } from "./embeddings.js";

const QDRANT_URL = process.env.QDRANT_URL ?? "http://localhost:6333";
const COLLECTION = "mihael_trader_chunks";

export const client = new QdrantClient({ url: QDRANT_URL });

export function toPointId(id: string): string {
  const hash = createHash("sha1").update(id).digest("hex").slice(0, 32);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}

let collectionEnsured = false;
export async function ensureCollection(): Promise<void> {
  if (collectionEnsured) return;
  const { collections } = await client.getCollections();
  if (!collections.some((c) => c.name === COLLECTION)) {
    await client.createCollection(COLLECTION, {
      vectors: { size: EMBEDDING_DIM, distance: "Cosine" },
    });
  }
  collectionEnsured = true;
}

export type UpsertInput = {
  id: string;
  vector: number[];
  payload: Record<string, unknown>;
};

export async function upsertChunks(points: UpsertInput[]): Promise<void> {
  if (points.length === 0) return;
  await ensureCollection();
  await client.upsert(COLLECTION, {
    points: points.map((p) => ({
      id: toPointId(p.id),
      vector: p.vector,
      payload: { ...p.payload, originalId: p.id },
    })),
  });
}

export type DenseResult = {
  id: string;
  score: number;
  payload: Record<string, unknown>;
};

export async function searchDense(vector: number[], limit = 20): Promise<DenseResult[]> {
  await ensureCollection();
  const { points } = await client.query(COLLECTION, { query: vector, limit, with_payload: true });
  return points.map((r) => ({
    id: String((r.payload as Record<string, unknown> | undefined)?.originalId ?? r.id),
    score: r.score,
    payload: (r.payload as Record<string, unknown>) ?? {},
  }));
}
