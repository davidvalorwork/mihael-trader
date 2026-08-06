/**
 * Re-ranking local con un cross-encoder BGE (ONNX, sin API, sin costo). El
 * modelo recomendado en INVESTIGACION.md (`bge-reranker-v2-m3`) NO tiene
 * conversión ONNX publicada — verificado el 5-ago-2026. Se usa en su lugar
 * `Xenova/bge-reranker-base`, confirmado funcionando en vivo.
 */
import { AutoModelForSequenceClassification, AutoTokenizer } from "@huggingface/transformers";

export const RERANKER_MODEL_ID = "Xenova/bge-reranker-base";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let modelPromise: Promise<{ tokenizer: any; model: any }> | null = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getModel(): Promise<{ tokenizer: any; model: any }> {
  if (!modelPromise) {
    modelPromise = Promise.all([
      AutoTokenizer.from_pretrained(RERANKER_MODEL_ID),
      AutoModelForSequenceClassification.from_pretrained(RERANKER_MODEL_ID, {
        dtype: "q8",
      }),
    ]).then(([tokenizer, model]) => ({ tokenizer, model }));
  }
  return modelPromise;
}

/** Devuelve un score de relevancia (mayor = más relevante) por documento, en el mismo orden que `documents`. */
export async function rerank(query: string, documents: string[]): Promise<number[]> {
  if (documents.length === 0) return [];
  const { tokenizer, model } = await getModel();
  const scores: number[] = [];
  for (const doc of documents) {
    const inputs = tokenizer([query], { text_pair: [doc], padding: true, truncation: true });
    const { logits } = await model(inputs);
    scores.push((logits.data as Float32Array)[0]);
  }
  return scores;
}
