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

// ── Personality analyzer ─────────────────────────────────────────────────────
// Uses a dedicated Lyzr agent that returns a strict JSON personality profile
// given 10 quiz answers. See LYZR_PERSONALITY_AGENT_ID in .env.

export type PersonalityTraits = {
  openness: number
  conscientiousness: number
  extraversion: number
  agreeableness: number
  emotionalStability: number
}

export type PersonalityProfile = {
  traits: PersonalityTraits
  nickname: string
  summary: string
  vibeTags: string[]
}

const PERSONALITY_SYSTEM_PROMPT = `You are NeedHub's personality analyst.

INPUT: A JSON object with 10 numbered answers (q1..q10) to a personality quiz.

OUTPUT: STRICT JSON only — no markdown, no code fences, no commentary. Match this schema exactly:

{
  "traits": {
    "openness": <integer 0-100>,
    "conscientiousness": <integer 0-100>,
    "extraversion": <integer 0-100>,
    "agreeableness": <integer 0-100>,
    "emotionalStability": <integer 0-100>
  },
  "nickname": "<max 3 words, evocative and positive, e.g. 'The Builder', 'The Quiet Storm'>",
  "summary": "<one warm sentence, max 25 words, never judgmental>",
  "vibeTags": ["<lowercase-tag>", "<lowercase-tag>", "<lowercase-tag>"]
}

Ground every score in the answers. Return ONLY the JSON. No prefix, no suffix.`

/**
 * Analyze 10 quiz answers and return a normalized personality profile.
 * 3-tier fallback — this function is GUARANTEED to succeed:
 *   1. Lyzr agent (branded, preferred)
 *   2. Groq LLM (using the same key as moderation/decompose)
 *   3. Local deterministic Big-Five scoring engine (always works, no network)
 * Never throws. The demo cannot break because Lyzr broke.
 */
export async function analyzePersonality(
  answers: string[],
): Promise<PersonalityProfile & { poweredBy: 'lyzr' | 'groq' | 'local' }> {
  const message = JSON.stringify(
    Object.fromEntries(answers.map((a, i) => [`q${i + 1}`, a])),
  )

  // Attempt 1: Lyzr agent (branded, on the Home CTA).
  try {
    const lyzrProfile = await callLyzrPersonality(message)
    return { ...lyzrProfile, poweredBy: 'lyzr' }
  } catch (err) {
    console.warn('[personality] Lyzr failed, falling back to Groq:', (err as Error).message)
  }

  // Attempt 2: Groq via the same key we already use for moderation + decompose.
  try {
    const groqProfile = await callGroqPersonality(message)
    return { ...groqProfile, poweredBy: 'groq' }
  } catch (err) {
    console.warn('[personality] Groq failed, using local scoring engine:', (err as Error).message)
  }

  // Attempt 3: Local Big-Five scoring engine — deterministic, no network,
  // never fails. The demo cannot break.
  return { ...computeLocalPersonality(answers), poweredBy: 'local' }
}

/**
 * Deterministic Big-Five scorer. Never fails. Maps each answer position to
 * trait deltas based on the semantic direction of the option chosen. The
 * result is a plausible personality profile grounded in the answers.
 */
