'use client'
import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { getSecret } from '@/lib/api'

export default function Root() {
  const router = useRouter()
  useEffect(() => {
    router.replace(getSecret() ? '/dashboard' : '/login')
  }, [router])
  return null
}
