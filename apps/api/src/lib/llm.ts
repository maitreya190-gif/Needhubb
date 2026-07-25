import { z } from 'zod'
import type { DecomposeResult } from '@needhub/shared'
import { config } from '../config'

/**
 * Server-side only. LLM API key never leaves this module.
 *
 * Uses the OpenAI-compatible endpoint configured in `.env`
 * (Groq in dev — llama-3.3-70b — but any OpenAI-compatible endpoint works).
 *
 * On any failure (network, schema, parse), THROWS so the caller can fall back
 * gracefully (post the raw text as a single need).
 */

const decomposedNeed = z.object({
  title: z.string().min(1).max(120),
  description: z.string().min(1).max(2000),
  needType: z.enum(['EARN', 'CONNECT']),
  earnCategory: z
    .enum(['TUTORING', 'FREELANCE', 'GOODS_BUY', 'GOODS_SELL', 'REPAIR', 'OTHER'])
    .nullable(),
  connectCategory: z
    .enum(['STUDY_PARTNER', 'ACTIVITY_PARTNER', 'HOBBY', 'MENTOR', 'OTHER'])
    .nullable(),
  budgetMin: z.number().nullable(),
  budgetMax: z.number().nullable(),
  deadline: z.string().nullable(),
})

const decomposeResult = z.object({
  needs: z.array(decomposedNeed).min(1).max(6),
})

const SYSTEM_PROMPT = `You are the NeedHub AI decomposition engine.

You take a single free-form user request and split it into 1–4 concrete, actionable NEEDS that other users can respond to.

Return STRICT JSON matching this schema:

{
  "needs": [
    {
      "title": string,               // <= 80 chars, imperative
      "description": string,         // 1-2 sentences, what the responder does
      "needType": "EARN" | "CONNECT",
      "earnCategory": "TUTORING" | "FREELANCE" | "GOODS_BUY" | "GOODS_SELL" | "REPAIR" | "OTHER" | null,
      "connectCategory": "STUDY_PARTNER" | "ACTIVITY_PARTNER" | "HOBBY" | "MENTOR" | "OTHER" | null,
      "budgetMin": number | null,    // in INR (₹). Null if not monetary.
      "budgetMax": number | null,
      "deadline": string | null      // ISO-8601 date if user gave one. Null otherwise.
    }
  ]
}

Rules:
- needType=EARN when money changes hands or a paid service is requested. earnCategory MUST be set. connectCategory MUST be null.
- needType=CONNECT when it's about meeting people, mentorship, study/activity partners. connectCategory MUST be set. earnCategory MUST be null.
- Split multi-step requests into separate needs. E.g. "propose to my gf next month" -> [find ring shop, book restaurant, buy flowers, photographer]. Each becomes its own EARN need.
- Prefer 2-4 needs for anything non-trivial. Only return 1 need if the user's request truly is atomic.
- Never invent budgets. If unspecified, budgetMin/Max=null.
- Never invent deadlines. If unspecified, deadline=null.
- Titles are imperative. Good: "Book a photographer for engagement". Bad: "Photography".
- Descriptions should tell a responder exactly what they'd be doing.
- Return ONLY the JSON object. No prose, no markdown fences.`

export async function decomposeNeed(text: string): Promise<DecomposeResult> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = config.llmApiKey
  const model = config.llmModel
  if (!baseUrl || !key || !model) throw new Error('LLM not configured')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 20000)

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Authorization': `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        response_format: { type: 'json_object' },
        temperature: 0.3,
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: text.slice(0, 3000) },
        ],
      }),
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`LLM ${res.status}: ${body.slice(0, 200)}`)
    }

    const data = (await res.json()) as {
      choices?: { message?: { content?: string } }[]
    }
    const raw = data.choices?.[0]?.message?.content?.trim()
    if (!raw) throw new Error('LLM returned no content')

    let json: unknown
    try {
      json = JSON.parse(raw)
    } catch {
      // Some models wrap in ```json fences despite response_format. Strip and retry.
      const stripped = raw.replace(/^```(?:json)?\s*|\s*```$/g, '')
      json = JSON.parse(stripped)
    }

    const parsed = decomposeResult.safeParse(json)
    if (!parsed.success) {
      throw new Error(`LLM output failed schema: ${parsed.error.message.slice(0, 300)}`)
    }

    // Normalize category invariants — the prompt asks the model to do this but
    // llama occasionally sets both. Server enforces the rule.
    for (const n of parsed.data.needs) {
      if (n.needType === 'EARN') n.connectCategory = null
      if (n.needType === 'CONNECT') n.earnCategory = null
    }

    return parsed.data
  } finally {
    clearTimeout(timeout)
  }
}
