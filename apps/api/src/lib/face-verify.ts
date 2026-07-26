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

const FACEPP_ENDPOINTS = [
  'https://api-us.faceplusplus.com/facepp/v3/detect',
  'https://api-cn.faceplusplus.com/facepp/v3/detect',
]
const TIMEOUT_MS = 15_000

export type FaceVerifyResult = { verified: boolean; reason: string }

async function callFacePlusPlus(
  endpoint: string,
  apiKey: string,
  apiSecret: string,
  imageBuffer: Buffer,
  mimeType: string,
): Promise<{ faces: any[]; raw: any } | { errorMessage: string }> {
  const form = new FormData()
  form.append('api_key', apiKey)
  form.append('api_secret', apiSecret)
  // Send as binary multipart instead of base64 — more efficient + reliable
  form.append('image_file', new Blob([new Uint8Array(imageBuffer)], { type: mimeType || 'image/jpeg' }), 'selfie.jpg')
  form.append('return_attributes', 'none')

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS)

  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      signal: controller.signal,
      body: form,
    })

    const bodyText = await res.text()
    let data: any = {}
    try {
      data = JSON.parse(bodyText)
    } catch {
      return { errorMessage: `Non-JSON response: ${bodyText.slice(0, 200)}` }
    }

    console.log('[face-verify] Face++ response:', {
      endpoint,
      status: res.status,
      faces: data.faces?.length ?? 0,
      error: data.error_message,
    })

    if (data.error_message) return { errorMessage: data.error_message }
    if (!res.ok) return { errorMessage: `HTTP ${res.status}: ${bodyText.slice(0, 200)}` }

    return { faces: data.faces ?? [], raw: data }
  } finally {
    clearTimeout(timeout)
  }
}

export async function verifyFace(
  imageBuffer: Buffer,
  mimeType: string,
): Promise<FaceVerifyResult> {
  const apiKey = process.env.FACEPP_API_KEY
  const apiSecret = process.env.FACEPP_API_SECRET

  if (!apiKey || !apiSecret) {
    throw new Error('Face++ not configured — set FACEPP_API_KEY and FACEPP_API_SECRET in .env')
  }

  console.log(`[face-verify] image size: ${imageBuffer.length} bytes, mime: ${mimeType}`)

  let lastError = 'Unknown error'
  for (const endpoint of FACEPP_ENDPOINTS) {
    try {
      const result = await callFacePlusPlus(endpoint, apiKey, apiSecret, imageBuffer, mimeType)
      if ('errorMessage' in result) {
        lastError = result.errorMessage
        // On authentication-related errors, try the next endpoint region
        if (result.errorMessage.includes('AUTHENTICATION_ERROR') ||
            result.errorMessage.includes('INVALID_API_KEY')) {
          continue
        }
        // On rate-limit or transient errors, don't retry — surface to caller
        throw new Error(result.errorMessage)
      }

      const faceCount = result.faces.length

      if (faceCount === 0) {
        return { verified: false, reason: 'No face detected — please take a clear selfie in good lighting' }
      }
      if (faceCount > 1) {
        return { verified: false, reason: 'Multiple faces detected — please take a solo selfie' }
      }
      return { verified: true, reason: 'Face confirmed' }
    } catch (err: any) {
      lastError = err?.message ?? String(err)
      console.error(`[face-verify] endpoint ${endpoint} failed:`, lastError)
      // Try next region on network/auth failures
    }
  }

  throw new Error(`All Face++ endpoints failed. Last error: ${lastError}`)
}
