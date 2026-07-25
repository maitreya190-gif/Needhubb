import type { Request, Response, NextFunction } from 'express'
import { config } from '../config'

export function adminAuth(req: Request, res: Response, next: NextFunction) {
  const secret = req.headers['x-admin-secret']
  if (!secret || secret !== config.adminSecret) {
    res.status(401).json({ error: 'Unauthorized' })
    return
  }
  next()
}
