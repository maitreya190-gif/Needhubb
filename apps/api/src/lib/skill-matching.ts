import { prisma } from './prisma'
import { pushNotification } from './notifications'
import { embedBatch, cosineSimilarity, embeddingsAvailable } from './embeddings'

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371
  const toRad = (d: number) => (d * Math.PI) / 180
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

/** Simple stemmer helper for common skill suffixes (e.g. sketching -> sketch, coding -> code, tutoring -> tutor) */
function stemWord(word: string): string {
  const w = word.toLowerCase()
  if (w.endsWith('ing') && w.length > 5) {
    return w.slice(0, -3) // sketching -> sketch, painting -> paint, tutoring -> tutor
  }
  if (w.endsWith('er') && w.length > 4) {
    return w.slice(0, -2) // painter -> paint, designer -> design
  }
  if (w.endsWith('or') && w.length > 4) {
    return w.slice(0, -2) // tutor -> tut
  }
  if (w.endsWith('s') && w.length > 3) {
    return w.slice(0, -1)
  }
  return w
}

export async function notifyMatchingSkillUsers(need: {
  id: string
  posterId: string
  title: string
  description: string
  earnCategory?: string | null
  connectCategory?: string | null
  lat?: number | null
  lng?: number | null
}) {
  try {
    // 1. Fetch potential users who have skills in their profile (excluding the poster)
    const usersWithSkills = await prisma.user.findMany({
      where: {
        id: { not: need.posterId },
        profile: {
          skills: {
            some: {},
          },
        },
      },
      select: {
        id: true,
        displayName: true,
        profile: {
          select: {
            lat: true,
            lng: true,
            skills: {
              select: {
                skill: { select: { label: true } },
              },
            },
          },
        },
      },
    })

    if (usersWithSkills.length === 0) return

    // Prepare need text signal
    const needText = `${need.title} ${need.description} ${need.earnCategory ?? ''} ${need.connectCategory ?? ''}`.toLowerCase()

    // 2. Optional batch embedding if Cohere is available
    let needVec: number[] | null = null
    if (embeddingsAvailable()) {
      const vecs = await embedBatch([needText], 'search_document')
      if (vecs && vecs[0]) {
        needVec = vecs[0]
      }
    }

    // 3. Evaluate each user
    for (const user of usersWithSkills) {
      if (!user.profile) continue

      // Proximity check: If both need and user have coordinates, check radius (50km)
      if (need.lat != null && need.lng != null && user.profile.lat != null && user.profile.lng != null) {
        const dist = haversineKm(need.lat, need.lng, user.profile.lat, user.profile.lng)
        if (dist > 50) continue // skip users further than 50km
      }

      const userSkillLabels = user.profile.skills.map((s) => s.skill.label.trim())
      if (userSkillLabels.length === 0) continue

      let matchedSkill: string | null = null

      // Check Strategy 1: Substring & Word Root / Stem matching
      for (const skillLabel of userSkillLabels) {
        const sLower = skillLabel.toLowerCase()
        // a) Direct substring
        if (needText.includes(sLower)) {
          matchedSkill = skillLabel
          break
        }
        // b) Word root stemming matching:
        // E.g., "sketching" -> root "sketch", "drawing" -> root "draw", "painting" -> root "paint"
        const words = sLower.split(/\s+/).filter((w) => w.length >= 3)
        for (const w of words) {
          const root = stemWord(w)
          if (root.length >= 3 && needText.includes(root)) {
            matchedSkill = skillLabel
            break
          }
        }
        if (matchedSkill) break
      }

      // Check Strategy 2: Semantic embedding match (if Cohere is available and no keyword match yet)
      if (!matchedSkill && needVec && embeddingsAvailable()) {
        for (const skillLabel of userSkillLabels) {
          const skillVecs = await embedBatch([skillLabel], 'search_query')
          if (skillVecs && skillVecs[0]) {
            const sim = cosineSimilarity(needVec, skillVecs[0])
            if (sim >= 0.45) {
              matchedSkill = skillLabel
              break
            }
          }
        }
      }

      // If matched, send notification to user
      if (matchedSkill) {
        await prisma.$transaction(async (tx) => {
          await pushNotification(tx, {
            userId: user.id,
            type: 'SKILL_MATCH_NEED',
            title: 'Skill Match Found!',
            body: `Someone near you needs exactly what you offer (${matchedSkill}): "${need.title}"`,
            refType: 'need',
            refId: need.id,
          })
        })
      }
    }
  } catch (err) {
    console.error('[skill-matching] Error notifying matching skill users:', err)
  }
}
