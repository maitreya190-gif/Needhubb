export class HttpError extends Error {
  status: number
  code?: string

  constructor(status: number, message: string, code?: string) {
    super(message)
    this.status = status
    this.code = code
    this.name = 'HttpError'
  }
}

export const badRequest = (message: string, code?: string) => new HttpError(400, message, code)
export const unauthorized = (message = 'Unauthorized', code = 'AUTH_REQUIRED') => new HttpError(401, message, code)
export const forbidden = (message: string, code?: string) => new HttpError(403, message, code)
export const notFound = (message = 'Not found', code?: string) => new HttpError(404, message, code)
export const conflict = (message: string, code?: string) => new HttpError(409, message, code)
export const tooMany = (message: string, code?: string) => new HttpError(429, message, code)
export const unprocessable = (message: string, code?: string) => new HttpError(422, message, code)
