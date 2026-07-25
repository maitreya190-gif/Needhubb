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

adminRouter.patch('/certificates/:id', async (req, res) => {
  const { id } = req.params
  const { status, pointsAwarded } = req.body as {
    status: 'APPROVED' | 'REJECTED'
    pointsAwarded?: number
  }

  const cert = await prisma.certificate.update({
    where: { id },
    data: { status, pointsAwarded: pointsAwarded ?? null },
  })

  if (status === 'APPROVED' && pointsAwarded) {
    await prisma.pointsLedger.create({
      data: {
        userId: cert.userId,
        delta: pointsAwarded,
        reason: `Certificate approved: ${cert.type}`,
        refId: cert.id,
      },
    })
    await prisma.profile.upsert({
      where: { userId: cert.userId },
      update: { pointsTotal: { increment: pointsAwarded } },
      create: { userId: cert.userId, pointsTotal: pointsAwarded },
    })
  }

  res.json(cert)
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
 * flagged instead of an opaque id. Attaches a `target` object with the fields
 * the admin panel renders (title/body/posterName for NEEDs, name/email for
 * USERs, body/senderName for MESSAGEs). Auto-moderation reports whose targetId
 * starts with "pending:" also get the intended text via meta.detail.
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
          // Auto-moderation report for a need that was blocked before creation.
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
            // The blocked text is captured in ReportMeta.detail (matches + reasons).
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
            sender: { select: { id: true, displayName: true } },
          },
        })
        if (dm) {
          target = {
            kind: 'MESSAGE',
            id: dm.id,
            body: dm.body,
            imageUrl: dm.imageUrl,
            createdAt: dm.createdAt,
            senderId: dm.sender.id,
            senderName: dm.sender.displayName,
          }
        }
      }

      return { ...r, target }
    }),
  )
}

adminRouter.patch('/reports/:id/resolve', async (req, res) => {
  const { id } = req.params
  const { action, message } = req.body as {
    action: 'dismiss' | 'warn' | 'ban_user' | 'remove_need' | 'remove_message'
    message?: string
  }

  const report = await prisma.$transaction(async (tx) => {
    const updated = await tx.report.update({
      where: { id },
      data: { status: 'RESOLVED' },
    })

    if (action === 'warn') {
      // Resolve the target user:
      //   - USER report → targetId is the userId directly
      //   - NEED report → look up the poster
      //   - Auto-blocked moderation reports use targetId format "pending:{userId}"
      //     because the need was rejected before creation. Parse that too.
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
    } else if (action === 'ban_user' && updated.targetType === 'USER') {
      await tx.user.delete({ where: { id: updated.targetId } })
    } else if (action === 'remove_need' && updated.targetType === 'NEED') {
      await tx.need.delete({ where: { id: updated.targetId } })
    } else if (action === 'remove_message' && updated.targetType === 'MESSAGE') {
      const dm = await tx.dmMessage.findUnique({ where: { id: updated.targetId }, select: { id: true } })
      if (dm) {
        await tx.dmMessage.delete({ where: { id: updated.targetId } })
      } else {
        await tx.message.deleteMany({ where: { id: updated.targetId } })
      }
    }

    return updated
  })

  res.json({ ok: true, report })
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
