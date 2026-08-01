/**
 * Semantic tagging of needs against the app's filter vocabulary.
 *
 * The problem this solves: a Need has no tags of its own — only `earnCategory` /
 * `connectCategory`, two enums with 11 coarse values between them. The mobile
 * filter chips are a ~28-label vocabulary of interests and skills (Flutter,
 * Chess, UI Design…). Those two vocabularies barely intersect, so filtering a
 * feed by chip never reliably matched anything.
 *
 * Here we assign each need the labels it is actually about, by comparing the
 * need's embedding to an embedding of each label. The feed then returns them as
 * `tags`, and the client can intersect chips against tags directly.
 *
 * This is deliberately cheap: `embedBatch` caches by text, so the vocabulary is
 * embedded once per process and each need's vector is usually already warm from
 * the ranking pass that ran moments earlier on the same request.
 *
 * It is also deliberately fail-safe: every failure path returns an empty Map.
 * A need with no tags filters exactly the way it did before this module existed,
 * so Cohere being down or unkeyed degrades the feed rather than breaking it.
 */

import { embedBatch, cosineSimilarity, embeddingsAvailable, needSignalText } from './embeddings'

/**
 * Minimum cosine similarity for a label to be attached to a need.
 *
 * Tuned against real feed data — see the tagging step in the runbook. Too low
 * and every need collects unrelated tags; too high and needs come back bare
 * and the filters look broken again. Exported so it can be adjusted without
 * touching the logic below.
 */
export const TAG_MIN_SIMILARITY = 0.28

/** Upper bound on tags per need, keeping the strongest. */
export const MAX_TAGS_PER_NEED = 5

/**
 * The label vocabulary, mirroring `_availableInterests` + `_availableSkills` in
 * `apps/mobile/lib/widgets/nh_filter_sheet.dart`. These strings are what the
 * client compares its chips against, so they must stay character-identical to
 * the chip labels — if you add a chip there, add it here.
 *
 * `hint` is what actually gets embedded. A bare label like "Dev" or "Art" is too
 * short and ambiguous to produce a useful vector, so each label carries a short
 * descriptive phrase. The hint is an implementation detail; only `label` is ever
 * returned to the client.
 */
interface TagLabel {
  label: string
  hint: string
}

export const TAG_VOCABULARY: TagLabel[] = [
  // ── Interests ────────────────────────────────────────────────────────────
  { label: 'Flutter', hint: 'Flutter and Dart mobile app development, widgets, state management' },
  { label: 'DSA', hint: 'data structures and algorithms, leetcode, competitive programming, coding interview prep' },
  { label: 'Coffee', hint: 'coffee, cafes, catching up over a drink' },
  { label: 'Startups', hint: 'startups, founders, entrepreneurship, building a product or company' },
  { label: 'Trekking', hint: 'trekking, hiking, trails, camping and the outdoors' },
  { label: 'Photography', hint: 'photography, photoshoots, cameras, photographing an event' },
  { label: 'Chess', hint: 'chess, board games, playing a match' },
  { label: 'Anime', hint: 'anime, manga, watching series together' },
  { label: 'Guitar', hint: 'guitar, playing and practising a musical instrument' },
  { label: 'Lifting', hint: 'weight lifting, gym, workouts, fitness training, a gym partner' },
  { label: 'Movies', hint: 'movies, films, cinema, watching something together' },
  { label: 'Cooking', hint: 'cooking, baking, recipes, preparing food' },
  { label: 'Art', hint: 'art, drawing, sketching, painting, creative visual work' },
  { label: 'Gaming', hint: 'video games, gaming, playing online together, esports' },
  { label: 'Science', hint: 'science, physics, chemistry, biology, research and experiments' },

  // ── Skills ───────────────────────────────────────────────────────────────
  { label: 'Tutoring', hint: 'tutoring, teaching, lessons, explaining a subject one on one' },
  { label: 'UI Design', hint: 'UI and UX design, interface design, figma, wireframes, product design' },
  { label: 'Java', hint: 'Java programming, spring, android development in Java' },
  { label: 'Python', hint: 'Python programming, scripting, data science, automation' },
  { label: 'Video editing', hint: 'video editing, premiere, after effects, cutting and editing footage' },
  { label: 'Writing', hint: 'writing, copywriting, essays, articles, content and blog writing' },
  { label: 'Math', hint: 'mathematics, calculus, algebra, statistics, solving maths problems' },
  { label: 'Music', hint: 'music, singing, producing, recording and performing' },
  { label: 'Repair', hint: 'repairing and fixing things, appliances, electronics, plumbing, maintenance' },
  { label: 'Note-taking', hint: 'note taking, lecture notes, summarising study material' },
  { label: 'Proofreading', hint: 'proofreading, editing and correcting written text, grammar review' },
  { label: 'Design', hint: 'graphic design, logos, posters, branding and visual assets' },
  { label: 'Dev', hint: 'software development, web development, coding, building an app or website' },
]

/** Shape needed to tag a need — matches what the feed already has in hand. */
export interface TaggableNeed {
  id: string
  title: string
  description: string
  earnCategory?: string | null
  connectCategory?: string | null
}

/**
 * Assign vocabulary labels to each need by embedding similarity.
 *
 * Returns a Map of need id → labels, strongest first. Needs that matched
 * nothing are simply absent from the Map. Returns an empty Map — never throws —
 * when embeddings are unavailable or anything goes wrong.
 */
export async function tagNeedsByEmbedding(
  needs: TaggableNeed[],
): Promise<Map<string, string[]>> {
  const result = new Map<string, string[]>()
  if (!embeddingsAvailable() || needs.length === 0) return result

  try {
    // 'search_document' on both sides: we are comparing content to content, and
    // it matches the input type the ranking pass already used for needs, so the
    // need vectors come back as cache hits rather than a second API call.
    const [labelVecs, needVecs] = await Promise.all([
      embedBatch(TAG_VOCABULARY.map((t) => t.hint), 'search_document'),
      embedBatch(needs.map((n) => needSignalText(n)), 'search_document'),
    ])
    if (!labelVecs || !needVecs) return result

    needs.forEach((need, i) => {
      const needVec = needVecs[i]
      if (!needVec) return

      const scored: { label: string; score: number }[] = []
      for (let j = 0; j < TAG_VOCABULARY.length; j++) {
        const score = cosineSimilarity(needVec, labelVecs[j])
        if (score >= TAG_MIN_SIMILARITY) {
          scored.push({ label: TAG_VOCABULARY[j].label, score })
        }
      }
      if (scored.length === 0) return

      scored.sort((a, b) => b.score - a.score)
      result.set(need.id, scored.slice(0, MAX_TAGS_PER_NEED).map((s) => s.label))
    })

    return result
  } catch (err) {
    // Tagging is an enhancement — the feed must still serve without it.
    console.error('[need-tagging] failed, serving feed untagged', err)
    return new Map()
  }
}
