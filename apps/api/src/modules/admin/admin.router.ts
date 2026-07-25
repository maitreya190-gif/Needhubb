import { Router, type Router as ExpressRouter } from 'express'
import { prisma } from '../../lib/prisma'
import { pushNotification } from '../../lib/notifications'

export const adminRouter: ExpressRouter = Router()

// ── Stats overview ────────────────────────────────────────────────────────────

adminRouter.get('/stats', async (_req, res) => {
  const [users, needs, pendingCerts, openReports] = await Promise.all([
    prisma.user.count(),
    prisma.need.count(),
    prisma.certificate.count({ where: { status: 'PENDING_REVIEW' } }),
    prisma.report.count({ where: { status: 'OPEN' } }),
  ])
  res.json({ users, needs, pendingCerts, openReports })
})

// ── Certificates ──────────────────────────────────────────────────────────────

adminRouter.get('/certificates', async (req, res) => {
  const status = (req.query.status as string) || 'PENDING_REVIEW'
  const certs = await prisma.certificate.findMany({
    where: { status: status as any },
    include: { user: { select: { id: true, displayName: true, email: true } } },
    orderBy: { createdAt: 'desc' },
  })
  res.json(certs)
})

adminRouter.patch('/certificates/:id', async (req, res, next) => {
  const { id } = req.params
  const { status, pointsAwarded } = req.body as {
    status: 'APPROVED' | 'REJECTED'
    pointsAwarded?: number
  }

  try {
    const result = await prisma.$transaction(async (tx) => {
      const cert = await tx.certificate.update({
        where: { id },
        data: { status, pointsAwarded: pointsAwarded ?? null },
      })

      if (status === 'APPROVED' && pointsAwarded && pointsAwarded > 0) {
        await tx.pointsLedger.create({
          data: {
            userId: cert.userId,
            delta: pointsAwarded,
            reason: `Certificate approved: ${cert.type}`,
            refId: cert.id,
          },
        })
        await tx.profile.upsert({
          where: { userId: cert.userId },
          update: { pointsTotal: { increment: pointsAwarded } },
          create: { userId: cert.userId, pointsTotal: pointsAwarded },
        })
        await pushNotification(tx, {
          userId: cert.userId,
          type: 'CERT_APPROVED',
          title: 'Certificate approved!',
          body: `Your ${cert.type.replace(/_/g, ' ').toLowerCase()} certificate was approved. You earned ${pointsAwarded} points.`,
          refType: 'CERTIFICATE',
          refId: cert.id,
        })
      } else if (status === 'REJECTED') {
        await pushNotification(tx, {
          userId: cert.userId,
          type: 'CERT_REJECTED',
          title: 'Certificate not approved',
          body: `Your ${cert.type.replace(/_/g, ' ').toLowerCase()} certificate could not be verified. You may resubmit with clearer documentation.`,
          refType: 'CERTIFICATE',
          refId: cert.id,
        })
      }

      return cert
    })

    res.json(result)
  } catch (err) { next(err) }
})

// ── Reports ───────────────────────────────────────────────────────────────────

adminRouter.get('/reports', async (req, res) => {
  const targetType = req.query.targetType as string | undefined
  const status = (req.query.status as string) || 'OPEN'
  const source = req.query.source as string | undefined

  const reports = await prisma.report.findMany({
    where: {
      status: status as any,
      ...(targetType ? { targetType: targetType as any } : {}),
      ...(source ? { meta: { source } } : {}),
    },
    include: {
      reporter: { select: { id: true, displayName: true, email: true } },
      meta: true,
    },
    orderBy: { createdAt: 'desc' },
  })
  res.json(await enrichReportsWithTargets(reports))
})

// Dedicated queue for auto-flagged content so admins can triage them first.
adminRouter.get('/moderation/flags', async (req, res) => {
  const source = (req.query.source as string) || 'moderation_hard'
  const status = (req.query.status as string) || 'OPEN'
  const reports = await prisma.report.findMany({
    where: { status: status as any, meta: { source } },
    include: {
      reporter: { select: { id: true, displayName: true, email: true } },
      meta: true,
    },
    orderBy: { createdAt: 'desc' },
  })
  res.json(await enrichReportsWithTargets(reports))
})

/**
 * For each report, resolve the target's actual content so admins see what was
 * flagged instead of an opaque id. For MESSAGE reports, also attaches the last
 * 20 messages from the thread so admins have full context.
 */
async function enrichReportsWithTargets(reports: any[]) {
  return Promise.all(
    reports.map(async (r) => {
      let target: Record<string, any> | null = null

      if (r.targetType === 'USER') {
        const u = await prisma.user.findUnique({
          where: { id: r.targetId },
          select: { id: true, displayName: true, email: true },
        })
        if (u) target = { kind: 'USER', ...u }
      } else if (r.targetType === 'NEED') {
        if (r.targetId.startsWith('pending:')) {
          const posterId = r.targetId.slice('pending:'.length)
          const poster = await prisma.user.findUnique({
            where: { id: posterId },
            select: { id: true, displayName: true },
          })
          target = {
            kind: 'NEED',
            pending: true,
            posterId,
            posterName: poster?.displayName ?? 'Unknown',
            blockedText: (r.meta?.detail as any)?.text ?? null,
          }
        } else {
          const need = await prisma.need.findUnique({
            where: { id: r.targetId },
            select: {
              id: true, title: true, description: true,
              needType: true, status: true,
              poster: { select: { id: true, displayName: true } },
            },
          })
          if (need) {
            target = {
              kind: 'NEED',
              id: need.id,
              title: need.title,
              description: need.description,
              needType: need.needType,
              status: need.status,
              posterId: need.poster.id,
              posterName: need.poster.displayName,
            }
          }
        }
      } else if (r.targetType === 'MESSAGE') {
        const dm = await prisma.dmMessage.findUnique({
          where: { id: r.targetId },
          select: {
            id: true, body: true, imageUrl: true, createdAt: true,
            threadId: true,
            sender: { select: { id: true, displayName: true } },
          },
        })
        if (dm) {
          // Fetch last 20 messages from the thread for admin context.
          const contextMessages = await prisma.dmMessage.findMany({
            where: { threadId: dm.threadId },
            include: { sender: { select: { id: true, displayName: true } } },
            orderBy: { createdAt: 'desc' },
            take: 20,
          })
          target = {
            kind: 'MESSAGE',
            id: dm.id,
            body: dm.body,
            imageUrl: dm.imageUrl,
            createdAt: dm.createdAt,
            senderId: dm.sender.id,
            senderName: dm.sender.displayName,
            contextMessages: contextMessages.reverse(),
          }
        }
      }

      return { ...r, target }
    }),
  )
}

