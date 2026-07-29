import { Server } from 'socket.io'
import type { Server as HttpServer } from 'http'
import jwt from 'jsonwebtoken'
import { config } from '../config'

let _io: Server | null = null

export function initSocket(httpServer: HttpServer): Server {
  _io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    transports: ['websocket', 'polling'],
    allowUpgrades: true,
    pingTimeout: 60000,
    pingInterval: 25000,
  })

  _io.use((socket, next) => {
    const token = socket.handshake.auth?.token as string | undefined
    if (!token) return next(new Error('AUTH_REQUIRED'))
    try {
      const payload = jwt.verify(token, config.authSecret) as { sub: string }
      socket.data.userId = payload.sub
      next()
    } catch {
      next(new Error('AUTH_INVALID'))
    }
  })

  _io.on('connection', (socket) => {
    const userId = socket.data.userId as string
    // Each user joins their own private room for personal events
    socket.join(`user:${userId}`)

    // Client joins a thread room when opening a conversation
    socket.on('join_thread', (threadId: string) => {
      if (typeof threadId === 'string') socket.join(`thread:${threadId}`)
    })
    socket.on('leave_thread', (threadId: string) => {
      if (typeof threadId === 'string') socket.leave(`thread:${threadId}`)
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
