/**
 * AI face verification — privacy-first.
 *
 * Uses Face++ (Megvii) dedicated face detection API.
 * The image buffer is processed in-memory and NEVER written to disk or stored.
 * If exactly one real human face is detected, the caller sets the DB flag.
 *
 * Setup:
 *   1. Sign up at console.faceplusplus.com
 *   2. Create an app → copy API Key + API Secret
 *   3. Add to .env:  FACEPP_API_KEY=...  FACEPP_API_SECRET=...
 */

const FACEPP_URL = 'https://api-us.faceplusplus.com/facepp/v3/detect'
const TIMEOUT_MS = 15_000

export type FaceVerifyResult = { verified: boolean; reason: string }

export async function verifyFace(
  imageBuffer: Buffer,
  _mimeType: string,
): Promise<FaceVerifyResult> {
  const apiKey = process.env.FACEPP_API_KEY
  const apiSecret = process.env.FACEPP_API_SECRET

  if (!apiKey || !apiSecret) {
    throw new Error('Face++ not configured — set FACEPP_API_KEY and FACEPP_API_SECRET in .env')
  }

  const b64 = imageBuffer.toString('base64')

  const form = new FormData()
  form.append('api_key', apiKey)
  form.append('api_secret', apiSecret)
  form.append('image_base64', b64)
  form.append('return_attributes', 'none')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    const res = await fetch(FACEPP_URL, {
      method: 'POST',
      signal: controller.signal,
      body: form,
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '')
      throw new Error(`Face++ ${res.status}: ${body.slice(0, 200)}`)
    }

    const data = (await res.json()) as {
      faces?: { face_token: string }[]
      error_message?: string
    }

    if (data.error_message) {
      throw new Error(`Face++ error: ${data.error_message}`)
    }

    const faceCount = data.faces?.length ?? 0

    if (faceCount === 0) {
      return { verified: false, reason: 'No face detected — please take a clear selfie in good lighting' }
    }
    if (faceCount > 1) {
      return { verified: false, reason: 'Multiple faces detected — please take a solo selfie' }
    }

    return { verified: true, reason: 'Face confirmed' }
  } finally {
    clearTimeout(timeout)
    // imageBuffer goes out of scope — GC'd, never stored
  }
}
