import nodemailer, { type Transporter } from 'nodemailer'
import { Resend } from 'resend'

const stripEnv = (v: string | undefined) =>
  (v ?? '').trim().replace(/^["']|["']$/g, '').trim()

const FROM = stripEnv(process.env.EMAIL_FROM) || 'NeedHub <noreply@needhub.app>'

// Provider priority (highest to lowest):
//   1. Brevo  — HTTPS, 300/day free, sender verification only (recommended)
//   2. Resend — HTTPS, 100/day free, sandbox unless domain verified
//   3. Gmail SMTP — blocked by most cloud providers on port 587
//   4. Dev fallback — console.log the code
type Provider = 'brevo' | 'gmail' | 'resend' | 'dev'

let cached: { provider: Provider; transporter?: Transporter; resend?: Resend; brevoKey?: string } | null = null

function pickProvider(): { provider: Provider; transporter?: Transporter; resend?: Resend; brevoKey?: string } {
  if (cached) return cached

  // 1. Brevo (Sendinblue) — best free tier for arbitrary recipients.
  const brevoKey = stripEnv(process.env.BREVO_API_KEY)
  if (brevoKey) {
    cached = { provider: 'brevo', brevoKey }
    return cached
  }

  // 2. Resend — HTTPS-based, works from cloud but has sandbox limit.
  const resendKey = stripEnv(process.env.RESEND_API_KEY)
  if (resendKey) {
    cached = { provider: 'resend', resend: new Resend(resendKey) }
    return cached
  }

  // 3. Gmail SMTP — usually blocked on cloud (Railway, Render, Vercel...).
  const gmailUser = stripEnv(process.env.GMAIL_USER)
  const gmailPass = stripEnv(process.env.GMAIL_APP_PASSWORD).replace(/\s+/g, '')
  if (gmailUser && gmailPass) {
    const transporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 587,
      secure: false,
      auth: { user: gmailUser, pass: gmailPass },
      connectionTimeout: 8000,
      greetingTimeout: 8000,
      socketTimeout: 8000,
    })
    cached = { provider: 'gmail', transporter }
    return cached
  }

  cached = { provider: 'dev' }
  return cached
}

const HTML_TEMPLATE = (code: string) => `
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px;">
  <h2 style="color: #1f2937; margin: 0 0 16px;">Verify your email</h2>
  <p style="color: #4b5563; margin: 0 0 24px;">Enter this code in the NeedHub app to finish signing up.</p>
  <div style="font-size: 36px; font-weight: 700; letter-spacing: 12px; padding: 20px; background: #f3f4f6; border-radius: 12px; text-align: center; color: #111827;">${code}</div>
  <p style="color: #9ca3af; font-size: 13px; margin-top: 20px;">This code expires in 10 minutes. If you didn't request it, you can ignore this email.</p>
</div>
`

const TEXT_TEMPLATE = (code: string) =>
  `Your NeedHub verification code is ${code}. It expires in 10 minutes.`

export async function sendOtp(email: string, code: string): Promise<void> {
  const picked = pickProvider()
  const subject = 'Your NeedHub verification code'
  const html = HTML_TEMPLATE(code)
  const text = TEXT_TEMPLATE(code)

  if (picked.provider === 'dev') {
    console.log(`[email dev-fallback] OTP for ${email}: ${code}`)
    return
  }

  try {
    if (picked.provider === 'brevo' && picked.brevoKey) {
      await sendViaBrevo(picked.brevoKey, email, subject, html, text)
      console.log(`[email:brevo] sent to ${email}`)
      return
    }

    if (picked.provider === 'gmail' && picked.transporter) {
      const info = await picked.transporter.sendMail({ from: FROM, to: email, subject, html, text })
      console.log(`[email:gmail] sent to ${email}, messageId=${info.messageId}`)
      return
    }

    if (picked.provider === 'resend' && picked.resend) {
      const { data, error } = await picked.resend.emails.send({ from: FROM, to: email, subject, html, text })
      if (error) throw new Error(`Resend error: ${JSON.stringify(error)}`)
      console.log(`[email:resend] sent to ${email}, id=${data?.id}`)
      return
    }
  } catch (err) {
    // Provider failed at runtime. Log and swallow — signup should not fail on
    // transient email issues; the user can hit resend, and dev code `000000`
    // always passes as a last resort.
    console.error(`[email:${picked.provider}] failed for ${email}:`, (err as Error).message)
  }
}

async function sendViaBrevo(
  apiKey: string,
  to: string,
  subject: string,
  html: string,
  text: string,
): Promise<void> {
  // Parse "NeedHub <verified@sender.com>" into { name, email } that Brevo needs.
  const match = FROM.match(/^\s*(.*?)\s*<([^>]+)>\s*$/)
  const senderName = match ? match[1] : 'NeedHub'
  const senderEmail = match ? match[2] : FROM.trim()

  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': apiKey,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: { name: senderName, email: senderEmail },
      to: [{ email: to }],
      subject,
      htmlContent: html,
      textContent: text,
    }),
  })
  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`Brevo ${res.status}: ${body.slice(0, 300)}`)
  }
}
