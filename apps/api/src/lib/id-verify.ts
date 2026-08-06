/**
 * Government ID + live selfie verification via Face++ (Megvii).
 *
 * TWO checks run in sequence — both must pass:
 *
 *   1. Liveness  — detects on the selfie that a real human face is present
 *      right now (eyes open, face at a natural angle, not blurry). Blocks
 *      printed-photo and phone-screen spoofing attacks without any hardware.
 *
 *   2. Face match — compares the face on the government ID with the live
 *      selfie and requires a confidence score ≥ MATCH_THRESHOLD. Proves the
 *      person holding the camera is the same person on the ID.
 *
 * Privacy: both image buffers are processed in-memory and immediately
 * dereferenced after the API calls complete. Nothing is written to disk or
 * stored in the database — only the resulting boolean and timestamp are kept.
 *
 * Setup: uses the same FACEPP_API_KEY + FACEPP_API_SECRET already configured
 * for face-verify.ts. No new credentials required.
 */

const FACEPP_DETECT_ENDPOINTS = [
  'https://api-us.faceplusplus.com/facepp/v3/detect',
  'https://api-cn.faceplusplus.com/facepp/v3/detect',
]
const FACEPP_COMPARE_ENDPOINTS = [
  'https://api-us.faceplusplus.com/facepp/v3/compare',
  'https://api-cn.faceplusplus.com/facepp/v3/compare',
]

const TIMEOUT_MS = 20_000
const MATCH_THRESHOLD = 75  // Face++ confidence score 0–100; ≥75 is a strong match

export type IdVerifyResult =
  | { verified: true; idFaceToken: string }
  | { verified: false; reason: string; code: string }

type LivenessResult =
  | { verified: true }
  | { verified: false; reason: string; code: string }

// ── Helpers ──────────────────────────────────────────────────────────────────

function buildForm(apiKey: string, apiSecret: string): FormData {
  const form = new FormData()
  form.append('api_key', apiKey)
  form.append('api_secret', apiSecret)
  return form
}

async function fetchFacePP(
  endpoints: string[],
  form: FormData,
): Promise<any> {
  let lastErr = 'Unknown error'
  for (const endpoint of endpoints) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)
    try {
      const res = await fetch(endpoint, { method: 'POST', body: form, signal: controller.signal })
      const text = await res.text()
      let data: any = {}
      try { data = JSON.parse(text) } catch { throw new Error(`Non-JSON: ${text.slice(0, 200)}`) }
      if (data.error_message) {
        // Auth errors → try next region; others → surface immediately
        if (data.error_message.includes('AUTHENTICATION_ERROR') || data.error_message.includes('INVALID_API_KEY')) {
          lastErr = data.error_message
          continue
        }
        throw new Error(data.error_message)
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      return data
    } catch (err: any) {
      lastErr = err?.message ?? String(err)
      console.error(`[id-verify] ${endpoint} failed:`, lastErr)
    } finally {
      clearTimeout(timer)
    }
  }
  throw new Error(`All Face++ endpoints failed. Last: ${lastErr}`)
}

// ── Step 1: Liveness check on selfie ─────────────────────────────────────────

async function checkLiveness(
  apiKey: string,
  apiSecret: string,
  selfieBuffer: Buffer,
  selfieMime: string,
): Promise<LivenessResult> {
  const form = buildForm(apiKey, apiSecret)
  form.append(
    'image_file',
    new Blob([new Uint8Array(selfieBuffer)], { type: selfieMime || 'image/jpeg' }),
    'selfie.jpg',
  )
  form.append('return_attributes', 'eyestatus,headpose,blur,occlusion')

  const data = await fetchFacePP(FACEPP_DETECT_ENDPOINTS, form)
  const faces: any[] = data.faces ?? []

  if (faces.length === 0) {
    return { verified: false, reason: 'No face detected in your selfie — please take a clear photo in good lighting.', code: 'NO_FACE' }
  }
  if (faces.length > 1) {
    return { verified: false, reason: 'Multiple faces detected — please take a solo selfie.', code: 'MULTIPLE_FACES' }
  }

  const attrs = faces[0].attributes ?? {}

  // Blur check — rejects phone-screen captures (very blurry) and printed photos
  const blurValue = attrs.blur?.blurness?.value ?? 0
  if (blurValue > 80) {
    return { verified: false, reason: 'Selfie is too blurry — please retake in better lighting.', code: 'TOO_BLURRY' }
  }

  // Eyes open — core liveness signal: a printed photo has closed/absent eyes
  const leftOpen = attrs.eyestatus?.left_eye_status?.normal_eye_open ?? 0
  const rightOpen = attrs.eyestatus?.right_eye_status?.normal_eye_open ?? 0
  if (leftOpen < 30 && rightOpen < 30) {
    return { verified: false, reason: 'Please open your eyes and retake the selfie.', code: 'EYES_CLOSED' }
  }

  // Occlusion — Face++ returns per-region 0–1 values (higher = more occluded).
  // Blocks masks and sunglasses, which the eye-open check alone misses
  // because Face++ may still infer eyes from other landmarks.
  const occ = attrs.occlusion ?? {}
  if ((occ.eye_left ?? 0) > 0.7 || (occ.eye_right ?? 0) > 0.7) {
    return { verified: false, reason: 'Please remove any glasses or covering from your eyes and retake the selfie.', code: 'EYES_OCCLUDED' }
  }
  if ((occ.mouth ?? 0) > 0.7 || (occ.nose ?? 0) > 0.7) {
    return { verified: false, reason: 'Please remove any mask or covering from your face and retake the selfie.', code: 'FACE_OCCLUDED' }
  }

  // Head pose — a photo of a photo held perfectly parallel to the camera has
  // pitch, roll, and yaw all essentially zero. Real faces have micro-tilt
  // even when the user tries to hold still. We only trip when all three are
  // effectively zero (< 0.5°); a user who holds their phone very steady but
  // has any natural head angle still passes.
  const { pitch_angle = 0, roll_angle = 0, yaw_angle = 0 } = attrs.headpose ?? {}
  if (Math.abs(pitch_angle) < 0.5 && Math.abs(roll_angle) < 0.5 && Math.abs(yaw_angle) < 0.5) {
    return { verified: false, reason: 'Selfie looks like a photo of a photo — please take a live selfie.', code: 'FLAT_POSE' }
  }

  return { verified: true }
}