function computeLocalPersonality(answers: string[]): PersonalityProfile {
  const traits = { openness: 50, conscientiousness: 50, extraversion: 50, agreeableness: 50, emotionalStability: 50 }

  const bump = (k: keyof typeof traits, delta: number) => {
    traits[k] = Math.max(0, Math.min(100, traits[k] + delta))
  }

  const a = answers.map((x) => x.toLowerCase())

  // Q1 — Saturday: walk/new = openness, solo project = conscientious, group = extraversion, cozy = agreeableness
  if (a[0]?.includes('walk') || a[0]?.includes('new')) bump('openness', 15)
  if (a[0]?.includes('solo') || a[0]?.includes('project')) bump('conscientiousness', 15)
  if (a[0]?.includes('group')) bump('extraversion', 18)
  if (a[0]?.includes('cozy') || a[0]?.includes('close')) bump('agreeableness', 12)

  // Q2 — Meet new: ask questions = openness, listen = agreeableness, joke = extraversion, wait = introvert
  if (a[1]?.includes('ask')) bump('openness', 12)
  if (a[1]?.includes('listen')) bump('agreeableness', 15)
  if (a[1]?.includes('joke') || a[1]?.includes('ice')) bump('extraversion', 15)
  if (a[1]?.includes('wait')) bump('extraversion', -12)

  // Q3 — Workspace: place = conscientious high; chaos = openness; pile/inspiration = openness; laptop lands = low conscientiousness
  if (a[2]?.includes('place')) bump('conscientiousness', 18)
  if (a[2]?.includes('chaos') || a[2]?.includes('rotating') || a[2]?.includes('inspiration')) bump('openness', 12)
  if (a[2]?.includes('wherever') || a[2]?.includes('lands')) bump('conscientiousness', -12)

  // Q4 — Cancel plans: relief = introvert/emotional stability, curiosity = agreeableness, annoyed = low stability, swap = extraversion
  if (a[3]?.includes('relief') || a[3]?.includes('reset')) bump('emotionalStability', 12)
  if (a[3]?.includes('curiosity') || a[3]?.includes('okay')) bump('agreeableness', 12)
  if (a[3]?.includes('annoyed')) bump('emotionalStability', -8)
  if (a[3]?.includes('swap') || a[3]?.includes('three other')) bump('extraversion', 15)

  // Q5 — Happiest: build/hands = conscientious, learn = openness, help = agreeableness, energy = extraversion
  if (a[4]?.includes('build') || a[4]?.includes('hands')) bump('conscientiousness', 12)
  if (a[4]?.includes('learn')) bump('openness', 15)
  if (a[4]?.includes('help')) bump('agreeableness', 18)
  if (a[4]?.includes('energy') || a[4]?.includes('surrounded')) bump('extraversion', 15)

  // Q6 — Quote: depth = conscientiousness, curious = openness, people = agreeableness, ship = extraversion/conscientious
  if (a[5]?.includes('depth')) bump('conscientiousness', 12)
  if (a[5]?.includes('curious')) bump('openness', 15)
  if (a[5]?.includes('people')) bump('agreeableness', 15)
  if (a[5]?.includes('ship') || a[5]?.includes('polish')) bump('conscientiousness', 10)

  // Q7 — Stress: withdraw = introvert, talk = extraversion, task = conscientious, body = emotional stability
  if (a[6]?.includes('withdraw') || a[6]?.includes('recharge')) bump('extraversion', -15)
  if (a[6]?.includes('talk')) bump('extraversion', 12)
  if (a[6]?.includes('task') || a[6]?.includes('distract')) bump('conscientiousness', 10)
  if (a[6]?.includes('body') || a[6]?.includes('walk') || a[6]?.includes('workout')) bump('emotionalStability', 15)

  // Q8 — Draws you: unexpected = openness, listened = agreeableness, warm/easy = agreeableness, niche = openness
  if (a[7]?.includes('unexpected')) bump('openness', 12)
  if (a[7]?.includes('listened')) bump('agreeableness', 15)
  if (a[7]?.includes('warm') || a[7]?.includes('easy')) bump('agreeableness', 12)
  if (a[7]?.includes('niche')) bump('openness', 12)

  // Q9 — Try new: trust recommended = agreeableness, data = conscientious, itch = openness, bored = openness
  if (a[8]?.includes('trust') || a[8]?.includes('recommended')) bump('agreeableness', 12)
  if (a[8]?.includes('data') || a[8]?.includes('convinced')) bump('conscientiousness', 12)
  if (a[8]?.includes('itch') || a[8]?.includes('months')) bump('openness', 12)
  if (a[8]?.includes('bored')) bump('openness', 15)

  // Q10 — Compliment: person I call = agreeableness, make things = conscientiousness, see something = openness, easy = extraversion
  if (a[9]?.includes('call when') || a[9]?.includes('hard')) bump('agreeableness', 15)
  if (a[9]?.includes('make things happen')) bump('conscientiousness', 15)
  if (a[9]?.includes('see something') || a[9]?.includes('no one else')) bump('openness', 15)
  if (a[9]?.includes('easy')) bump('extraversion', 12)

  // Pick a nickname from the dominant trait.
  const entries = Object.entries(traits) as Array<[keyof typeof traits, number]>
  entries.sort((x, y) => y[1] - x[1])
  const [top] = entries
  const nicknames: Record<keyof typeof traits, string> = {
    openness: 'The Explorer',
    conscientiousness: 'The Builder',
    extraversion: 'The Connector',
    agreeableness: 'The Anchor',
    emotionalStability: 'The Steady One',
  }
  const summaries: Record<keyof typeof traits, string> = {
    openness: 'A curious mind drawn to new ideas and fresh experiences over routine.',
    conscientiousness: 'A grounded doer who turns intentions into finished, well-crafted things.',
    extraversion: 'Energized by people — you spark rooms and gather good company easily.',
    agreeableness: 'Warm, generous, and the person people call when things get hard.',
    emotionalStability: 'A calm steady presence who handles turbulence without losing focus.',
  }
  const vibes: Record<keyof typeof traits, string[]> = {
    openness: ['curious', 'inventive', 'open-minded'],
    conscientiousness: ['reliable', 'focused', 'grounded'],
    extraversion: ['warm', 'social', 'energizing'],
    agreeableness: ['kind', 'loyal', 'thoughtful'],
    emotionalStability: ['steady', 'composed', 'calm'],
  }
  return {
    traits,
    nickname: nicknames[top[0]],
    summary: summaries[top[0]],
    vibeTags: vibes[top[0]],
  }
}

