import type { Request, Response, NextFunction } from 'express'
import jwt from 'jsonwebtoken'
import { config } from '../config'

export interface AuthedRequest extends Request {
  userId: string
  userEmail: string
}

export function authenticate(req: Request, res: Response, next: NextFunction) {
  const auth = req.headers.authorization
  if (!auth?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or malformed Authorization header', code: 'AUTH_REQUIRED' })
    return
  }

  const token = auth.slice(7)
  try {
    const payload = jwt.verify(token, config.authSecret) as { sub: string; email: string }
    ;(req as AuthedRequest).userId = payload.sub
    ;(req as AuthedRequest).userEmail = payload.email
    next()
  } catch {
    res.status(401).json({ error: 'Invalid or expired token', code: 'AUTH_REQUIRED' })
  }
}
