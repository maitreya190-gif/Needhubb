import { describe, it, expect } from 'vitest'
import { computeIsOnline } from '../presence'

describe('computeIsOnline', () => {
  it('is online only when connected AND visible', () => {
    expect(computeIsOnline(true, true)).toBe(true)
  })

  it('is never online while disconnected, regardless of the privacy toggle', () => {
    expect(computeIsOnline(true, false)).toBe(false)
    expect(computeIsOnline(false, false)).toBe(false)
  })

  it('is never online when the user has hidden their status, even while connected', () => {
    expect(computeIsOnline(false, true)).toBe(false)
  })
})
