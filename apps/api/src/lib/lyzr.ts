/**
 * Lyzr AI integration — powers the "Suggest intro" feature.
 *
 * Setup (one-time):
 *  1. Go to app.lyzr.ai (or studio.lyzr.ai) → Settings → API Keys → copy key
 *  2. Create an agent → copy its Agent ID
 *  3. Add both to apps/api/.env:
 *       LYZR_API_KEY=lyzr-...
 *       LYZR_AGENT_ID=agent-...
 *
 * If those env vars are missing, suggestResponse() falls back to the existing
 * Grok/Groq LLM so the feature still works offline / before Lyzr is wired up.
 */

const LYZR_API_URL = 'https://agent-prod.studio.lyzr.ai/v3/inference/chat/'
const TIMEOUT_MS = 15_000

export type SuggestResponseArgs = {
  needTitle: string
  needDescription: string
  category: 'EARN' | 'CONNECT'
  budget?: string | null
  responderBio?: string | null
  responderSkills?: string[]
  responderInterests?: string[]
}

export type SuggestionResult = {
  suggestion: string
  poweredBy: 'lyzr' | 'fallback'
}

const SUGGEST_SYSTEM_PROMPT = `You are NeedHub AI, a hyperlocal needs platform assistant.

Your job: write a short, friendly, first-person intro message (2–3 sentences) for someone
who wants to help with a need posted by another user.

Rules:
- Start with WHY they are a good fit (reference their skills or interests if provided)
- Include ONE specific detail from the need description
- End with an offer to help or a relevant question
- Keep it under 60 words
- Natural, warm tone — not corporate or formal
- Do NOT include greetings like "Hi!" or "Hello!"
- Return ONLY the message text, nothing else`

/**
 * Generate a personalized intro message suggestion for someone applying to a need.
 * Uses Lyzr Agent API if configured, falls back to Grok/Groq otherwise.
 */
export async function suggestResponse(args: SuggestResponseArgs): Promise<SuggestionResult> {
  const lyzrKey = process.env.LYZR_API_KEY
  const lyzrAgentId = process.env.LYZR_AGENT_ID

  const userMessage = buildUserMessage(args)

  if (lyzrKey && lyzrAgentId) {
    try {
      return {
        suggestion: await callLyzr(lyzrKey, lyzrAgentId, userMessage),
        poweredBy: 'lyzr',
      }
    } catch (err) {
      console.warn('[lyzr] Lyzr call failed, falling back to Grok:', (err as Error).message)
    }
  }

  // Fallback: use existing Grok/Groq LLM (same pattern as llm.ts)
  try {
    return {
      suggestion: await callFallbackLlm(userMessage),
      poweredBy: 'fallback',
    }
  } catch (err) {
    throw new Error(`Suggestion unavailable: ${(err as Error).message}`)
  }
}

async function callLyzr(apiKey: string, agentId: string, message: string): Promise<string> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  // Use a stable session per agent so Lyzr memory works across calls
  const sessionId = `${agentId}-needhub`

  try {
    const res = await fetch(LYZR_API_URL, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'x-api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        user_id: 'needhub-app',
        agent_id: agentId,
        session_id: sessionId,
        message,
      }),
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`Lyzr ${res.status}: ${body.slice(0, 200)}`)
    }

    // v3 API returns { response: string, ... }
    const data = (await res.json()) as { response?: string; output?: string; message?: string }
    const text = data.response ?? data.output ?? data.message
    if (!text?.trim()) throw new Error('Lyzr returned empty response')
    return text.trim()
  } finally {
    clearTimeout(timeout)
  }
}

async function callFallbackLlm(userMessage: string): Promise<string> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = process.env.LLM_API_KEY
  const model = process.env.LLM_MODEL
  if (!baseUrl || !key || !model) throw new Error('No LLM configured')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

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
        temperature: 0.7,
        max_tokens: 120,
        messages: [
          { role: 'system', content: SUGGEST_SYSTEM_PROMPT },
          { role: 'user', content: userMessage },
        ],
      }),
    })

    if (!res.ok) throw new Error(`LLM ${res.status}`)
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] }
    const text = data.choices?.[0]?.message?.content?.trim()
    if (!text) throw new Error('LLM returned no content')
    return text
  } finally {
    clearTimeout(timeout)
  }
}

function buildUserMessage(args: SuggestResponseArgs): string {
  const lines: string[] = [
    `Need: "${args.needTitle}"`,
    `Description: ${args.needDescription}`,
    `Type: ${args.category === 'EARN' ? 'Paid task' : 'Connect/collab'}`,
  ]
  if (args.budget) lines.push(`Budget: ${args.budget}`)
  if (args.responderBio) lines.push(`Helper bio: ${args.responderBio}`)
  if (args.responderSkills?.length) lines.push(`Helper skills: ${args.responderSkills.join(', ')}`)
  if (args.responderInterests?.length) lines.push(`Helper interests: ${args.responderInterests.join(', ')}`)
  lines.push('\nWrite the intro message for the helper to send.')
  return lines.join('\n')
}
