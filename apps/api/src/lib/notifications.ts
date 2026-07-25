import type { Prisma, NotificationType } from '@prisma/client'

/**
 * Insert a notification for `userId` inside the given Prisma transaction.
 * Callers should pass their tx client so the notification is committed
 * atomically with the write that triggered it.
 *
 * For MESSAGE_RECEIVED notifications, coalesces multiple unread messages
 * from the same sender into a single notification row:
 *   - Title becomes "SenderName (N messages)"
 *   - Body becomes the latest message preview
 *   - createdAt is bumped so it stays at the top of the list
 * Other notification types always create a new row.
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
  // ── Coalesce chat notifications per sender ──────────────────────────
  if (args.type === 'MESSAGE_RECEIVED' && args.refType === 'USER' && args.refId) {
    const existing = await tx.notification.findFirst({
      where: {
        userId: args.userId,
        type: 'MESSAGE_RECEIVED',
        refType: 'USER',
        refId: args.refId,
        readAt: null,          // only coalesce unread notifications
      },
      orderBy: { createdAt: 'desc' },
    })

    if (existing) {
      // Extract current count from title, e.g. "Priya (3 messages)" → 3
      const countMatch = existing.title.match(/\((\d+) messages?\)/)
      const prevCount = countMatch ? parseInt(countMatch[1], 10) : 1
      const newCount = prevCount + 1

      // Strip any existing count suffix to get the clean sender name
      const senderName = args.title.replace(/\s*\(\d+ messages?\)/, '')

      await tx.notification.update({
        where: { id: existing.id },
        data: {
          title: `${senderName} (${newCount} messages)`,
          body: args.body,                  // latest message preview
          createdAt: new Date(),            // bump to top
        },
      })
      return
    }
  }

  // ── Default: create a new notification row ──────────────────────────
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
