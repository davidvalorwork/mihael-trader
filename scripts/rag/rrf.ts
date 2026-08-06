/**
 * Reciprocal Rank Fusion — combina varios rankings (p. ej. BM25 y vectores
 * densos) en uno solo, sin necesitar que las escalas de score sean
 * comparables entre sí. Ver INVESTIGACION.md sección 1.2.
 */
export type RankedItem = { id: string; score: number };

export function reciprocalRankFusion(rankings: RankedItem[][], k = 60): RankedItem[] {
  const fused = new Map<string, number>();
  for (const ranking of rankings) {
    const sorted = [...ranking].sort((a, b) => b.score - a.score);
    sorted.forEach((item, rank) => {
      const contribution = 1 / (k + rank + 1);
      fused.set(item.id, (fused.get(item.id) ?? 0) + contribution);
    });
  }
  return Array.from(fused.entries())
    .map(([id, score]) => ({ id, score }))
    .sort((a, b) => b.score - a.score);
}
