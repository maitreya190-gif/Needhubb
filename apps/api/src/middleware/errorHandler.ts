import type { Request, Response, NextFunction } from 'express'
import { HttpError } from '../lib/http-error'

export function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message, code: err.code })
    return
  }
  if (err instanceof Error) {
    console.error('[unhandled]', err.stack ?? err.message)
    res.status(500).json({ error: 'Internal server error', code: 'INTERNAL' })
    return
  }
  console.error('[unhandled non-Error]', err)
  res.status(500).json({ error: 'Internal server error', code: 'INTERNAL' })
}
