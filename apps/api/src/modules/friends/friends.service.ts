import { prisma } from '../../lib/prisma'

export function sortedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a]
}

export async function isBlockedBetween(a: string, b: string): Promise<boolean> {
  const row = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: a, blockedId: b },
        { blockerId: b, blockedId: a },
      ],
    },
    select: { id: true },
  })
  return row !== null
}

export async function areFriends(a: string, b: string): Promise<boolean> {
  const [x, y] = sortedPair(a, b)
  const row = await prisma.friendship.findUnique({
    where: { userAId_userBId: { userAId: x, userBId: y } },
    select: { id: true },
  })
  return row !== null
}

export async function pendingRequestBetween(a: string, b: string) {
  return prisma.friendRequest.findFirst({
    where: {
      status: 'PENDING',
      OR: [
        { fromUserId: a, toUserId: b },
        { fromUserId: b, toUserId: a },
      ],
    },
  })
}
