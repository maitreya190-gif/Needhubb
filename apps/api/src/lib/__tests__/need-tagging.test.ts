/**
 * Tagging must never be able to break the feed. Cohere is a free-tier
 * dependency that can be unkeyed, rate-limited or simply down, and when that
 * happens the correct behaviour is an untagged feed — not a 500.
 *
 * These tests stub only the network call (`embedBatch`); the cosine maths and
 * the threshold/cap logic under test are the real ones.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  embedBatch: vi.fn(),
  embeddingsAvailable: vi.fn(() => true),
}))

vi.mock('../embeddings', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../embeddings')>()
  return {
    ...actual,
    embedBatch: mocks.embedBatch,
    embeddingsAvailable: mocks.embeddingsAvailable,
  }
})

import {
  tagNeedsByEmbedding,
  TAG_VOCABULARY,
  TAG_MIN_SIMILARITY,
  MAX_TAGS_PER_NEED,
} from '../need-tagging'

const DIM = TAG_VOCABULARY.length

/** Unit vector pointing at label `j`, so cosine with that label is exactly 1. */
function basis(j: number): number[] {
  return Array.from({ length: DIM }, (_, i) => (i === j ? 1 : 0))
}

/** Vector weighted across several labels: index -> weight. */
function weighted(weights: Record<number, number>): number[] {
  return Array.from({ length: DIM }, (_, i) => weights[i] ?? 0)
}

/** Each label embeds to its own basis vector, so similarities are exact. */
const LABEL_VECTORS = TAG_VOCABULARY.map((_, j) => basis(j))

function makeNeed(id: string) {
  return { id, title: `Need ${id}`, description: 'desc', earnCategory: null, connectCategory: null }
}

/** Route the two embedBatch calls: the vocabulary batch vs the needs batch. */
function stubEmbeddings(needVectors: number[][] | null) {
  mocks.embedBatch.mockImplementation((texts: string[]) => {
    const isVocabulary =
      texts.length === TAG_VOCABULARY.length && texts[0] === TAG_VOCABULARY[0].hint
    return Promise.resolve(isVocabulary ? LABEL_VECTORS : needVectors)
  })
}

beforeEach(() => {
  mocks.embedBatch.mockReset()
  mocks.embeddingsAvailable.mockReset()
  mocks.embeddingsAvailable.mockReturnValue(true)
})

describe('tagNeedsByEmbedding — degrades instead of failing', () => {
  it('returns nothing when Cohere is not configured, without calling it', async () => {
    mocks.embeddingsAvailable.mockReturnValue(false)
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.size).toBe(0)
    expect(mocks.embedBatch).not.toHaveBeenCalled()
  })

  it('returns nothing for an empty feed', async () => {
    const result = await tagNeedsByEmbedding([])
    expect(result.size).toBe(0)
    expect(mocks.embedBatch).not.toHaveBeenCalled()
  })

  it('returns nothing when embedding yields null (quota or HTTP failure)', async () => {
    stubEmbeddings(null)
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.size).toBe(0)
  })

  it('swallows a network rejection rather than propagating it', async () => {
    mocks.embedBatch.mockRejectedValue(new Error('ECONNRESET'))
    await expect(tagNeedsByEmbedding([makeNeed('a')])).resolves.toEqual(new Map())
  })
})

describe('tagNeedsByEmbedding — label assignment', () => {
  it('assigns the label a need actually matches', async () => {
    stubEmbeddings([basis(0)])
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.get('a')).toEqual([TAG_VOCABULARY[0].label])
  })

  it('omits needs that match nothing above the threshold', async () => {
    stubEmbeddings([Array.from({ length: DIM }, () => 0)])
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.has('a')).toBe(false)
  })

  it('drops labels below TAG_MIN_SIMILARITY', async () => {
    // Dominated by label 0; label 1 sits well under the threshold.
    const weak = TAG_MIN_SIMILARITY / 4
    stubEmbeddings([weighted({ 0: 1, 1: weak })])
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.get('a')).toEqual([TAG_VOCABULARY[0].label])
  })

  it('orders labels strongest first', async () => {
    stubEmbeddings([weighted({ 0: 3, 1: 2.5, 2: 2 })])
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.get('a')).toEqual([
      TAG_VOCABULARY[0].label,
      TAG_VOCABULARY[1].label,
      TAG_VOCABULARY[2].label,
    ])
  })

  it('caps a broadly-matching need at MAX_TAGS_PER_NEED', async () => {
    // Equal weight across 7 labels — each scores 1/sqrt(7) ≈ 0.38, all above
    // the threshold, so the cap is the only thing limiting the result.
    const spread: Record<number, number> = {}
    for (let i = 0; i < 7; i++) spread[i] = 1
    stubEmbeddings([weighted(spread)])
    const result = await tagNeedsByEmbedding([makeNeed('a')])
    expect(result.get('a')).toHaveLength(MAX_TAGS_PER_NEED)
  })

  it('tags each need independently in a batch', async () => {
    stubEmbeddings([basis(0), basis(1)])
    const result = await tagNeedsByEmbedding([makeNeed('a'), makeNeed('b')])
    expect(result.get('a')).toEqual([TAG_VOCABULARY[0].label])
    expect(result.get('b')).toEqual([TAG_VOCABULARY[1].label])
  })
})

describe('TAG_VOCABULARY', () => {
  it('has no duplicate labels — a duplicate would double-count a chip', () => {
    const labels = TAG_VOCABULARY.map((t) => t.label)
    expect(new Set(labels).size).toBe(labels.length)
  })

  it('gives every label a hint substantial enough to embed', () => {
    for (const { label, hint } of TAG_VOCABULARY) {
      expect(hint.length, `hint for "${label}"`).toBeGreaterThan(label.length)
    }
  })
})
