import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest } from '../../lib/http-error'
import { uploadFile, storageKey } from '../../lib/storage'

export const achievementsRouter: IRouter = Router()

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) cb(new Error('Images only'))
    else cb(null, true)
  },
})

// POST /achievements — multipart { title, description, category, file? }
achievementsRouter.post('/', authenticate, upload.single('file'), async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const { title, description, category } = req.body as {
      title?: string; description?: string; category?: string
    }
    if (!title || !description || !category) {
      return next(badRequest('title, description, category required', 'INVALID_BODY'))
    }

    let fileUrl: string | null = null
    if (req.file) {
      const key = storageKey(`achievements/${me}`, req.file.originalname)
      fileUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)
    }

    const row = await prisma.achievement.create({
      data: {
        userId: me,
        title,
        description,
        category: category as any,
        fileUrl,
        status: 'PENDING_REVIEW',
      },
    })
    res.status(201).json(row)
  } catch (err) { next(err) }
})

// GET /achievements/mine
achievementsRouter.get('/mine', authenticate, async (req, res, next) => {
  try {
    const me = (req as unknown as AuthedRequest).userId!
    const rows = await prisma.achievement.findMany({
      where: { userId: me }, orderBy: { createdAt: 'desc' },
    })
    res.json(rows)
  } catch (err) { next(err) }
})
