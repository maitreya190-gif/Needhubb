import type { Prisma, NotificationType } from '@prisma/client'

/**
 * Insert a notification for `userId` inside the given Prisma transaction.
 * Callers should pass their tx client so the notification is committed
 * atomically with the write that triggered it.
 *
 * Task 14 wires this into every trigger point across the codebase.
 * Until then, callers can `await pushNotification(tx, { ... })` freely —
 * it's a real insert, not a stub.
 */
export async function pushNotification(
  tx: Prisma.TransactionClient,
  args: {
    userId: string
    type: NotificationType
    title: string
    body: string
    refType?: string
    refId?: string
  },
): Promise<void> {
  await tx.notification.create({
    data: {
      userId: args.userId,
      type: args.type,
      title: args.title,
      body: args.body,
      refType: args.refType ?? null,
      refId: args.refId ?? null,
    },
  })
}
