import { Server } from 'socket.io'
import type { Server as HttpServer } from 'http'
import jwt from 'jsonwebtoken'
import { config } from '../config'

let _io: Server | null = null

// userId -> set of connected socket ids. A user is "online" iff this set is
// non-empty — supports multiple simultaneous devices/tabs correctly, since
// presence only flips to offline once every socket has disconnected.
const onlineSockets = new Map<string, Set<string>>()

function markSocketOnline(userId: string, socketId: string): void {
  const existing = onlineSockets.get(userId)
  if (existing) existing.add(socketId)
  else onlineSockets.set(userId, new Set([socketId]))
}

function markSocketOffline(userId: string, socketId: string): void {
  const existing = onlineSockets.get(userId)
  if (!existing) return
  existing.delete(socketId)
  if (existing.size === 0) onlineSockets.delete(userId)
}

// Raw connection check — callers combine this with the user's
// showOnlineStatus preference via computeIsOnline() in lib/presence.ts.
export function isUserConnected(userId: string): boolean {
  return (onlineSockets.get(userId)?.size ?? 0) > 0
}

export function initSocket(httpServer: HttpServer): Server {
  _io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    transports: ['websocket', 'polling'],
    allowUpgrades: true,
    pingTimeout: 60000,
    pingInterval: 25000,
  })

  _io.use((socket, next) => {
    const token = (socket.handshake.auth?.token as string | undefined)
      ?? (socket.handshake.query?.token as string | undefined)
      ?? (socket.handshake.headers?.authorization as string | undefined)?.replace('Bearer ', '')
    console.log('[socket] handshake token present:', !!token, 'transport:', socket.conn.transport.name)
    if (!token) {
      const err = new Error('AUTH_REQUIRED')
      ;(err as any).data = { code: 'AUTH_REQUIRED' }
      return next(err)
    }
    try {
      const payload = jwt.verify(token, config.authSecret) as { sub: string }
      socket.data.userId = payload.sub
      console.log('[socket] auth ok for user:', payload.sub)
      next()
    } catch (e) {
      console.log('[socket] auth failed:', (e as Error).message)
      const err = new Error('AUTH_INVALID')
      ;(err as any).data = { code: 'AUTH_INVALID' }
      next(err)
    }
  })

  _io.on('connection', (socket) => {
    const userId = socket.data.userId as string
    // Each user joins their own private room for personal events
    socket.join(`user:${userId}`)
    markSocketOnline(userId, socket.id)

    // Client joins a thread room when opening a conversation
    socket.on('join_thread', (threadId: string) => {
      if (typeof threadId === 'string') socket.join(`thread:${threadId}`)
    })
    socket.on('leave_thread', (threadId: string) => {
      if (typeof threadId === 'string') socket.leave(`thread:${threadId}`)
    })
    socket.on('disconnect', () => {
      markSocketOffline(userId, socket.id)
    })
  })

  return _io
}

export function getIo(): Server | null {
  return _io
}

// Emit to a specific user's private room — safe, never throws
export function emitToUser(userId: string, event: string, data: unknown): void {
  try { _io?.to(`user:${userId}`).emit(event, data) } catch {}
}

// Emit to everyone in a thread room — safe, never throws
export function emitToThread(threadId: string, event: string, data: unknown): void {
  try { _io?.to(`thread:${threadId}`).emit(event, data) } catch {}
}
