import express from 'express'
import { authenticate } from '../../middleware/authenticate'
import { config } from '../../config'

export const translateRouter = express.Router()

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

translateRouter.post('/', authenticate, async (req, res) => {
  const { text, targetLang } = req.body as { text?: string; targetLang?: string }

  if (!text || typeof text !== 'string' || !text.trim()) {
    return res.json({ translated: text ?? '' })
  }
  if (!targetLang || !LANG_NAMES[targetLang]) {
    return res.json({ translated: text })
  }
  if (targetLang === 'en') {
    return res.json({ translated: text })
  }

  const baseUrl = process.env.LLM_BASE_URL
  const key = config.llmApiKey
  const model = config.llmModel

  if (!baseUrl || !key || !model) {
    return res.json({ translated: text })
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 10000)

  try {
    const r = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.1,
        messages: [
          {
            role: 'system',
            content: `You are a translator. Translate the user's text to ${LANG_NAMES[targetLang]}. Return ONLY the translated text — no explanations, no quotes, no markdown.`,
          },
          { role: 'user', content: text.slice(0, 2000) },
        ],
      }),
    })

    if (!r.ok) {
      return res.json({ translated: text })
    }

    const data = (await r.json()) as { choices?: { message?: { content?: string } }[] }
    const translated = data.choices?.[0]?.message?.content?.trim()

    return res.json({ translated: translated || text })
  } catch {
    return res.json({ translated: text })
  } finally {
    clearTimeout(timeout)
  }
})
