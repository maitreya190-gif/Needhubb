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
// given 10 quiz answers. If Lyzr is missing or fails, falls back to Grok/Groq LLM
// or a deterministic local Big Five scoring engine so submission NEVER fails with 502.

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

/**
 * Analyze 10 quiz answers and return a normalized personality profile.
 * 3-Tier Fallback Architecture:
 *   1. Lyzr Agent (if LYZR_PERSONALITY_AGENT_ID is configured)
 *   2. Grok/Groq Fallback LLM (if LLM_* env vars are configured)
 *   3. Deterministic Local Big Five Scoring Engine (always guaranteed to succeed)
 */
export async function analyzePersonality(
  answers: string[],
): Promise<PersonalityProfile> {
  const apiKey = process.env.LYZR_API_KEY
  const agentId = process.env.LYZR_PERSONALITY_AGENT_ID

  // 1. Try Lyzr API
  if (apiKey && agentId) {
    try {
      return await callLyzrPersonality(apiKey, agentId, answers)
    } catch (err) {
      console.warn('[lyzr] Personality Lyzr call failed, trying LLM fallback:', (err as Error).message)
    }
  }

  // 2. Try Fallback LLM
  try {
    return await callFallbackLlmForPersonality(answers)
  } catch (err) {
    console.warn('[lyzr] Personality LLM call failed, using local scoring engine:', (err as Error).message)
  }

  // 3. Fallback to robust local scoring engine (always succeeds)
  return computeLocalPersonality(answers)
}

async function callLyzrPersonality(apiKey: string, agentId: string, answers: string[]): Promise<PersonalityProfile> {
  const message = JSON.stringify(
    Object.fromEntries(answers.map((a, i) => [`q${i + 1}`, a])),
  )

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
    return parseAndCleanProfile(raw)
  } finally {
    clearTimeout(timeout)
  }
}

async function callFallbackLlmForPersonality(answers: string[]): Promise<PersonalityProfile> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = process.env.LLM_API_KEY
  const model = process.env.LLM_MODEL
  if (!baseUrl || !key || !model) throw new Error('No LLM configured')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  const prompt = `Analyze these 10 personality quiz responses:
${answers.map((a, i) => `Q${i + 1}: ${a}`).join('\n')}

Return ONLY a JSON object matching this exact schema:
{
  "traits": {
    "openness": <number 50-98>,
    "conscientiousness": <number 50-98>,
    "extraversion": <number 50-98>,
    "agreeableness": <number 50-98>,
    "emotionalStability": <number 50-98>
  },
  "nickname": "<a catchy 2-3 word archetype, e.g. 'The Grounded Builder'>",
  "summary": "<2-sentence insight about their style & strengths>",
  "vibeTags": ["<tag1>", "<tag2>", "<tag3>", "<tag4>"]
}`

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
        max_tokens: 300,
        messages: [
          { role: 'system', content: 'You are a personality psychologist. Return valid JSON only.' },
          { role: 'user', content: prompt },
        ],
      }),
    })

    if (!res.ok) throw new Error(`LLM ${res.status}`)
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] }
    const raw = data.choices?.[0]?.message?.content?.trim()
    if (!raw) throw new Error('LLM returned no content')
    return parseAndCleanProfile(raw)
  } finally {
    clearTimeout(timeout)
  }
}

function parseAndCleanProfile(raw: string): PersonalityProfile {
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

  const parsed = JSON.parse(jsonText) as PersonalityProfile
  if (!parsed.traits || typeof parsed.traits.openness !== 'number') {
    throw new Error('Lyzr personality returned malformed profile — missing traits')
  }
  parsed.nickname = parsed.nickname?.trim() || 'The NeedHubber'
  parsed.summary = parsed.summary?.trim() || ''
  parsed.vibeTags = Array.isArray(parsed.vibeTags)
    ? parsed.vibeTags.map((t) => String(t).trim()).filter(Boolean).slice(0, 6)
    : []
  return parsed
}