adminRouter.patch('/reports/:id/resolve', async (req, res, next) => {
  const { id } = req.params
  const { action, message } = req.body as {
    action: 'dismiss' | 'warn' | 'warn_user' | 'ban_user' | 'remove_need' | 'remove_message'
    message?: string
  }

  try {
    const report = await prisma.$transaction(async (tx) => {
      const updated = await tx.report.update({
        where: { id },
        data: { status: 'RESOLVED' },
      })

      // Normalize warn_user (sent by admin portal) → warn (internal name).
      const act = action === 'warn_user' ? 'warn' : action

      if (act === 'warn') {
        let warnUserId: string | null = null
        if (updated.targetType === 'USER') {
          warnUserId = updated.targetId
        } else if (updated.targetType === 'NEED') {
          if (updated.targetId.startsWith('pending:')) {
            warnUserId = updated.targetId.slice('pending:'.length)
          } else {
            const need = await tx.need.findUnique({
              where: { id: updated.targetId },
              select: { posterId: true },
            })
            warnUserId = need?.posterId ?? null
          }
        } else if (updated.targetType === 'MESSAGE') {
          const dm = await tx.dmMessage.findUnique({
            where: { id: updated.targetId },
            select: { senderId: true },
          })
          warnUserId = dm?.senderId ?? null
        }

        if (warnUserId) {
          await pushNotification(tx, {
            userId: warnUserId,
            type: 'REPORT_ACTIONED',
            title: 'Warning from moderators',
            body: message?.trim() || 'Your content was flagged and reviewed by our team. Please follow community guidelines.',
            refType: 'REPORT',
            refId: id,
          })
        }
      } else if (act === 'ban_user' && updated.targetType === 'USER') {
        await tx.user.delete({ where: { id: updated.targetId } })
      } else if (act === 'remove_need' && updated.targetType === 'NEED') {
        const need = await tx.need.findUnique({
          where: { id: updated.targetId },
          select: { posterId: true, title: true },
        })
        if (need) {
          await pushNotification(tx, {
            userId: need.posterId,
            type: 'REPORT_ACTIONED',
            title: 'Your post was removed',
            body: `Your post "${need.title}" was removed for violating community guidelines.`,
            refType: 'REPORT',
            refId: id,
          })
          await tx.need.delete({ where: { id: updated.targetId } })
        }
      } else if (act === 'remove_message' && updated.targetType === 'MESSAGE') {
        const dm = await tx.dmMessage.findUnique({
          where: { id: updated.targetId },
          select: { id: true, senderId: true },
        })
        if (dm) {
          await pushNotification(tx, {
            userId: dm.senderId,
            type: 'REPORT_ACTIONED',
            title: 'Message removed',
            body: 'One of your messages was removed for violating community guidelines.',
            refType: 'REPORT',
            refId: id,
          })
          await tx.dmMessage.delete({ where: { id: updated.targetId } })
        } else {
          await tx.message.deleteMany({ where: { id: updated.targetId } })
        }
      }

      return updated
    })

    res.json({ ok: true, report })
  } catch (err) { next(err) }
})

// ── Users ─────────────────────────────────────────────────────────────────────

adminRouter.get('/users', async (req, res) => {
  const search = req.query.search as string | undefined
  const take = Math.min(Number(req.query.take) || 50, 200)
  const skip = Number(req.query.skip) || 0

  const users = await prisma.user.findMany({
    where: search
      ? {
          OR: [
            { displayName: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
          ],
        }
      : undefined,
    select: {
      id: true,
      displayName: true,
      email: true,
      verificationLevel: true,
      createdAt: true,
      _count: { select: { needs: true, reports: true } },
    },
    orderBy: { createdAt: 'desc' },
    take,
    skip,
  })
  res.json(users)
})

adminRouter.delete('/users/:id', async (req, res) => {
  await prisma.user.delete({ where: { id: req.params.id } })
  res.json({ ok: true })
})

// ── Needs ─────────────────────────────────────────────────────────────────────

adminRouter.get('/needs', async (req, res) => {
  const status = req.query.status as string | undefined
  const take = Math.min(Number(req.query.take) || 50, 200)
  const skip = Number(req.query.skip) || 0

  const needs = await prisma.need.findMany({
    where: status ? { status: status as any } : undefined,
    include: {
      poster: { select: { id: true, displayName: true, email: true } },
    },
    orderBy: { createdAt: 'desc' },
    take,
    skip,
  })
  res.json(needs)
})

adminRouter.delete('/needs/:id', async (req, res) => {
  await prisma.need.delete({ where: { id: req.params.id } })
  res.json({ ok: true })
})
