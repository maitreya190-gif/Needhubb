import express, { Router } from 'express'
import { config } from '../../config'

export const translateRouter: Router = express.Router()

const LANG_NAMES: Record<string, string> = {
  en: 'English',
  hi: 'Hindi',
  bn: 'Bengali',
  te: 'Telugu',
  mr: 'Marathi',
  ta: 'Tamil',
  gu: 'Gujarati',
  kn: 'Kannada',
}

// All 10 Groq keys in one pool — round-robin distributes load and bypasses
// per-key rate limits. New keys wired via LLM_API_KEY_3..10 in .env.
const groqKeys = [
  config.llmApiKey,
  config.llmApiKey2,
  config.llmApiKey3,
  config.llmApiKey4,
  config.llmApiKey5,
  config.llmApiKey6,
  config.llmApiKey7,
  config.llmApiKey8,
  config.llmApiKey9,
  config.llmApiKey10,
].filter(Boolean)

let groqKeyCursor = 0

function nextKey(): string {
  const key = groqKeys[groqKeyCursor % groqKeys.length]
  groqKeyCursor++
  return key
}

async function callGroq(
  messages: { role: string; content: string }[],
  key: string,
): Promise<string | null> {
  const baseUrl = process.env.LLM_BASE_URL
  const model = config.translateModel
  if (!baseUrl || !key || !model) return null

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 12000)
  try {
    const r = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, temperature: 0.1, messages }),
    })
    if (r.ok) {
      const data = (await r.json()) as { choices?: { message?: { content?: string } }[] }
      return data.choices?.[0]?.message?.content?.trim() ?? null
    }
  } catch {
    // network / abort
  } finally {
    clearTimeout(timeout)
  }
  return null
}

// Try multiple keys on failure (up to 3 attempts). Exported for reuse by
// NeedHub Plus's AI posting insights (plus.router.ts) — same key pool, no
// duplicated key list, no behavior change to translation itself.
export async function callGroqWithFallback(
  messages: { role: string; content: string }[],
): Promise<string | null> {
  const attempts = Math.min(3, groqKeys.length)
  for (let i = 0; i < attempts; i++) {
    const result = await callGroq(messages, nextKey())
    if (result !== null) return result
  }
  return null
}

// Single string translation.
translateRouter.post('/', async (req, res) => {
  const { text, targetLang } = req.body as { text?: string; targetLang?: string }
  if (!text || typeof text !== 'string' || !text.trim()) return res.json({ translated: text ?? '' })
  if (!targetLang || !LANG_NAMES[targetLang] || targetLang === 'en') return res.json({ translated: text })

  const result = await callGroqWithFallback([
    {
      role: 'system',
      content: `You are a translator. Translate the user's text to ${LANG_NAMES[targetLang]}. Return ONLY the translated text — no explanations, no quotes, no markdown.`,
    },
    { role: 'user', content: text.slice(0, 2000) },
  ])
  return res.json({ translated: result || text })
})

// Batch translation — splits large batches across multiple keys in parallel
// so the personality test (~50 strings) completes in one parallel round-trip
// instead of several sequential ones.
translateRouter.post('/batch', async (req, res) => {
  const { texts, targetLang } = req.body as { texts?: unknown; targetLang?: string }
  if (!Array.isArray(texts) || texts.length === 0) return res.json({ translations: [] })
  if (!targetLang || !LANG_NAMES[targetLang] || targetLang === 'en') {
    return res.json({ translations: texts })
  }

  const safeTexts = (texts as unknown[])
    .slice(0, 500)
    .map((t) => (typeof t === 'string' ? t.slice(0, 500) : ''))

  const systemPrompt = `You are a translator. Translate the following JSON array of UI strings to ${LANG_NAMES[targetLang]}. Return ONLY a valid JSON array of the same length with translated strings in the same order. Preserve any {placeholder} tokens exactly as-is. No extra text.`

  // For small batches (≤ 30) or when only 1 key is available: single call.
  // For larger batches: split across up to 4 parallel keys for speed.
  const PARALLEL_THRESHOLD = 30
  const MAX_PARALLEL = Math.min(4, groqKeys.length)

  if (safeTexts.length <= PARALLEL_THRESHOLD || groqKeys.length <= 1) {
    const result = await callGroqWithFallback([
      { role: 'system', content: systemPrompt },
      { role: 'user', content: JSON.stringify(safeTexts) },
    ])
    return res.json({ translations: parseTranslations(result, safeTexts) })
  }

  // Split into equal chunks, fire in parallel.
  const chunkSize = Math.ceil(safeTexts.length / MAX_PARALLEL)
  const chunks: string[][] = []
  for (let i = 0; i < safeTexts.length; i += chunkSize) {
    chunks.push(safeTexts.slice(i, i + chunkSize))
  }

  const results = await Promise.all(
    chunks.map((chunk) =>
      callGroqWithFallback([
        { role: 'system', content: systemPrompt },
        { role: 'user', content: JSON.stringify(chunk) },
      ]).then((r) => parseTranslations(r, chunk)),
    ),
  )

  return res.json({ translations: results.flat() })
})

function parseTranslations(result: string | null, fallback: string[]): string[] {
  if (!result) return fallback
  try {
    const parsed = JSON.parse(result)
    if (Array.isArray(parsed) && parsed.length === fallback.length) {
      return parsed.map((e) => (typeof e === 'string' ? e : ''))
    }
  } catch {/* fall through */}
  return fallback
}
