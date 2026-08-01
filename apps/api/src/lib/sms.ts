/**
 * Phone OTP delivery — Twilio Verify API.
 *
 * Verify (not raw Messaging) is used deliberately: Twilio's trial-account
 * Messaging API rejects arbitrary free-text SMS bodies ("Trial accounts can
 * only use predefined SMS templates" — error 572006), which broke a plain
 * "send an SMS with our own code" approach. Verify is Twilio's purpose-built
 * OTP product — it generates, sends, and checks the code itself, so we never
 * compose message text and don't hit that restriction.
 *
 * Setup:
 *   1. Sign up at twilio.com.
 *   2. Create a Verify Service (Console → Verify → Services → Create, or via
 *      POST https://verify.twilio.com/v2/Services) — copy its SID (starts "VA").
 *   3. Add to .env:
 *        TWILIO_ACCOUNT_SID=...
 *        TWILIO_AUTH_TOKEN=...
 *        TWILIO_VERIFY_SERVICE_SID=VA...
 *   4. If any of the three are missing, phone verification falls back to our
 *      own locally-generated code (see profiles.router.ts) — the dev OTP
 *      bypass (code 000000) always works regardless.
 */

const stripEnv = (v: string | undefined) => (v ?? '').trim().replace(/^["']|["']$/g, '').trim()

function verifyConfig() {
  return {
    sid: stripEnv(process.env.TWILIO_ACCOUNT_SID),
    token: stripEnv(process.env.TWILIO_AUTH_TOKEN),
    serviceSid: stripEnv(process.env.TWILIO_VERIFY_SERVICE_SID),
  }
}

export function twilioVerifyConfigured(): boolean {
  const { sid, token, serviceSid } = verifyConfig()
  return !!(sid && token && serviceSid)
}

function authHeader(sid: string, token: string) {
  return `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`
}

export async function startPhoneVerification(phone: string): Promise<{ ok: boolean; error?: string }> {
  const { sid, token, serviceSid } = verifyConfig()
  try {
    const res = await fetch(`https://verify.twilio.com/v2/Services/${serviceSid}/Verifications`, {
      method: 'POST',
      headers: {
        Authorization: authHeader(sid, token),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: phone, Channel: 'sms' }),
    })
    const data: any = await res.json().catch(() => ({}))
    if (!res.ok) {
      console.error('[twilio-verify] start failed:', JSON.stringify(data))
      return { ok: false, error: data?.message ?? `Twilio ${res.status}` }
    }
    console.log(`[twilio-verify] verification started for ${phone}, status=${data.status}`)
    return { ok: true }
  } catch (err) {
    console.error('[twilio-verify] start error:', (err as Error).message)
    return { ok: false, error: (err as Error).message }
  }
}

export async function checkPhoneVerification(phone: string, code: string): Promise<{ approved: boolean; error?: string }> {
  const { sid, token, serviceSid } = verifyConfig()
  try {
    const res = await fetch(`https://verify.twilio.com/v2/Services/${serviceSid}/VerificationCheck`, {
      method: 'POST',
      headers: {
        Authorization: authHeader(sid, token),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: phone, Code: code }),
    })
    const data: any = await res.json().catch(() => ({}))
    if (!res.ok) {
      console.error('[twilio-verify] check failed:', JSON.stringify(data))
      return { approved: false, error: data?.message ?? `Twilio ${res.status}` }
    }
    return { approved: data.status === 'approved' }
  } catch (err) {
    console.error('[twilio-verify] check error:', (err as Error).message)
    return { approved: false, error: (err as Error).message }
  }
}
