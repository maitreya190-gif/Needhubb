/**
 * Smart Shareable Need Cards — the share-safe view of a Need.
 *
 * Nothing here is stored: a share card is derived on demand from the live
 * Need row, so a link shared today always renders the Need's current title,
 * budget and status the next time anyone opens it. That is deliberate — it
 * satisfies "keep shared cards synchronised" without a second copy of the
 * data to keep in sync, and means sharing adds no write path at all.
 *
 * Two rules govern everything below:
 *   1. Only genuinely public, live Needs are shareable (see isShareable).
 *   2. The payload is an explicit allowlist. Private and internal columns —
 *      lat/lng, urgencyConfidence, renewalGeneration, posterId, responder
 *      identities — are never selected, so they cannot leak by accident the
 *      way a raw row spread would.
 */

import { prisma } from './prisma'

/** A Need is shareable only while it is still open to the public. */
export const SHAREABLE_STATUSES = ['OPEN', 'IN_PROGRESS'] as const

/**
 * Deep link that opens the Need inside the installed app.
 *
 * The empty authority (three slashes) is deliberate: go_router matches on
 * the URI *path*, and with `needhub://need/<id>` the "need" segment would be
 * parsed as the host and dropped, leaving a bare `/<id>` that no route can
 * safely claim. `needhub:///need/<id>` keeps the full `/need/<id>` path.
 */
export function needDeepLink(needId: string): string {
  return `needhub:///need/${needId}`
}

/** Public web preview URL — what actually gets pasted into WhatsApp etc. */
export function needShareUrl(baseUrl: string, needId: string): string {
  return `${baseUrl.replace(/\/+$/, '')}/n/${needId}`
}

export interface ShareCard {
  id: string
  title: string
  /** Trimmed for social display — the full text lives in the app. */
  description: string
  category: string
  /** Human-readable budget, or null when the Need is not paid. */
  budget: string | null
  isUrgent: boolean
  /** ISO string, only when the Need is urgent and still has a deadline. */
  expiresAt: string | null
  /** City / neighbourhood only. Never coordinates. */
  location: string | null
  poster: { displayName: string; avatarUrl: string | null }
  shareUrl: string
  deepLink: string
}

const MAX_SHARE_DESCRIPTION = 180

function shortenDescription(text: string): string {
  const clean = text.replace(/\s+/g, ' ').trim()
  if (clean.length <= MAX_SHARE_DESCRIPTION) return clean
  return `${clean.slice(0, MAX_SHARE_DESCRIPTION - 1).trimEnd()}…`
}

/** Turns the enum columns into something a stranger can actually read. */
function categoryLabel(need: {
  needType: string
  earnCategory: string | null
  connectCategory: string | null
}): string {
  const raw = need.needType === 'EARN' ? need.earnCategory : need.connectCategory
  if (!raw) return need.needType === 'EARN' ? 'Earn' : 'Connect'
  return raw
    .split('_')
    .map((w) => w.charAt(0) + w.slice(1).toLowerCase())
    .join(' ')
}

function budgetLabel(need: {
  isPaid: boolean
  budgetMin: number | null
  budgetMax: number | null
}): string | null {
  if (!need.isPaid) return null
  const { budgetMin: min, budgetMax: max } = need
  if (min != null && max != null) {
    return min === max ? `₹${Math.round(min)}` : `₹${Math.round(min)}–₹${Math.round(max)}`
  }
  if (max != null) return `Up to ₹${Math.round(max)}`
  if (min != null) return `From ₹${Math.round(min)}`
  return null
}

type ShareableNeedRow = {
  id: string
  title: string
  description: string
  needType: string
  earnCategory: string | null
  connectCategory: string | null
  isPaid: boolean
  budgetMin: number | null
  budgetMax: number | null
  locationText: string | null
  status: string
  isUrgent: boolean
  deadline: Date | null
  poster: { displayName: string; profile: { avatarUrl: string | null } | null }
}

/**
 * Requirement: never share a private, expired, deleted or restricted Need.
 * Deleted rows simply are not found; the rest is status plus the urgency
 * deadline, mirroring the read-time expiry rule in lib/urgency.ts so an
 * urgent Need whose deadline has passed stops being shareable immediately,
 * without waiting for the status flip to be written.
 */
export function isShareable(need: ShareableNeedRow, now: Date = new Date()): boolean {
  if (!(SHAREABLE_STATUSES as readonly string[]).includes(need.status)) return false
  if (need.isUrgent && need.deadline && need.deadline.getTime() <= now.getTime()) return false
  return true
}

export function buildShareCard(need: ShareableNeedRow, baseUrl: string): ShareCard {
  return {
    id: need.id,
    title: need.title,
    description: shortenDescription(need.description),
    category: categoryLabel(need),
    budget: budgetLabel(need),
    isUrgent: need.isUrgent,
    expiresAt: need.isUrgent && need.deadline ? need.deadline.toISOString() : null,
    location: need.locationText,
    poster: {
      displayName: need.poster.displayName,
      avatarUrl: need.poster.profile?.avatarUrl ?? null,
    },
    shareUrl: needShareUrl(baseUrl, need.id),
    deepLink: needDeepLink(need.id),
  }
}

/**
 * Loads a Need for sharing, or null when it does not exist or is not
 * eligible. Selects an explicit allowlist — adding a private column to the
 * Need model can therefore never widen what sharing exposes.
 */
