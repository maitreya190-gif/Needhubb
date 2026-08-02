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

async function callGroq(messages: { role: string; content: string }[]): Promise<string | null> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = config.llmApiKey
  const model = config.llmModel
  if (!baseUrl || !key || !model) return null

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 15000)
  try {
    const r = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, temperature: 0.1, messages }),
    })
    if (!r.ok) return null
    const data = (await r.json()) as { choices?: { message?: { content?: string } }[] }
    return data.choices?.[0]?.message?.content?.trim() ?? null
  } catch {
    return null
  } finally {
    clearTimeout(timeout)
  }
}

// Single string — no auth, rate-limited at mount site
translateRouter.post('/', async (req, res) => {
  const { text, targetLang } = req.body as { text?: string; targetLang?: string }
  if (!text || typeof text !== 'string' || !text.trim()) return res.json({ translated: text ?? '' })
  if (!targetLang || !LANG_NAMES[targetLang] || targetLang === 'en') return res.json({ translated: text })

  const result = await callGroq([
    {
      role: 'system',
      content: `You are a translator. Translate the user's text to ${LANG_NAMES[targetLang]}. Return ONLY the translated text — no explanations, no quotes, no markdown.`,
    },
    { role: 'user', content: text.slice(0, 2000) },
  ])
  return res.json({ translated: result || text })
})

// Batch — translate an array of strings in ONE Groq call (efficient for UI localisation)
translateRouter.post('/batch', async (req, res) => {
  const { texts, targetLang } = req.body as { texts?: unknown; targetLang?: string }
  if (!Array.isArray(texts) || texts.length === 0) return res.json({ translations: [] })
  if (!targetLang || !LANG_NAMES[targetLang] || targetLang === 'en') {
    return res.json({ translations: texts })
  }

  const safeTexts = (texts as unknown[])
    .slice(0, 500)
    .map((t) => (typeof t === 'string' ? t.slice(0, 500) : ''))

  const result = await callGroq([
    {
      role: 'system',
      content: `You are a translator. Translate the following JSON array of UI strings to ${LANG_NAMES[targetLang]}. Return ONLY a valid JSON array of the same length with translated strings in the same order. Preserve any {placeholder} tokens exactly as-is. No extra text.`,
    },
    { role: 'user', content: JSON.stringify(safeTexts) },
  ])

  if (!result) return res.json({ translations: safeTexts })

  try {
    const parsed = JSON.parse(result)
    if (Array.isArray(parsed) && parsed.length === safeTexts.length) {
      return res.json({ translations: parsed })
    }
  } catch {/* fall through */}

  return res.json({ translations: safeTexts })
})
