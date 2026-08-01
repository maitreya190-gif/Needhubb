import 'dotenv/config'
import { describe, it, expect, afterAll, beforeAll } from 'vitest'
import { prisma } from '../../../lib/prisma'
import { notifyMatchingSkillUsers } from '../../../lib/skill-matching'

const RUN_ID = Date.now()
const email = (n: number) => `skillmatch-test-${RUN_ID}-${n}@needhub.dev`

let userAId: string // User who has 'sketching' skill
let userBId: string // User who posts the need

beforeAll(async () => {
  // Create User A with skill 'sketching'
  const userA = await prisma.user.create({
    data: {
      email: email(1),
      displayName: 'Sketcher Alice',
      passwordHash: 'dummyhash',
      emailVerifiedAt: new Date(),
    },
  })
  userAId = userA.id

  const profileA = await prisma.profile.create({
    data: {
      userId: userA.id,
      bio: 'Loves drawing and sketching portraits',
      lat: 12.9352,
      lng: 77.6245,
    },
  })

  const skillRecord = await prisma.skill.upsert({
    where: { label: 'sketching' },
    update: {},
    create: { label: 'sketching' },
  })

  await prisma.profileSkill.create({
    data: {
      profileId: profileA.id,
      skillId: skillRecord.id,
    },
  })

  // Create User B (poster)
  const userB = await prisma.user.create({
    data: {
      email: email(2),
      displayName: 'Poster Bob',
      passwordHash: 'dummyhash',
      emailVerifiedAt: new Date(),
    },
  })
  userBId = userB.id

  await prisma.profile.create({
    data: {
      userId: userB.id,
      lat: 12.9360,
      lng: 77.6250, // near User A (within 1km)
    },
  })
})

afterAll(async () => {
  await prisma.notification.deleteMany({
    where: { userId: { in: [userAId, userBId] } },
  })
  await prisma.profileSkill.deleteMany({
    where: { profile: { userId: { in: [userAId, userBId] } } },
  })
  await prisma.profile.deleteMany({
    where: { userId: { in: [userAId, userBId] } },
  })
  await prisma.user.deleteMany({
    where: { id: { in: [userAId, userBId] } },
  })
})

describe('Skill Matching Notification System', () => {
  it('notifies user with matching skill when a related need is posted near them', async () => {
    // User B posts a need for a sketch
    const need = await prisma.need.create({
      data: {
        posterId: userBId,
        title: 'Make a sketch for a friend as her bday gift',
        description: 'I want to make a sketch for my friend as her birthday gift. Need someone skilled in portrait drawing.',
        needType: 'EARN',
        earnCategory: 'FREELANCE',
        isPaid: true,
        budgetMin: 1500,
        budgetMax: 3000,
        lat: 12.9360,
        lng: 77.6250,
      },
    })

    // Trigger skill matching
    await notifyMatchingSkillUsers(need)

    // Verify notification was delivered to User A
    const notifs = await prisma.notification.findMany({
      where: {
        userId: userAId,
        type: 'SKILL_MATCH_NEED',
      },
    })

    expect(notifs.length).toBeGreaterThanOrEqual(1)
    const targetNotif = notifs.find((n) => n.refId === need.id)
    expect(targetNotif).toBeDefined()
    expect(targetNotif?.title).toBe('Skill Match Found!')
    expect(targetNotif?.body).toContain('Someone near you needs exactly what you offer')
    expect(targetNotif?.body).toContain('sketching')
    expect(targetNotif?.refType).toBe('need')

    // Clean up created test need
    await prisma.need.delete({ where: { id: need.id } })
  })

  it('does NOT notify poster themselves when they post a need matching their own skill', async () => {
    // User A posts a need
    const need = await prisma.need.create({
      data: {
        posterId: userAId,
        title: 'Need another sketch artist',
        description: 'Looking for a sketch artist to collaborate',
        needType: 'CONNECT',
        connectCategory: 'HOBBY',
        isPaid: false,
      },
    })

    await notifyMatchingSkillUsers(need)

    // User A should NOT get a notification for their own post
    const selfNotifs = await prisma.notification.findMany({
      where: {
        userId: userAId,
        refId: need.id,
      },
    })

    expect(selfNotifs.length).toBe(0)

    await prisma.need.delete({ where: { id: need.id } })
  })
})