export async function fetchShareableNeed(needId: string): Promise<ShareableNeedRow | null> {
  try {
    const need = await prisma.need.findUnique({
      where: { id: needId },
      select: {
        id: true,
        title: true,
        description: true,
        needType: true,
        earnCategory: true,
        connectCategory: true,
        isPaid: true,
        budgetMin: true,
        budgetMax: true,
        locationText: true,
        status: true,
        isUrgent: true,
        deadline: true,
        poster: {
          select: {
            displayName: true,
            profile: { select: { avatarUrl: true } },
          },
        },
      },
    })
    if (!need) return null
    return isShareable(need as ShareableNeedRow) ? (need as ShareableNeedRow) : null
  } catch (err) {
    console.error('[share-card] failed to load need', needId, err)
    return null
  }
}

// ── Web preview page ──────────────────────────────────────────────────────

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

/** Play Store listing — the install target when the app is missing. */
export const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.needhub.needhub'

/**
 * The page a recipient without the app lands on. Server-rendered with
 * OpenGraph tags so WhatsApp/X/Telegram show a rich preview of the card
 * itself, plus a smart CTA: try the deep link first, fall back to install.
 */
export function renderSharePage(card: ShareCard): string {
  const title = escapeHtml(card.title)
  const description = escapeHtml(card.description)
  const category = escapeHtml(card.category)
  const posterName = escapeHtml(card.poster.displayName)
  const location = card.location ? escapeHtml(card.location) : null
  const budget = card.budget ? escapeHtml(card.budget) : null
  const ogDescription = escapeHtml(
    [card.budget, card.location, `Posted by ${card.poster.displayName}`]
      .filter(Boolean)
      .join(' · '),
  )

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · NeedHub</title>
<meta name="description" content="${description}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="NeedHub">
<meta property="og:title" content="${title}">
<meta property="og:description" content="${ogDescription}">
<meta property="og:url" content="${escapeHtml(card.shareUrl)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${title}">
<meta name="twitter:description" content="${ogDescription}">
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; padding: 24px;
    background: #F2E4DE;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #2B1B16;
  }
  .card {
    width: 100%; max-width: 420px; background: #FBF3EF; border-radius: 22px;
    padding: 26px; box-shadow: 0 18px 40px rgba(43,27,22,.13);
  }
  .brand { display: flex; align-items: center; gap: 9px; margin-bottom: 20px; }
  .brand-mark {
    width: 26px; height: 26px; border-radius: 8px;
    background: linear-gradient(135deg,#1F5C43 50%, #E2603C 50%);
  }
  .brand-name { font-weight: 800; letter-spacing: -.2px; }
  .chips { display: flex; flex-wrap: wrap; gap: 7px; margin-bottom: 14px; }
  .chip {
    font-size: 12px; font-weight: 700; padding: 5px 10px; border-radius: 999px;
    background: rgba(31,92,67,.12); color: #1F5C43;
  }
  .chip.urgent { background: rgba(226,96,60,.14); color: #C2451F; }
  .chip.budget { background: rgba(196,138,45,.16); color: #8A5D12; }
  h1 { font-size: 22px; line-height: 1.25; margin: 0 0 10px; }
  .desc { font-size: 15px; line-height: 1.5; color: #6C5750; margin: 0 0 18px; }
  .meta { font-size: 13px; color: #6C5750; margin-bottom: 22px; }
  .meta strong { color: #2B1B16; }
  .cta {
    display: block; width: 100%; text-align: center; text-decoration: none;
    padding: 15px; border-radius: 14px; font-weight: 800; font-size: 15px;
    background: #2B1B16; color: #FBF3EF; margin-bottom: 10px;
  }
  .cta.secondary { background: transparent; color: #2B1B16; border: 1.5px solid rgba(43,27,22,.22); }
  .foot { font-size: 12px; color: #8A7970; text-align: center; margin: 16px 0 0; }
</style>
</head>
<body>
  <main class="card">
    <div class="brand"><div class="brand-mark"></div><div class="brand-name">NeedHub</div></div>
    <div class="chips">
      <span class="chip">${category}</span>
      ${card.isUrgent ? '<span class="chip urgent">Urgent</span>' : ''}
      ${budget ? `<span class="chip budget">${budget}</span>` : ''}
    </div>
    <h1>${title}</h1>
    <p class="desc">${description}</p>
    <p class="meta">
      Posted by <strong>${posterName}</strong>${location ? ` · ${location}` : ''}
    </p>
    <a class="cta" id="open-app" href="${escapeHtml(card.deepLink)}">Open in NeedHub</a>
    <a class="cta secondary" href="${PLAY_STORE_URL}">Install NeedHub</a>
    <p class="foot">Meet people nearby through what you both love.</p>
  </main>
<script>
  // Smart deep link: if the app is installed the custom scheme takes over
  // and the page is backgrounded, so the visibility check below never fires.
  // If nothing handles it, we're still here after the timeout — send them to
  // the store instead of leaving a dead button.
  (function () {
    var link = document.getElementById('open-app');
    link.addEventListener('click', function (e) {
      e.preventDefault();
      var start = Date.now();
      var t = setTimeout(function () {
        if (document.hidden || Date.now() - start > 2200) return;
        window.location.href = ${JSON.stringify(PLAY_STORE_URL)};
      }, 1400);
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) clearTimeout(t);
      });
      window.location.href = ${JSON.stringify(card.deepLink)};
    });
  })();
</script>
</body>
</html>`
}
