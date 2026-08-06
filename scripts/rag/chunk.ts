/**
 * Chunking consciente de estructura (INVESTIGACION.md sección 1.2): chunks de
 * ~1800 caracteres, con metadata del documento completo prepended a cada
 * chunk. Prefiere cortar en límite de párrafo/oración, nunca a mitad de
 * palabra si se puede evitar.
 */

export type SourceDocument = {
  id: string;
  text: string;
  metadata?: Record<string, string | number | undefined>;
};

export type Chunk = {
  id: string;
  documentId: string;
  chunkIndex: number;
  text: string;
  metadata?: Record<string, string | number | undefined>;
};

const DEFAULT_CHUNK_SIZE = 1800;

export function buildHeader(metadata: SourceDocument["metadata"]): string {
  if (!metadata) return "";
  const parts: string[] = [];
  if (metadata.title) parts.push(`Título: ${metadata.title}`);
  if (metadata.source) parts.push(`Fuente: ${metadata.source}`);
  if (metadata.ticker) parts.push(`Ticker: ${metadata.ticker}`);
  if (metadata.publishedAt) parts.push(`Publicado: ${metadata.publishedAt}`);
  return parts.join(" | ");
}

function splitText(text: string, chunkSize: number): string[] {
  const trimmed = text.trim();
  if (trimmed.length <= chunkSize) return [trimmed];

  const chunks: string[] = [];
  let rest = trimmed;
  while (rest.length > chunkSize) {
    const window = rest.slice(0, chunkSize);
    const para = window.lastIndexOf("\n\n");
    const sentence = window.lastIndexOf(". ");
    const space = window.lastIndexOf(" ");

    let cut: number;
    if (para > chunkSize * 0.5) cut = para;
    else if (sentence > chunkSize * 0.5) cut = sentence + 1;
    else if (space > 0) cut = space;
    else cut = chunkSize;

    chunks.push(rest.slice(0, cut).trim());
    rest = rest.slice(cut).trim();
  }
  if (rest) chunks.push(rest);
  return chunks;
}

export function chunkDocument(doc: SourceDocument, chunkSize = DEFAULT_CHUNK_SIZE): Chunk[] {
  const header = buildHeader(doc.metadata);
  const parts = splitText(doc.text, chunkSize);
  return parts.map((body, i) => ({
    id: `${doc.id}#${i}`,
    documentId: doc.id,
    chunkIndex: i,
    text: header ? `${header}\n\n${body}` : body,
    metadata: doc.metadata,
  }));
}

export function chunkDocuments(docs: SourceDocument[], chunkSize = DEFAULT_CHUNK_SIZE): Chunk[] {
  return docs.flatMap((d) => chunkDocument(d, chunkSize));
}