async function callLyzrPersonality(message: string): Promise<PersonalityProfile> {
  const apiKey = process.env.LYZR_API_KEY
  const agentId = process.env.LYZR_PERSONALITY_AGENT_ID
  if (!apiKey || !agentId) {
    throw new Error('Lyzr personality agent not configured')
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    const res = await fetch(LYZR_API_URL, {
      method: 'POST',
      signal: controller.signal,
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user_id: 'needhub-personality',
        agent_id: agentId,
        session_id: `${agentId}-${Date.now()}`,
        message,
      }),
    })
    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`Lyzr personality ${res.status}: ${body.slice(0, 200)}`)
    }
    const data = (await res.json()) as { response?: string; output?: string }
    const raw = (data.response ?? data.output ?? '').trim()
    if (!raw) throw new Error('Lyzr personality returned empty response')

    // Extract the first {...} JSON object from the response. Handles cases
    // where Lyzr wraps the JSON in markdown fences or adds a preamble/suffix.
    const cleaned = raw
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/```\s*$/i, '')
      .trim()
    let jsonText = cleaned
    if (!jsonText.startsWith('{')) {
      const firstBrace = jsonText.indexOf('{')
      const lastBrace = jsonText.lastIndexOf('}')
      if (firstBrace !== -1 && lastBrace > firstBrace) {
        jsonText = jsonText.slice(firstBrace, lastBrace + 1)
      }
    }

    let parsed: PersonalityProfile
    try {
      parsed = JSON.parse(jsonText) as PersonalityProfile
    } catch (err) {
      console.error('[lyzr] personality parse failure. Raw response:', raw.slice(0, 500))
      throw new Error(`Lyzr personality returned unparseable JSON: ${(err as Error).message}`)
    }
    if (!parsed.traits || typeof parsed.traits.openness !== 'number') {
      throw new Error('Lyzr personality returned malformed profile — missing traits')
    }
    // Coerce missing / fuzzy fields so downstream code never crashes.
    parsed.nickname = parsed.nickname?.trim() || 'The NeedHubber'
    parsed.summary = parsed.summary?.trim() || ''
    parsed.vibeTags = Array.isArray(parsed.vibeTags)
      ? parsed.vibeTags.map((t) => String(t).trim()).filter(Boolean).slice(0, 6)
      : []
    return parsed
  } finally {
    clearTimeout(timeout)
  }
}

async function callGroqPersonality(message: string): Promise<PersonalityProfile> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = process.env.LLM_API_KEY
  const model = process.env.LLM_MODEL
  if (!baseUrl || !key || !model) {
    throw new Error('Groq fallback not configured — set LLM_API_KEY, LLM_BASE_URL, LLM_MODEL in .env')
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.6,
        max_tokens: 400,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: PERSONALITY_SYSTEM_PROMPT },
          { role: 'user', content: message },
        ],
      }),
    })
    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`Groq personality ${res.status}: ${body.slice(0, 200)}`)
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] }
    const raw = data.choices?.[0]?.message?.content?.trim()
    if (!raw) throw new Error('Groq personality returned no content')

    let parsed: PersonalityProfile
    try {
      parsed = JSON.parse(raw) as PersonalityProfile
    } catch (err) {
      console.error('[groq] personality parse failure. Raw:', raw.slice(0, 500))
      throw new Error(`Groq personality returned unparseable JSON: ${(err as Error).message}`)
    }
    if (!parsed.traits || typeof parsed.traits.openness !== 'number') {
      throw new Error('Groq personality returned malformed profile')
    }
    parsed.nickname = parsed.nickname?.trim() || 'The NeedHubber'
    parsed.summary = parsed.summary?.trim() || ''
    parsed.vibeTags = Array.isArray(parsed.vibeTags)
      ? parsed.vibeTags.map((t) => String(t).trim()).filter(Boolean).slice(0, 6)
      : []
    return parsed
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