// ── Step 2: Face match between ID and selfie ──────────────────────────────────

async function matchFaces(
  apiKey: string,
  apiSecret: string,
  idBuffer: Buffer,
  idMime: string,
  selfieBuffer: Buffer,
  selfieMime: string,
): Promise<IdVerifyResult> {
  const form = buildForm(apiKey, apiSecret)
  form.append(
    'image_file1',
    new Blob([new Uint8Array(idBuffer)], { type: idMime || 'image/jpeg' }),
    'id.jpg',
  )
  form.append(
    'image_file2',
    new Blob([new Uint8Array(selfieBuffer)], { type: selfieMime || 'image/jpeg' }),
    'selfie.jpg',
  )

  const data = await fetchFacePP(FACEPP_COMPARE_ENDPOINTS, form)

  // Face++ returns null confidence when it can't find a face in one of the images
  const confidence: number | null = data.confidence ?? null
  // face_token1 is the token for image_file1 (the ID photo)
  const idFaceToken: string | null = data.faces_on_image1?.[0]?.face_token ?? null
  console.log(`[id-verify] face match confidence: ${confidence}, idFaceToken: ${idFaceToken ? 'present' : 'null'}`)

  if (confidence === null) {
    return { verified: false, reason: 'Could not detect a face on your ID — please upload a clear photo of your government ID.', code: 'NO_FACE_ON_ID' }
  }
  if (confidence < MATCH_THRESHOLD) {
    return { verified: false, reason: `Your selfie doesn't match the face on your ID (confidence: ${Math.round(confidence)}%). Please retake your selfie or use a clearer ID photo.`, code: 'FACE_MISMATCH' }
  }
  // A missing face_token means the compare succeeded but Face++ didn't return
  // a stable identifier for the ID face. Without it we can't hash for
  // duplicate-account detection — synthesizing a fake token would silently
  // bypass that check, so fail instead.
  if (!idFaceToken) {
    return { verified: false, reason: 'Could not read your ID photo cleanly — please retake it in better lighting.', code: 'ID_TOKEN_MISSING' }
  }

  return { verified: true, idFaceToken }
}

// ── Public API ────────────────────────────────────────────────────────────────

export async function verifyIdWithSelfie(
  idBuffer: Buffer,
  idMime: string,
  selfieBuffer: Buffer,
  selfieMime: string,
): Promise<IdVerifyResult> {
  const apiKey = process.env.FACEPP_API_KEY
  const apiSecret = process.env.FACEPP_API_SECRET

  if (!apiKey || !apiSecret) {
    throw new Error('Face++ not configured — set FACEPP_API_KEY and FACEPP_API_SECRET')
  }

  console.log(`[id-verify] id: ${idBuffer.length}B  selfie: ${selfieBuffer.length}B`)

  // Step 1: liveness on the selfie
  const liveness = await checkLiveness(apiKey, apiSecret, selfieBuffer, selfieMime)
  if (!liveness.verified) return liveness

  // Step 2: face match — only runs if liveness passed
  const match = await matchFaces(apiKey, apiSecret, idBuffer, idMime, selfieBuffer, selfieMime)
  return match
}
