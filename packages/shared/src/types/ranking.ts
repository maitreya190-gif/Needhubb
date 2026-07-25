export interface RankingWeights {
  relevance: number    // w1 — skill/interest overlap
  proximity: number    // w2 — distance
  freshness: number    // w3 — recency
  boost: number        // w4 — active visibility boost
  reputation: number   // w5 — small points tiebreaker
}

export const DEFAULT_WEIGHTS: RankingWeights = {
  relevance: 0.4,
  proximity: 0.3,
  freshness: 0.15,
  boost: 0.1,
  reputation: 0.05,
}
