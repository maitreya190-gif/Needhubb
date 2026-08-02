/**
 * withinEditWindow is the one piece of the message-edit feature worth
 * pinning as pure logic — everything else in PATCH /chats/messages/:id is
 * DB plumbing already covered by the ownership/not-found checks shared with
 * the existing DELETE endpoint.
 */

// messaging.router.ts imports lib/prisma at module load time, which needs
// DATABASE_URL present for the import itself to succeed — same convention
// as needs/__tests__/scoreNeed.test.ts.
import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { EDIT_WINDOW_MS, withinEditWindow } from '../messaging.router'

describe('withinEditWindow', () => {
  it('allows an edit immediately after sending', () => {
    const now = new Date('2026-01-01T00:00:00Z')
    expect(withinEditWindow(now, now)).toBe(true)
  })

  it('allows an edit right up to the 23-minute boundary', () => {
    const createdAt = new Date('2026-01-01T00:00:00Z')
    const now = new Date(createdAt.getTime() + EDIT_WINDOW_MS)
    expect(withinEditWindow(createdAt, now)).toBe(true)
  })

  it('rejects an edit one millisecond past the 23-minute window', () => {
    const createdAt = new Date('2026-01-01T00:00:00Z')
    const now = new Date(createdAt.getTime() + EDIT_WINDOW_MS + 1)
    expect(withinEditWindow(createdAt, now)).toBe(false)
  })

  it('rejects an edit long after sending', () => {
    const createdAt = new Date('2026-01-01T00:00:00Z')
    const now = new Date(createdAt.getTime() + 60 * 60 * 1000)
    expect(withinEditWindow(createdAt, now)).toBe(false)
  })
})
