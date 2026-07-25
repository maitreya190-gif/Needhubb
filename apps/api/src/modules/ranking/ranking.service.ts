import type { RankingWeights } from '@needhub/shared'
import { DEFAULT_WEIGHTS } from '@needhub/shared'

interface RankInput {
  relevanceScore: number
  proximityScore: number  // 0–1, computed server-side (never exposes precise coords)
  freshnessScore: number
  hasActiveBoost: boolean
  reputationScore: number
}

export function computeRankScore(
  input: RankInput,
  weights: RankingWeights = DEFAULT_WEIGHTS,
): number {
  const { relevance: w1, proximity: w2, freshness: w3, boost: w4, reputation: w5 } = weights
  return (
    w1 * input.relevanceScore +
    w2 * input.proximityScore +
    w3 * input.freshnessScore +
    w4 * (input.hasActiveBoost ? 1 : 0) +
    w5 * input.reputationScore
  )
}
