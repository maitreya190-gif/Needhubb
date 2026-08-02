import 'dotenv/config'
import { describe, it, expect } from 'vitest'
import { createNeedBody, editResponseBody } from '../needs.schemas'
import { z } from 'zod'

const editNeedSchema = z.object({
  title: z.string().min(3).max(120).optional(),
  description: z.string().min(5).max(3000).optional(),
  category: z.string().optional(),
  budgetMin: z.number().int().min(0).nullable().optional(),
  budgetMax: z.number().int().min(0).nullable().optional(),
  locationText: z.string().optional(),
  deadline: z.string().nullable().optional(),
  peopleNeeded: z.number().int().min(1).max(100).optional(),
})

describe('Multi-person freezing schemas', () => {
  it('defaults peopleNeeded to 1 when omitted in createNeedBody', () => {
    const payload = {
      needs: [
        {
          title: 'Need 5 volunteers for beach cleanup',
          description: 'Help us clean the beach this Sunday morning.',
          needType: 'CONNECT',
          earnCategory: null,
          connectCategory: 'ACTIVITY_PARTNER',
          budgetMin: null,
          budgetMax: null,
          deadline: null,
        },
      ],
    }
    const res = createNeedBody.safeParse(payload)
    expect(res.success).toBe(true)
    if (res.success) {
      expect(res.data.needs[0].peopleNeeded).toBe(1)
    }
  })

  it('accepts explicit peopleNeeded in createNeedBody', () => {
    const payload = {
      needs: [
        {
          title: 'Need 10 event organizers',
          description: 'Looking for 10 people to help organize hackathon.',
          needType: 'CONNECT',
          earnCategory: null,
          connectCategory: 'OTHER',
          budgetMin: null,
          budgetMax: null,
          deadline: null,
          peopleNeeded: 10,
        },
      ],
    }
    const res = createNeedBody.safeParse(payload)
    expect(res.success).toBe(true)
    if (res.success) {
      expect(res.data.needs[0].peopleNeeded).toBe(10)
    }
  })

  it('rejects invalid peopleNeeded (e.g. less than 1 or non-integer)', () => {
    const payloadZero = {
      needs: [
        {
          title: 'Invalid count',
          description: 'Describing invalid need count.',
          needType: 'CONNECT',
          earnCategory: null,
          connectCategory: null,
          budgetMin: null,
          budgetMax: null,
          deadline: null,
          peopleNeeded: 0,
        },
      ],
    }
    expect(createNeedBody.safeParse(payloadZero).success).toBe(false)
  })

  it('validates peopleNeeded in editNeedSchema', () => {
    const validEdit = editNeedSchema.safeParse({ peopleNeeded: 5 })
    expect(validEdit.success).toBe(true)
    if (validEdit.success) {
      expect(validEdit.data.peopleNeeded).toBe(5)
    }

    const invalidEdit = editNeedSchema.safeParse({ peopleNeeded: -2 })
    expect(invalidEdit.success).toBe(false)
  })
})
