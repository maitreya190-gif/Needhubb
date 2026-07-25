import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME
const CLOUDINARY_UPLOAD_PRESET = process.env.CLOUDINARY_UPLOAD_PRESET
const cloudinaryConfigured = !!(CLOUDINARY_CLOUD_NAME && CLOUDINARY_UPLOAD_PRESET)

const API_BASE_URL = process.env.API_BASE_URL ?? 'http://localhost:3000'
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads')

function ensureDir(dir: string) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true })
}

async function uploadToCloudinary(buffer: Buffer, mimeType: string, key: string): Promise<string> {
  const ext = path.extname(key)
  // Strip extension from public_id — Cloudinary appends it automatically.
  const publicId = key.replace(/\.[^/.]+$/, '')

  const form = new FormData()
  form.append('file', new Blob([buffer], { type: mimeType }), `upload${ext}`)
  form.append('upload_preset', CLOUDINARY_UPLOAD_PRESET!)
  form.append('public_id', publicId)

  const res = await fetch(
    `https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/auto/upload`,
    { method: 'POST', body: form },
  )

  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Cloudinary upload failed (${res.status}): ${body}`)
  }

  const json = (await res.json()) as { secure_url: string }
  return json.secure_url
}

function uploadToLocal(buffer: Buffer, key: string): string {
  const dest = path.join(UPLOADS_DIR, key)
  ensureDir(path.dirname(dest))
  fs.writeFileSync(dest, buffer)
  return `${API_BASE_URL}/uploads/${key}`
}

export async function uploadFile(key: string, buffer: Buffer, mimeType: string): Promise<string> {
  if (cloudinaryConfigured) return uploadToCloudinary(buffer, mimeType, key)
  return uploadToLocal(buffer, key)
}

export async function deleteFile(key: string): Promise<void> {
  if (!cloudinaryConfigured) {
    const dest = path.join(UPLOADS_DIR, key)
    if (fs.existsSync(dest)) fs.unlinkSync(dest)
  }
  // Cloudinary deletion requires signed API — skip for now; files are cheap and quota is large.
}

export function storageKey(prefix: string, originalName: string): string {
  const ext = path.extname(originalName).toLowerCase() || '.bin'
  return `${prefix}/${crypto.randomUUID()}${ext}`
}
