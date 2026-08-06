/**
 * Embeddings locales via BGE-M3 (ONNX, corriendo en Node con transformers.js
 * — sin API, sin costo, sin Ollama). Verificado en vivo el 5-ago-2026:
 * modelo `Xenova/bge-m3`, 1024 dimensiones. Ver INVESTIGACION.md sección 8.
 *
 * La primera llamada descarga el modelo (~500MB-1GB, cuantizado) a
 * ~/.cache o al cache que use transformers.js — puede tardar; llamadas
 * siguientes son instantáneas.
 */
import { pipeline } from "@huggingface/transformers";

export const EMBEDDING_MODEL_ID = "Xenova/bge-m3";
export const EMBEDDING_DIM = 1024;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let extractorPromise: Promise<any> | null = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getExtractor(): Promise<any> {
  if (!extractorPromise) {
    extractorPromise = pipeline("feature-extraction", EMBEDDING_MODEL_ID, {
      dtype: "q8",
    });
  }
  return extractorPromise;
}

export async function embed(texts: string[]): Promise<number[][]> {
  if (texts.length === 0) return [];
  const extractor = await getExtractor();
  const vectors: number[][] = [];
  for (const text of texts) {
    const output = await extractor(text, { pooling: "mean", normalize: true });
    vectors.push(Array.from(output.data as Float32Array));
  }
  return vectors;
}

export async function embedOne(text: string): Promise<number[]> {
  const [vector] = await embed([text]);
  return vector;
}
