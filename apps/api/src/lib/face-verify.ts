/**
 * AI face verification — privacy-first.
 * The image buffer is processed here and NEVER written to disk or stored.
 * If the vision model confirms a real human face, the caller sets the DB flag.
 */

const VISION_PROMPT =
  'Does this image show exactly one real, live human face? ' +
  'Not a photo-of-a-photo, not a drawing, not a mask, not a group, not an animal. ' +
  'Reply with EXACTLY one word: VERIFIED or REJECTED'

export type FaceVerifyResult = { verified: boolean; reason: string }

export async function verifyFace(
  imageBuffer: Buffer,
  mimeType: string,
): Promise<FaceVerifyResult> {
  const baseUrl = process.env.LLM_BASE_URL
  const apiKey = process.env.LLM_API_KEY
  const model = process.env.VISION_MODEL || 'meta-llama/llama-4-scout-17b-16e-instruct'

  if (!baseUrl || !apiKey) throw new Error('Vision LLM not configured')

  const b64 = imageBuffer.toString('base64')
  const dataUrl = `data:${mimeType};base64,${b64}`

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 20_000)

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        max_tokens: 10,
        temperature: 0,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image_url', image_url: { url: dataUrl } },
              { type: 'text', text: VISION_PROMPT },
            ],
          },
        ],
      }),
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`Vision LLM ${res.status}: ${body.slice(0, 200)}`)
    }

    const data = (await res.json()) as {
      choices?: { message?: { content?: string } }[]
    }
    const answer = data.choices?.[0]?.message?.content?.trim().toUpperCase() ?? ''
    const verified = answer.startsWith('VERIFIED')
    return {
      verified,
      reason: verified ? 'Face confirmed' : 'No real human face detected — please retake in good lighting',
    }
  } finally {
    clearTimeout(timeout)
    // imageBuffer goes out of scope — GC'd, never stored
  }
}
