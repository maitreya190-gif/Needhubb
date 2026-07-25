import type { Request, Response, NextFunction } from 'express'

// TODO: wire up express-rate-limit (or similar) per route group.
// Key routes to limit: POST /needs, POST /responses, POST /messages,
// POST /certificates, POST /achievements — to blunt spam and points gaming.
export function rateLimiter(_req: Request, _res: Response, next: NextFunction) {
  next()
}