export function computeLocalPersonality(answers: string[]): PersonalityProfile {
  let openness = 65
  let conscientiousness = 65
  let extraversion = 65
  let agreeableness = 65
  let emotionalStability = 65

  answers.forEach((ans) => {
    const a = ans.toLowerCase()
    // Q1
    if (a.includes('walk somewhere new')) { openness += 12 }
    else if (a.includes('solo project')) { conscientiousness += 12; extraversion -= 6 }
    else if (a.includes('group hangout')) { extraversion += 15 }
    else if (a.includes('cozy day in')) { agreeableness += 10 }

    // Q2
    if (a.includes('ask a lot of questions')) { openness += 10; agreeableness += 8 }
    else if (a.includes('listen more')) { agreeableness += 12; extraversion -= 6 }
    else if (a.includes('crack a joke')) { extraversion += 12; emotionalStability += 6 }
    else if (a.includes('wait for them')) { emotionalStability += 8 }

    // Q3
    if (a.includes('everything has its place')) { conscientiousness += 15 }
    else if (a.includes('organized chaos')) { openness += 8; conscientiousness += 6 }
    else if (a.includes('rotating pile')) { openness += 15 }
    else if (a.includes('wherever my laptop')) { extraversion += 8 }

    // Q4
    if (a.includes('relief')) { emotionalStability += 10; extraversion -= 8 }
    else if (a.includes('curiosity')) { agreeableness += 12 }
    else if (a.includes('annoyed but flexible')) { emotionalStability += 12 }
    else if (a.includes('text three other')) { extraversion += 15 }

    // Q5
    if (a.includes('building something')) { conscientiousness += 12; openness += 8 }
    else if (a.includes('learning a new idea')) { openness += 15 }
    else if (a.includes('helping someone')) { agreeableness += 15 }
    else if (a.includes('surrounded by good energy')) { extraversion += 12; agreeableness += 8 }

    // Q6
    if (a.includes('depth over breadth')) { conscientiousness += 10; extraversion -= 5 }
    else if (a.includes('stay curious')) { openness += 15 }
    else if (a.includes('people are the point')) { agreeableness += 15; extraversion += 8 }
    else if (a.includes('ship, then polish')) { conscientiousness += 15 }

    // Q7
    if (a.includes('withdraw and recharge')) { extraversion -= 8; emotionalStability += 8 }
    else if (a.includes('talk it out')) { agreeableness += 10; extraversion += 8 }
    else if (a.includes('distract yourself with a task')) { conscientiousness += 12 }
    else if (a.includes('move your body')) { emotionalStability += 15 }

    // Q8
    if (a.includes('something unexpected')) { openness += 12 }
    else if (a.includes('actually listened')) { agreeableness += 15 }
    else if (a.includes('warm and easy')) { agreeableness += 10; emotionalStability += 8 }
    else if (a.includes('niche interest')) { openness += 10; conscientiousness += 6 }

    // Q9
    if (a.includes('someone you trust')) { agreeableness += 10 }
    else if (a.includes('data that convinced')) { conscientiousness += 15 }
    else if (a.includes('itch you’ve had') || a.includes("itch you've had")) { openness += 12 }
    else if (a.includes('bored of your usual')) { extraversion += 10; openness += 8 }

    // Q10
    if (a.includes('person i call')) { agreeableness += 15; emotionalStability += 10 }
    else if (a.includes('make things happen')) { conscientiousness += 15; extraversion += 8 }
    else if (a.includes('see something no one else')) { openness += 15 }
    else if (a.includes('around you is easy')) { agreeableness += 20; emotionalStability += 12 }
  })

  const clamp = (val: number) => Math.min(96, Math.max(52, Math.round(val)))
  const traits: PersonalityTraits = {
    openness: clamp(openness),
    conscientiousness: clamp(conscientiousness),
    extraversion: clamp(extraversion),
    agreeableness: clamp(agreeableness),
    emotionalStability: clamp(emotionalStability),
  }

  const maxTrait = Object.entries(traits).reduce((a, b) => (b[1] > a[1] ? b : a))
  let nickname = 'The Thoughtful Explorer'
  let summary = 'You balance practical focus with a warm, open perspective when connecting with others.'
  let vibeTags = ['Curious', 'Reliable', 'Thoughtful', 'Balanced']

  switch (maxTrait[0]) {
    case 'openness':
      nickname = 'The Visionary Catalyst'
      summary = 'Driven by curiosity and fresh ideas, you bring imaginative problem-solving to every room you enter.'
      vibeTags = ['Creative', 'Curious', 'Innovative', 'Open-Minded']
      break
    case 'conscientiousness':
      nickname = 'The Grounded Architect'
      summary = 'Methodical and dependable, you take pride in turning ideas into tangible, high-quality results.'
      vibeTags = ['Focused', 'Reliable', 'Detail-Oriented', 'Structured']
      break
    case 'extraversion':
      nickname = 'The Energy Connector'
      summary = 'You thrive on vibrant interactions and bring warmth, enthusiasm, and momentum wherever you go.'
      vibeTags = ['Outgoing', 'Dynamic', 'Expressive', 'Engaging']
      break
    case 'agreeableness':
      nickname = 'The Harmony Builder'
      summary = 'Empathetic and grounded, you create safe, supportive spaces where people feel truly heard.'
      vibeTags = ['Empathetic', 'Warm', 'Supportive', 'Good Listener']
      break
    case 'emotionalStability':
      nickname = 'The Calm Anchor'
      summary = 'Composed under pressure, your steady presence helps clarify chaos and navigate challenges with ease.'
      vibeTags = ['Steady', 'Adaptable', 'Resilient', 'Calm Energy']
      break
  }

  return {
    traits,
    nickname,
    summary,
    vibeTags,
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
