import { Router, type IRouter } from 'express'
import multer from 'multer'
import { prisma } from '../../lib/prisma'
import { authenticate, type AuthedRequest } from '../../middleware/authenticate'
import { badRequest } from '../../lib/http-error'
import { uploadFile, storageKey } from '../../lib/storage'

export const certificatesRouter: IRouter = Router()

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      cb(new Error('Only image files are allowed'))
    } else {
      cb(null, true)
    }
  },
})

certificatesRouter.post('/', authenticate, upload.single('file'), async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId
    const { type, description } = req.body as { type?: string; description?: string }

    if (!req.file) return next(badRequest('Image file is required', 'FILE_REQUIRED'))

    const certType = (type ?? 'OTHER') as any
    const key = storageKey(`certs/${userId}`, req.file.originalname)
    const fileUrl = await uploadFile(key, req.file.buffer, req.file.mimetype)

    const cert = await prisma.certificate.create({
      data: {
        userId: userId!,
        type: certType,
        description: description ?? null,
        fileUrl,
        status: 'PENDING_REVIEW',
      },
    })

    res.status(201).json(cert)
  } catch (err) {
    next(err)
  }
})

certificatesRouter.get('/mine', authenticate, async (req, res, next) => {
  try {
    const userId = (req as AuthedRequest).userId
    const certs = await prisma.certificate.findMany({
      where: { userId: userId! },
      orderBy: { createdAt: 'desc' },
    })
    res.json(certs)
  } catch (err) {
    next(err)
  }
})
