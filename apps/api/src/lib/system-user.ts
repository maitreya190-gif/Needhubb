import bcrypt from 'bcryptjs'
import { prisma } from './prisma'
import { config } from '../config'

const SYSTEM_EMAIL = 'system@needhub.internal'

let cachedId: string | null = null

/**
 * Returns the id of the SYSTEM user, creating it if it doesn't exist.
 * SYSTEM is the reporter for every auto-generated moderation Report.
 *
 * Callers can preset SYSTEM_USER_ID in env for stability across restarts;
 * if unset, we get-or-create on first call and cache in memory.
 */
export async function getSystemUserId(): Promise<string> {
  if (cachedId) return cachedId
  if (config.systemUserId) {
    cachedId = config.systemUserId
    return cachedId
  }

  const existing = await prisma.user.findUnique({ where: { email: SYSTEM_EMAIL } })
  if (existing) {
    cachedId = existing.id
    return cachedId
  }

  const created = await prisma.user.create({
    data: {
      email: SYSTEM_EMAIL,
      displayName: 'NeedHub System',
      // Unusable password (bcrypt hash of a random 64-char string it can never guess).
      passwordHash: await bcrypt.hash(Math.random().toString(36).repeat(4), 4),
      emailVerifiedAt: new Date(),
    },
  })
  cachedId = created.id
  return cachedId
}
