/**
 * One-off: nuke any Profile rows where personalityTraits is malformed
 * (missing fields, wrong types). This lets affected users retake the
 * quiz cleanly. Idempotent — safe to run repeatedly.
 */
import { prisma } from '../src/lib/prisma'

const REQUIRED = [
  'openness',
  'conscientiousness',
  'extraversion',
  'agreeableness',
  'emotionalStability',
] as const

async function main() {
  const rows = await prisma.profile.findMany({
    where: { personalityTakenAt: { not: null } },
    select: { id: true, userId: true, personalityTraits: true, personalityNickname: true },
  })
  console.log(`inspecting ${rows.length} profiles with personality data`)
  let cleaned = 0
  for (const row of rows) {
    const t = row.personalityTraits as Record<string, unknown> | null
    const bad = !t || REQUIRED.some((k) => typeof t[k] !== 'number')
    if (bad) {
      console.log(`  wiping bad row user=${row.userId} nickname=${row.personalityNickname}`)
      await prisma.profile.update({
        where: { id: row.id },
        data: {
          personalityTraits: null as never,
          personalityNickname: null,
          personalitySummary: null,
          personalityVibeTags: [],
          personalityTakenAt: null,
        },
      })
      cleaned++
    }
  }
  console.log(`done — cleaned ${cleaned} bad rows`)
  await prisma.$disconnect()
}

main().catch((e) => { console.error(e); process.exit(1) })
