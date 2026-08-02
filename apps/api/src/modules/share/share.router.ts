import { Router, type IRouter, type Request } from 'express'
import {
  fetchShareableNeed,
  buildShareCard,
  renderSharePage,
  PLAY_STORE_URL,
  escapeHtml,
} from '../../lib/share-card'
import { config } from '../../config'

export const shareRouter: IRouter = Router()

/**
 * Prefer the host the request actually arrived on so links keep working
 * across local dev, previews and production without an env var having to be
 * set correctly in each. Falls back to the configured base URL.
 */
function baseUrlFor(req: Request): string {
  const host = req.get('host')
  if (!host) return config.apiBaseUrl
  const proto = (req.get('x-forwarded-proto') ?? req.protocol ?? 'https').split(',')[0].trim()
  return `${proto}://${host}`
}

/** Shown when a link points at a Need that is finished, expired or gone. */
function renderUnavailablePage(): string {
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Need unavailable · NeedHub</title>
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    padding:24px; background:#F2E4DE; color:#2B1B16;
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  .card { max-width:400px; width:100%; background:#FBF3EF; border-radius:22px; padding:28px;
    text-align:center; box-shadow:0 18px 40px rgba(43,27,22,.13); }
  h1 { font-size:20px; margin:0 0 10px; }
  p { color:#6C5750; font-size:15px; line-height:1.5; margin:0 0 22px; }
  a { display:block; padding:15px; border-radius:14px; background:#2B1B16; color:#FBF3EF;
    text-decoration:none; font-weight:800; }
</style></head>
<body><main class="card">
  <h1>This need isn't available</h1>
  <p>It may have been completed, closed, or expired. There are plenty more nearby.</p>
  <a href="${escapeHtml(PLAY_STORE_URL)}">Get NeedHub</a>
</main></body></html>`
}

// ─── GET /share/need/:id — share-safe JSON, public by design ──────────────
//
// Public because the whole point is that a recipient who does not have the
// app (and therefore has no token) can still resolve the link. Only ever
// returns the allowlisted ShareCard — see lib/share-card.ts.

shareRouter.get('/need/:id', async (req, res, next) => {
  try {
    const need = await fetchShareableNeed(req.params.id)
    if (!need) {
      return res.status(404).json({ error: 'Need not available for sharing', code: 'NOT_SHAREABLE' })
    }
    res.json(buildShareCard(need, baseUrlFor(req)))
  } catch (err) { next(err) }
})

// ─── GET /n/:id — the web preview a shared link opens ─────────────────────

export const shareLandingRouter: IRouter = Router()

shareLandingRouter.get('/n/:id', async (req, res, next) => {
  try {
    const need = await fetchShareableNeed(req.params.id)
    res.set('Content-Type', 'text/html; charset=utf-8')
    // Short cache: link-preview crawlers hit this repeatedly, but the card
    // must still reflect edits to the Need reasonably quickly.
    res.set('Cache-Control', 'public, max-age=300')
    if (!need) return res.status(404).send(renderUnavailablePage())
    res.send(renderSharePage(buildShareCard(need, baseUrlFor(req))))
  } catch (err) { next(err) }
})
