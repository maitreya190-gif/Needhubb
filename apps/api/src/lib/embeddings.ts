/**
 * Semantic embeddings for feed ranking.
 *
 * We use Cohere's `embed-english-light-v3.0` (384-dim) via the free tier.
 * Vectors are cached in-memory by the text they were computed from — the
 * cache survives the process lifetime but not restarts, which is fine
 * because Cohere is fast enough to re-warm on demand.
 *
 * If COHERE_API_KEY is missing, `embedBatch` returns null and the caller
 * falls back to the substring-heuristic scorer. This keeps the app working
 * offline / on cold-start / on quota exhaustion.
 */

const COHERE_API_KEY = process.env.COHERE_API_KEY
const COHERE_MODEL = process.env.COHERE_MODEL ?? 'embed-english-light-v3.0'
const cohereAvailable = !!COHERE_API_KEY

const cache = new Map<string, number[]>()
const CACHE_MAX = 5000 // simple bound; LRU is overkill at demo scale

function cacheSet(key: string, value: number[]) {
  if (cache.size >= CACHE_MAX) {
    const first = cache.keys().next().value
    if (first) cache.delete(first)
  }
  cache.set(key, value)
}

/**
 * Batch-embed a list of texts. Returns an array of vectors in the same order,
 * or null if Cohere is unavailable (missing key, network error, or quota).
 *
 * `inputType` should be:
 *   - 'search_document' for content that will be searched over (needs, profiles)
 *   - 'search_query'    for the current query vector (user profile signal)
 * Cohere's v3 models are asymmetric — matching the type matters for quality.
 */
export async function embedBatch(
  texts: string[],
  inputType: 'search_document' | 'search_query',
): Promise<number[][] | null> {
  if (!cohereAvailable || texts.length === 0) return null

  // Normalize input to reduce cache misses.
  const normalized = texts.map((t) => t.trim().toLowerCase().slice(0, 2000))

  // Partition into cache hits vs misses.
  const missingIdx: number[] = []
  const missingTexts: string[] = []
  for (let i = 0; i < normalized.length; i++) {
    const key = cacheKey(normalized[i], inputType)
    if (!cache.has(key)) {
      missingIdx.push(i)
      missingTexts.push(normalized[i])
    }
  }

  if (missingTexts.length > 0) {
    try {
      const res = await fetch('https://api.cohere.com/v2/embed', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${COHERE_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          texts: missingTexts,
          model: COHERE_MODEL,
          input_type: inputType,
          embedding_types: ['float'],
        }),
      })
      if (!res.ok) {
        console.error('[embeddings] Cohere failed', res.status, await res.text().catch(() => ''))
        return null
      }
      const j = (await res.json()) as { embeddings: { float: number[][] } }
      const vectors = j.embeddings?.float
      if (!Array.isArray(vectors) || vectors.length !== missingTexts.length) {
        console.error('[embeddings] Cohere returned unexpected shape')
        return null
      }
      missingTexts.forEach((t, i) => {
        cacheSet(cacheKey(t, inputType), vectors[i])
      })
    } catch (err) {
      console.error('[embeddings] Cohere network error', err)
      return null
    }
  }

  return normalized.map((t) => cache.get(cacheKey(t, inputType))!)
}

function cacheKey(text: string, inputType: string): string {
  return `${inputType}::${text}`
}

/** Cosine similarity in [-1, 1]. Both vectors must be the same length. */
export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) return 0
  let dot = 0
  let normA = 0
  let normB = 0
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  }
  if (normA === 0 || normB === 0) return 0
  return dot / (Math.sqrt(normA) * Math.sqrt(normB))
}

/** Combine a need's textual signal into one embedding-input string. */
export function needSignalText(need: {
  title: string
  description: string
  earnCategory?: string | null
  connectCategory?: string | null
}): string {
  const parts = [
    need.title,
    need.description,
    need.earnCategory ?? '',
    need.connectCategory ?? '',
  ].filter(Boolean)
  return parts.join(' — ')
}

/**
 * Combine a user's profile into a search-query string.
 * Order: interests > skills > bio > prompts. Interests carry the most weight
 * for the "what do they want to find" signal.
 */
export function userSignalText(profile: {
  bio?: string | null
  promptSkill?: string | null
  promptCollab?: string | null
  promptNeed?: string | null
  interests: { interest: { label: string } }[]
  skills: { skill: { label: string } }[]
}): string {
  const interestLabels = profile.interests.map((i) => i.interest.label)
  const skillLabels = profile.skills.map((s) => s.skill.label)
  const parts = [
    interestLabels.length ? `Interests: ${interestLabels.join(', ')}.` : '',
    skillLabels.length ? `Skills: ${skillLabels.join(', ')}.` : '',
    profile.bio ?? '',
    profile.promptNeed ? `Looking for: ${profile.promptNeed}` : '',
    profile.promptCollab ? `Collab: ${profile.promptCollab}` : '',
    profile.promptSkill ? `Best at: ${profile.promptSkill}` : '',
  ].filter((s) => s && s.trim().length > 0)
  return parts.join(' ')
}

export const embeddingsAvailable = () => cohereAvailable
