import { config } from '../config'

export type ModerationVerdict = {
  ok: boolean            // false = the write MUST be blocked
  hardBlocked: boolean   // matched the local blocklist
  softFlag: boolean      // LLM judged risky but not blocked
  matches: string[]      // hit terms (for admin review)
  llmScore?: number      // 0..1 from the LLM safety pass
  reasons: string[]      // human-readable summary for the admin panel
}

// Word-boundary regexes. Case-insensitive. This list intentionally stays compact
// and focuses on unambiguous hard-block content: well-known racial/homophobic slurs,
// explicit sexual language, credible threats, self-harm cues. Anything ambiguous
// (satire, quoted usage, reclaimed language) is caught softly by the LLM pass.
//
// Adding a term? Use \b anchors and put it in the category it belongs to so the
// reason string tells admins WHY something was blocked.
const BLOCKLIST: { pattern: RegExp; category: string }[] = [
  // Racial / ethnic slurs
  { pattern: /\bn[i1!][gq]{2}(?:er|a)s?\b/i, category: 'racial-slur' },
  { pattern: /\bch[i1!]nks?\b/i, category: 'racial-slur' },
  { pattern: /\bg[o0]{2}ks?\b/i, category: 'racial-slur' },
  { pattern: /\bsp[i1!]cs?\b/i, category: 'racial-slur' },
  { pattern: /\bk[i1!]kes?\b/i, category: 'racial-slur' },
  { pattern: /\bw[e3]tbacks?\b/i, category: 'racial-slur' },
  { pattern: /\btowelheads?\b/i, category: 'racial-slur' },
  { pattern: /\braghead\b/i, category: 'racial-slur' },
  { pattern: /\bp[a4]k[i1!]s?\b/i, category: 'racial-slur' },
  { pattern: /\bcoolies?\b/i, category: 'racial-slur' },

  // Homophobic / transphobic slurs
  { pattern: /\bf[a4]gg[o0]ts?\b/i, category: 'homophobic-slur' },
  { pattern: /\bf[a4]gs?\b/i, category: 'homophobic-slur' },
  { pattern: /\bd[y1i]kes?\b/i, category: 'homophobic-slur' },
  { pattern: /\btr[a4]nn+[i1y]es?\b/i, category: 'transphobic-slur' },
  { pattern: /\bshemales?\b/i, category: 'transphobic-slur' },

  // Misogynistic slurs
  { pattern: /\bwh[o0]res?\b/i, category: 'misogynistic-slur' },
  { pattern: /\bc[uv]nts?\b/i, category: 'misogynistic-slur' },
  { pattern: /\bslut+s?\b/i, category: 'misogynistic-slur' },

  // Ableist slurs — used to demean people with cognitive/physical disabilities.
  { pattern: /\bretard(?:s|ed|ation)?\b/i, category: 'ableist-slur' },
  { pattern: /\bmong(?:oloid|ol)s?\b/i, category: 'ableist-slur' },
  { pattern: /\bcrip+les?\b/i, category: 'ableist-slur' },
  { pattern: /\bspa(?:sti?c|z)s?\b/i, category: 'ableist-slur' },

  // General profanity
  { pattern: /\bf+u+c+k+(?:e[rd]|ing|ers?|s|ed)?\b/i, category: 'profanity' },
  { pattern: /\bsh[i1]t+(?:ty|head|hole|bag|s)?\b/i, category: 'profanity' },
  { pattern: /\bb[i1]tch(?:es|ing|y)?\b/i, category: 'profanity' },
  { pattern: /\bass+(?:hole|hat|wipe|face|head|clown|bag|es)?\b/i, category: 'profanity' },
  { pattern: /\bb[a4]st[a4]rds?\b/i, category: 'profanity' },
  { pattern: /\bm[o0]th[e3]rf+u+c+k(?:er|ing)?\b/i, category: 'profanity' },
  { pattern: /\bs[o0]n\s+of\s+a\s+b[i1]tch\b/i, category: 'profanity' },
  { pattern: /\bd[i1]+ck(?:head|s)?\b/i, category: 'profanity' },
  { pattern: /\bc[o0]+ck(?:sucker|head|s)?\b/i, category: 'profanity' },
  { pattern: /\bp[u0]ss+[yi](?:es?)?\b/i, category: 'profanity' },
  { pattern: /\bbull+?sh[i1]t\b/i, category: 'profanity' },
  { pattern: /\bwank(?:er|ing|s)?\b/i, category: 'profanity' },
  { pattern: /\bprick(?:s)?\b/i, category: 'profanity' },

  // Indian-language profanity (transliterated)
  { pattern: /\bm(?:a|aa)d[a4]rch[o0]d\b/i, category: 'profanity-hi' },
  { pattern: /\bmc\b/i, category: 'profanity-hi' },
  { pattern: /\bbh[e3]nch[o0]d\b/i, category: 'profanity-hi' },
  { pattern: /\bbc\b/i, category: 'profanity-hi' },
  { pattern: /\bch[u0][t7][i1]y[a4]\b/i, category: 'profanity-hi' },
  { pattern: /\br[a4]nd[i1]\b/i, category: 'profanity-hi' },
  { pattern: /\bg[a4]{2}nd\b/i, category: 'profanity-hi' },
  { pattern: /\bh[a4]r[a4]m[i1]\b/i, category: 'profanity-hi' },
  { pattern: /\bb[e3]hench[o0]d\b/i, category: 'profanity-hi' },

  // Hate speech targeting any group
  { pattern: /\bi\s+hate\s+(?:men|women|girls|boys|muslims?|hindus?|christians?|sikhs?|jews?|blacks?|whites?|indians?|pakistanis?|gays?|lesbians?|trans)\b/i, category: 'hate-speech' },
  { pattern: /\b(?:all|every)\s+(?:men|women|muslims?|hindus?|christians?|sikhs?|jews?|blacks?|whites?)\s+(?:are|should)\b/i, category: 'hate-speech' },
  { pattern: /\b(?:men|women|muslims?|hindus?|christians?|blacks?|whites?)\s+(?:are\s+)?(?:trash|disgusting|evil|inferior|stupid|animals?|dogs?)\b/i, category: 'hate-speech' },

  // Harassment intensifiers
  { pattern: /\bpiece\s+of\s+shit\b/i, category: 'harassment' },
  { pattern: /\bgo\s+(?:die|kys|kill\s+your?self)\b/i, category: 'harassment' },
  { pattern: /\bfuck(?:ing)?\s+(?:you|u|off|die)\b/i, category: 'harassment' },

  // Explicit sexual content (unwelcome on a marketplace listing)
  { pattern: /\bblowjobs?\b/i, category: 'explicit-sexual' },
  { pattern: /\bhandjobs?\b/i, category: 'explicit-sexual' },
  { pattern: /\brimjobs?\b/i, category: 'explicit-sexual' },
  { pattern: /\bcumshots?\b/i, category: 'explicit-sexual' },
  { pattern: /\bcreampies?\b/i, category: 'explicit-sexual' },
  { pattern: /\bdeepthroats?\b/i, category: 'explicit-sexual' },
  { pattern: /\bgangbangs?\b/i, category: 'explicit-sexual' },
  { pattern: /\bpornhub\b/i, category: 'explicit-sexual' },

  // Child sexual content — instant block, zero tolerance
  { pattern: /\b(?:child|kid|minor|underage|teen)\s*porn\b/i, category: 'csam' },
  { pattern: /\blolic[o0]n\b/i, category: 'csam' },
  { pattern: /\bshotac[o0]n\b/i, category: 'csam' },

  // Credible threats
  { pattern: /\b(?:i(?:'|’)?ll|i\s+will|gonna)\s+kill\s+(?:you|u|him|her|them)\b/i, category: 'threat' },
  { pattern: /\brape\s+(?:you|u|her|him|them)\b/i, category: 'threat' },
  { pattern: /\bshoot\s+up\s+(?:the|a|your)?\s*\w+/i, category: 'threat' },
  { pattern: /\bbomb\s+(?:the|a|your|this)\s+\w+/i, category: 'threat' },

  // Self-harm / suicide cues
  { pattern: /\bkill\s+(?:my|your|him|her|them)?s?e?l?f?\b/i, category: 'self-harm' },
  { pattern: /\bkms\b/i, category: 'self-harm' },
  { pattern: /\bcommit\s+suicide\b/i, category: 'self-harm' },
  { pattern: /\bhow\s+to\s+(?:kill\s+myself|die|overdose)\b/i, category: 'self-harm' },
  { pattern: /\bkill\s+yourself\b/i, category: 'self-harm' },
  { pattern: /\bend\s+(?:your|my)\s+life\b/i, category: 'self-harm' },

  // Doxxing signals
  { pattern: /\bs[o0]cial\s+security\s+number\b/i, category: 'pii-request' },
  { pattern: /\bssn\s*[:=]\s*\d{3}/i, category: 'pii-leak' },
]

const LLM_SAFETY_THRESHOLD = 0.7

export async function checkText(
  text: string,
  opts: { skipLlm?: boolean } = {},
): Promise<ModerationVerdict> {
  const clean = (text ?? '').trim()
  if (!clean) {
    return { ok: true, hardBlocked: false, softFlag: false, matches: [], reasons: [] }
  }

  // Hard-block pass — always synchronous, always runs, never throws.
  const matches: string[] = []
  const categories = new Set<string>()
  for (const { pattern, category } of BLOCKLIST) {
    const m = clean.match(pattern)
    if (m) {
      matches.push(m[0])
      categories.add(category)
    }
  }
  if (matches.length) {
    return {
      ok: false,
      hardBlocked: true,
      softFlag: false,
      matches,
      reasons: [...categories].map((c) => `blocklist:${c}`),
    }
  }

  // Callers on hot paths (like DMs) skip the LLM soft check to avoid a
  // per-message round trip to Grok. Hard blocklist above still catches
  // egregious content instantly.
  if (opts.skipLlm) {
    return { ok: true, hardBlocked: false, softFlag: false, matches: [], reasons: [] }
  }

  // Soft pass — ask the LLM to score toxicity. Never throws, never blocks.
  try {
    const score = await scoreWithLlm(clean)
    if (score >= LLM_SAFETY_THRESHOLD) {
      return {
        ok: true,
        hardBlocked: false,
        softFlag: true,
        matches: [],
        llmScore: score,
        reasons: [`llm-safety:${score.toFixed(2)}`],
      }
    }
    return {
      ok: true, hardBlocked: false, softFlag: false, matches: [], llmScore: score, reasons: [],
    }
  } catch (err) {
    // LLM unavailable — fail open (don't block writes on infra glitches).
    // The hard blocklist above still ran and passed, so this is safe.
    console.warn('[moderation] LLM soft-check failed, falling open:', (err as Error).message)
    return { ok: true, hardBlocked: false, softFlag: false, matches: [], reasons: [] }
  }
}

async function scoreWithLlm(text: string): Promise<number> {
  const baseUrl = process.env.LLM_BASE_URL
  const key = config.llmApiKey
  const model = config.llmModel
  if (!baseUrl || !key || !model) throw new Error('LLM not configured')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 5000)

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
        temperature: 0,
        messages: [
          {
            role: 'system',
            content: [
              'You are a strict content-safety scorer for NeedHub, a community',
              'app in India that matches strangers for gigs, favors, and casual',
              'meetups. Every post is a public listing seen by all users.',
              '',
              'Return STRICTLY valid JSON: {"score": <0..1 number>, "reason": "<short>"}',
              '',
              'Score >= 0.7 (BLOCK) when the text contains ANY of:',
              '• Hate or generalized dislike toward a group of people — even coded,',
              '  even if wrapped in a joke, sport, chess, or gaming context.',
              '  Examples that MUST score >= 0.7:',
              '    "I hate people who have the color X"',
              '    "I hate people who are Y" (Y = race, religion, caste, gender,',
              '     sexuality, disability, nationality, region, language, age)',
              '    "I don\'t want to work with [group]"',
              '    "no [minority group] please"',
              '    "only [my community] allowed"',
              '    "prefer [caste/religion] applicants"',
              '• Slurs (any language), dogwhistles, or veiled discrimination',
              '  (e.g., "our kind", "true Indians", "those darker types").',
              '• Explicit sexual solicitation, sex-for-money offers, escorting.',
              '• Threats, incitement, doxxing, or requests for illegal work.',
              '• Self-harm ideation or encouragement.',
              '• Deception: fake certifications, obvious scams, MLM recruiting.',
              '',
              'Score 0.4-0.6 (SOFT-FLAG) for edgy language that is not clearly',
              'targeting a group but could reasonably concern a moderator.',
              '',
              'Score < 0.4 for genuinely benign requests. Do NOT be lenient on',
              'hate speech disguised as a joke or hobby preference — err strict.',
              'A demographic preference is ONLY acceptable when it is a genuine',
              'safety need (e.g., "female tutor for my daughter") — and even then',
              'score no lower than 0.3.',
            ].join('\n'),
          },
          { role: 'user', content: text.slice(0, 2000) },
        ],
      }),
    })
    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`LLM ${res.status}: ${body.slice(0, 200)}`)
    }
    const data = await res.json() as { choices?: { message?: { content?: string } }[] }
    const raw = data.choices?.[0]?.message?.content ?? '{}'
    const parsed = JSON.parse(raw) as { score?: unknown }
    const score = typeof parsed.score === 'number' ? parsed.score : Number(parsed.score)
    if (Number.isNaN(score)) throw new Error('LLM returned non-numeric score')
    return Math.max(0, Math.min(1, score))
  } finally {
    clearTimeout(timeout)
  }
}
