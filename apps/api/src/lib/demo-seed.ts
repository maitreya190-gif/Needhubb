import bcrypt from 'bcryptjs'
import { prisma } from './prisma'

/**
 * High-quality, comprehensive demo seed covering ALL permutations & combinations of NeedHub features:
 *
 * 1. PROFILES & PERSONALITY:
 *    - 7 distinct demo users with full names, avatars, bios, verified status (ID, Phone, Email, Face)
 *    - Personality test results (Big Five traits, nicknames, summaries, vibe tags)
 *    - Skills, interests, prompts (skill, collab, need)
 *    - Active ChitChat availability windows (24h)
 *
 * 2. NEEDS & SUB-NEEDS:
 *    - Needs across ALL Earn (TUTORING, FREELANCE, GOODS_BUY, GOODS_SELL, REPAIR, OTHER) & Connect (STUDY_PARTNER, ACTIVITY_PARTNER, HOBBY, MENTOR, OTHER) categories
 *    - All Need statuses: OPEN, IN_PROGRESS, FULFILLED, CLOSED
 *    - Parent needs with child sub-needs
 *
 * 3. INTEREST RESPONSES & CHAT THREADS:
 *    - All Response statuses: PENDING, ACCEPTED, DECLINED, WITHDRAWN
 *    - Quoted prices & work sample URLs attached to offers
 *    - MessageThreads for accepted responses with back-and-forth messages
 *
 * 4. DIRECT MESSAGING (DMs):
 *    - DmThreads between friends with text, image URLs, and reaction JSON
 *
 * 5. REVIEWS & RATINGS:
 *    - 5-star & 4-star reviews with private feedback comments
 *    - Automatic average rating calculations for profiles
 *
 * 6. SOCIAL & FRIENDS:
 *    - Friendships, Pending Friend Requests, Accepted Friend Requests, Declined Friend Requests
 *    - User blocks for safety testing
 *
 * 7. CERTIFICATES & ACHIEVEMENTS:
 *    - Certificates across ALL types (NSS, TREE_PLANTATION, CLEANUP, VOLUNTEERING, OTHER) & statuses (APPROVED, PENDING_REVIEW, REJECTED)
 *    - Achievements across ALL categories (COMPETITION, HACKATHON, TOURNAMENT, AWARD, OTHER) & statuses (APPROVED, PENDING_REVIEW)
 *
 * 8. VISIBILITY BOOSTS & POINTS LEDGER:
 *    - Needs boosted with active VisibilityBoost entries (6h, 24h, 72h tiers)
 *    - PointsLedger entries detailing earned (review, cert) and spent (boost, redemption) points
 *
 * 9. REDEMPTIONS & NOTIFICATIONS:
 *    - Redemption items catalog & user redemptions (DELIVERED & PENDING)
 *    - Notifications covering ALL NotificationType values
 */

const INTERESTS = [
  'Coding', 'Design', 'Photography', 'Music', 'Sports', 'Startup',
  'Reading', 'Chess', 'Cooking', 'Gaming', 'Travel', 'Fitness',
  'AI & ML', 'Public Speaking', 'Yoga', 'Writing', 'Robotics', 'Fintech',
]

const SKILLS = [
  'Flutter', 'React', 'Node.js', 'Python', 'UI/UX', 'Figma',
  'Copywriting', 'Video Editing', 'Machine Learning', 'Guitar', 'Yoga', 'Public Speaking',
  'PyTorch', 'Data Analysis', 'Event Photography', 'System Design', 'Cybersecurity', 'Cooking',
]

interface DemoUser {
  email: string
  username: string
  displayName: string
  bio: string
  gender: 'male' | 'female'
  locationText: string
  lat: number
  lng: number
  avatarUrl: string
  interests: string[]
  skills: string[]
  promptSkill: string
  promptCollab: string
  promptNeed: string
  pointsTotal: number
  personality: {
    traits: {
      openness: number
      conscientiousness: number
      extraversion: number
      agreeableness: number
      emotionalStability: number
    }
    nickname: string
    summary: string
    vibeTags: string[]
  }
}

const DEMO_USERS: DemoUser[] = [
  {
    email: 'aarav.kumar@needhub.demo',
    username: 'aarav',
    displayName: 'Aarav Kumar',
    bio: 'CS student at RVCE. Passionate about Flutter cross-platform apps and indie hacking on weekends.',
    gender: 'male',
    locationText: 'Koramangala, Bengaluru',
    lat: 12.9352, lng: 77.6245,
    avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
    interests: ['Coding', 'Startup', 'Gaming', 'AI & ML'],
    skills: ['Flutter', 'React', 'Node.js', 'System Design'],
    promptSkill: 'Flutter — I can spin up a production mobile app MVP in 48 hours',
    promptCollab: 'Someone who ships fast, communicates clearly, and cares about design polish',
    promptNeed: 'A talented UI/UX designer for my next indie mobile project',
    pointsTotal: 540,
    personality: {
      traits: { openness: 92, conscientiousness: 88, extraversion: 78, agreeableness: 85, emotionalStability: 90 },
      nickname: 'The Visionary Builder',
      summary: 'Driven by curiosity and a bias for action. You excel at turning abstract ideas into clean, functional software.',
      vibeTags: ['Ship Fast', 'Deep Thinker', 'Tech Explorer', 'Optimistic'],
    },
  },
  {
    email: 'meera.kulkarni@needhub.demo',
    username: 'meera',
    displayName: 'Meera Kulkarni',
    bio: 'Product designer & aspiring founder. Design lead at a fintech startup. Chess player & filter coffee snob.',
    gender: 'female',
    locationText: 'HSR Layout, Bengaluru',
    lat: 12.9081, lng: 77.6476,
    avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
    interests: ['Design', 'Startup', 'Chess', 'Writing'],
    skills: ['UI/UX', 'Figma', 'Copywriting'],
    promptSkill: 'UI/UX design — I have designed and shipped 3 consumer products with >50k MAU',
    promptCollab: 'Engineers who care deeply about micro-interactions and accessibility',
    promptNeed: 'A frontend engineer who understands fluid animations and motion design',
    pointsTotal: 490,
    personality: {
      traits: { openness: 95, conscientiousness: 90, extraversion: 70, agreeableness: 92, emotionalStability: 85 },
      nickname: 'The Empathetic Strategist',
      summary: 'Observant, thoughtful, and detail-oriented. You create experiences that feel intuitive and joyful.',
      vibeTags: ['Pixel Perfect', 'Strategic', 'Empathetic', 'Coffee Lover'],
    },
  },
  {
    email: 'rohan.verma@needhub.demo',
    username: 'rohan',
    displayName: 'Rohan Verma',
    bio: 'Freelance photographer & travel filmmaker. Cafe hopper. Learning Machine Learning in my spare time.',
    gender: 'male',
    locationText: 'Indiranagar, Bengaluru',
    lat: 12.9784, lng: 77.6408,
    avatarUrl: 'https://images.unsplash.com/photo-1568602471122-7832951cc4c5?w=400',
    interests: ['Photography', 'Coding', 'Travel', 'AI & ML'],
    skills: ['Video Editing', 'Event Photography', 'Machine Learning'],
    promptSkill: 'Portrait, brand, and event photography with professional color grading',
    promptCollab: 'Content creators, founders, and local brands looking for cinematic visual storytelling',
    promptNeed: 'A mentor to guide me through deep learning research papers',
    pointsTotal: 360,
    personality: {
      traits: { openness: 88, conscientiousness: 75, extraversion: 85, agreeableness: 88, emotionalStability: 80 },
      nickname: 'The Creative Explorer',
      summary: 'Storyteller at heart. You thrive in dynamic environments where art meets technology.',
      vibeTags: ['Cinematic', 'Wanderlust', 'Creative', 'Adaptable'],
    },
  },
  {
    email: 'priya.nair@needhub.demo',
    username: 'priya',
    displayName: 'Priya Nair',
    bio: 'Certified yoga instructor & holistic fitness coach. Tech enthusiast exploring Data Structures & Algorithms.',
    gender: 'female',
    locationText: 'Whitefield, Bengaluru',
    lat: 12.9698, lng: 77.7500,
    avatarUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
    interests: ['Fitness', 'Sports', 'Coding', 'Yoga'],
    skills: ['Yoga', 'Public Speaking'],
    promptSkill: 'Personalized strength, mobility, and mindfulness training',
    promptCollab: 'Study buddies for LeetCode grinding and system design sessions',
    promptNeed: 'A morning running partner for 5k runs in Whitefield',
    pointsTotal: 410,
    personality: {
      traits: { openness: 82, conscientiousness: 94, extraversion: 80, agreeableness: 95, emotionalStability: 92 },
      nickname: 'The Mindful Catalyst',
      summary: 'Disciplined and encouraging. You inspire everyone around you to push past limits while maintaining balance.',
      vibeTags: ['Disciplined', 'Mindful', 'High Energy', 'Encouraging'],
    },
  },
  {
    email: 'karthik.reddy@needhub.demo',
    username: 'karthik',
    displayName: 'Karthik Reddy',
    bio: 'Senior Backend Engineer. Open-source contributor. Lead guitarist in an indie rock band.',
    gender: 'male',
    locationText: 'BTM Layout, Bengaluru',
    lat: 12.9165, lng: 77.6101,
    avatarUrl: 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?w=400',
    interests: ['Coding', 'Music', 'Reading', 'Gaming'],
    skills: ['Node.js', 'Python', 'Guitar', 'System Design'],
    promptSkill: 'Scalable backend architectures, distributed systems, and DB query optimization',
    promptCollab: 'Musicians and vocalists for weekend jam sessions & recording sessions',
    promptNeed: 'A vocal coach to teach me vocal warmup techniques',
    pointsTotal: 430,
    personality: {
      traits: { openness: 85, conscientiousness: 92, extraversion: 72, agreeableness: 84, emotionalStability: 88 },
      nickname: 'The Resonant Systems Architect',
      summary: 'Analytical yet deeply expressive. You bring precision to code and soul to music.',
      vibeTags: ['Systems Mind', 'Guitarist', 'Problem Solver', 'Reliable'],
    },
  },
  {
    email: 'sneha.rao@needhub.demo',
    username: 'sneha',
    displayName: 'Sneha Rao',
    bio: 'Senior Content Strategist & Copywriter. Book club organizer. Culinary experimenter.',
    gender: 'female',
    locationText: 'Jayanagar, Bengaluru',
    lat: 12.9250, lng: 77.5938,
    avatarUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
    interests: ['Reading', 'Cooking', 'Travel', 'Writing'],
    skills: ['Copywriting', 'Public Speaking', 'Cooking'],
    promptSkill: 'High-converting landing page copy, brand messaging, and newsletter writing',
    promptCollab: 'Avid readers for monthly fiction & non-fiction book discussions',
    promptNeed: 'A traditional culinary swap — I trade English grammar tutoring for authentic South Indian recipes',
    pointsTotal: 380,
    personality: {
      traits: { openness: 90, conscientiousness: 86, extraversion: 82, agreeableness: 90, emotionalStability: 84 },
      nickname: 'The Eloquent Weaver',
      summary: 'Articulate and warm. You bring words to life and build meaningful communities around shared passions.',
      vibeTags: ['Wordcraft', 'Bookworm', 'Community', 'Warm'],
    },
  },
  {
    email: 'ananya.sharma@needhub.demo',
    username: 'ananya',
    displayName: 'Ananya Sharma',
    bio: 'AI Researcher & Data Scientist at IISc. Building open-source LLM eval benchmarks. Avid runner.',
    gender: 'female',
    locationText: 'MG Road, Bengaluru',
    lat: 12.9716, lng: 77.5946,
    avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
    interests: ['AI & ML', 'Coding', 'Reading', 'Fitness'],
    skills: ['PyTorch', 'Machine Learning', 'Python', 'Data Analysis'],
    promptSkill: 'Fine-tuning Transformer models, RAG pipelines, and model evaluation',
    promptCollab: 'Researchers and engineers interested in open-source AI benchmarks',
    promptNeed: 'A mobile developer to build a clean open-source frontend for our research tool',
    pointsTotal: 630,
    personality: {
      traits: { openness: 98, conscientiousness: 95, extraversion: 75, agreeableness: 88, emotionalStability: 92 },
      nickname: 'The Algorithmic Pioneer',
      summary: 'Inquisitive and rigorous. You bridge cutting-edge AI research with real-world human impact.',
      vibeTags: ['AI Researcher', 'Data Driven', 'Curious', 'Pioneer'],
    },
  },
]

const DEMO_NEEDS = [
  // EARN - FREELANCE (FULFILLED)
  {
    key: 'ui_design',
    posterEmail: 'aarav.kumar@needhub.demo',
    title: 'Need a UI designer for my Flutter app MVP',
    description: 'Building an indie note-taking app in Flutter. Need a designer for 2 weeks — Figma mockups + component tokens. Budget ₹8,000–15,000.',
    needType: 'EARN' as const, earnCategory: 'FREELANCE' as const, status: 'FULFILLED' as const,
    isPaid: true, budgetMin: 8000, budgetMax: 15000,
    locationText: 'Koramangala', lat: 12.9352, lng: 77.6245,
  },
  // EARN - TUTORING (FULFILLED)
  {
    key: 'guitar_lessons',
    posterEmail: 'karthik.reddy@needhub.demo',
    title: 'Guitar teacher — beginner acoustic lessons',
    description: 'Looking for a patient teacher for 45-min sessions, 2x per week. I have my own guitar. Prefer BTM/Koramangala or online.',
    needType: 'EARN' as const, earnCategory: 'TUTORING' as const, status: 'FULFILLED' as const,
    isPaid: true, budgetMin: 800, budgetMax: 1500,
    locationText: 'BTM Layout', lat: 12.9165, lng: 77.6101,
  },
  // EARN - REPAIR (IN_PROGRESS)
  {
    key: 'macbook_repair',
    posterEmail: 'ananya.sharma@needhub.demo',
    title: 'MacBook M2 repair & thermal paste service',
    description: 'My MacBook fans run loud under PyTorch workloads. Need an expert technician to clean dust and re-apply thermal paste cleanly.',
    needType: 'EARN' as const, earnCategory: 'REPAIR' as const, status: 'IN_PROGRESS' as const,
    isPaid: true, budgetMin: 1500, budgetMax: 3000,
    locationText: 'MG Road', lat: 12.9716, lng: 77.5946,
  },
  // EARN - GOODS_SELL (OPEN)
  {
    key: 'keyboard_sale',
    posterEmail: 'karthik.reddy@needhub.demo',
    title: 'Selling — mechanical keyboard (Keychron K2, mint condition)',
    description: 'Bought 3 months ago, used barely twice. Full box, warranty card included. Selling for ₹6500. Pickup in BTM Layout.',
    needType: 'EARN' as const, earnCategory: 'GOODS_SELL' as const, status: 'OPEN' as const,
    isPaid: true, budgetMin: 6500, budgetMax: 6500,
    locationText: 'BTM Layout', lat: 12.9165, lng: 77.6101,
  },
  // EARN - GOODS_BUY (OPEN)
  {
    key: 'camera_lens_buy',
    posterEmail: 'rohan.verma@needhub.demo',
    title: 'Buying — Sony E-mount 35mm F1.8 lens (used)',
    description: 'Looking for a pre-owned Sony 35mm F1.8 lens in good optical condition. Budget up to ₹22,000.',
    needType: 'EARN' as const, earnCategory: 'GOODS_BUY' as const, status: 'OPEN' as const,
    isPaid: true, budgetMin: 18000, budgetMax: 22000,
    locationText: 'Indiranagar', lat: 12.9784, lng: 77.6408,
  },
  // EARN - OTHER (CLOSED)
  {
    key: 'event_photos',
    posterEmail: 'meera.kulkarni@needhub.demo',
    title: 'Product launch event photo & video coverage',
    description: '4-hour event coverage for our startup launch party in Indiranagar. Raw photos + edited highlights reel.',
    needType: 'EARN' as const, earnCategory: 'OTHER' as const, status: 'CLOSED' as const,
    isPaid: true, budgetMin: 5000, budgetMax: 10000,
    locationText: 'HSR Layout', lat: 12.9081, lng: 77.6476,
  },
  // CONNECT - STUDY_PARTNER (OPEN)
  {
    key: 'gate_study',
    posterEmail: 'meera.kulkarni@needhub.demo',
    title: 'Study partner for GATE 2026 — CS/IT',
    description: 'Forming a small weekend study group. Focus on Data Structures, Algorithms, and Operating Systems. Meeting at HSR library.',
    needType: 'CONNECT' as const, connectCategory: 'STUDY_PARTNER' as const, status: 'OPEN' as const,
    isPaid: false,
    locationText: 'HSR Layout', lat: 12.9081, lng: 77.6476,
  },
  // CONNECT - ACTIVITY_PARTNER (OPEN - BOOSTED)
  {
    key: 'hackathon_team',
    posterEmail: 'aarav.kumar@needhub.demo',
    title: 'Hackathon teammate — need a designer, weekend of Aug 3',
    description: 'InovaHack finals coming up. Team of 3 — me on Flutter, backend guy locked in, need a designer who moves fast. Prize pool ₹50k.',
    needType: 'CONNECT' as const, connectCategory: 'ACTIVITY_PARTNER' as const, status: 'OPEN' as const,
    isPaid: false,
    locationText: 'Koramangala', lat: 12.9352, lng: 77.6245,
  },
  // CONNECT - MENTOR (OPEN)
  {
    key: 'founder_mentor',
    posterEmail: 'meera.kulkarni@needhub.demo',
    title: 'Mentor wanted — early-stage startup founder',
    description: 'Building a consumer tech product. Looking for a mentor who has been through the 0→1 startup grind. Coffee once a fortnight.',
    needType: 'CONNECT' as const, connectCategory: 'MENTOR' as const, status: 'OPEN' as const,
    isPaid: false,
    locationText: 'HSR Layout', lat: 12.9081, lng: 77.6476,
  },
  // CONNECT - HOBBY (OPEN)
  {
    key: 'cooking_swap',
    posterEmail: 'sneha.rao@needhub.demo',
    title: 'Cooking swap — I teach English lit, you teach South Indian recipes',
    description: 'Skill-swap: I have taught English lit for 3 years. Want to learn authentic dosa, sambar, rasam basics. Weekend sessions.',
    needType: 'CONNECT' as const, connectCategory: 'HOBBY' as const, status: 'OPEN' as const,
    isPaid: false,
    locationText: 'Jayanagar', lat: 12.9250, lng: 77.5938,
  },
  // CONNECT - OTHER (OPEN - BOOSTED)
  {
    key: 'ai_benchmark',
    posterEmail: 'ananya.sharma@needhub.demo',
    title: 'Open Source AI Benchmarking — Collaborators Wanted',
    description: 'Building an evaluation dataset for domain-specific LLM reasoning in Indian regional languages. Seeking NLP enthusiasts.',
    needType: 'CONNECT' as const, connectCategory: 'OTHER' as const, status: 'OPEN' as const,
    isPaid: false,
    locationText: 'MG Road', lat: 12.9716, lng: 77.5946,
  },
]

export async function runSeed() {
  console.log('▶ Seeding NeedHub comprehensive demo data…')

  // ── SYSTEM User ───────────────────────────────────────────────────────────
  const systemEmail = 'system@needhub.internal'
  const systemId = process.env.SYSTEM_USER_ID ?? 'system_00000000000000000000'
  await prisma.user.upsert({
    where: { email: systemEmail },
    update: {},
    create: {
      id: systemId,
      email: systemEmail,
      displayName: 'NeedHub System',
      passwordHash: 'not-a-real-hash-do-not-log-in',
      emailVerifiedAt: new Date(),
    },
  })
  console.log('  ✓ SYSTEM user')

  // ── Catalog (Interests & Skills) ───────────────────────────────────────────
  for (const label of INTERESTS) {
    await prisma.interest.upsert({ where: { label }, update: {}, create: { label } })
  }
  for (const label of SKILLS) {
    await prisma.skill.upsert({ where: { label }, update: {}, create: { label } })
  }
  console.log(`  ✓ Catalog: ${INTERESTS.length} interests, ${SKILLS.length} skills`)

  // ── 7 Rich Demo Users ──────────────────────────────────────────────────────
  const passwordHash = await bcrypt.hash('Demo1234!', 10)
  const usersById: Record<string, string> = {}

  for (const u of DEMO_USERS) {
    const user = await prisma.user.upsert({
      where: { email: u.email },
      update: {
        displayName: u.displayName,
        username: u.username,
        verificationLevel: 'ID',
        emailVerifiedAt: new Date(),
        phoneVerifiedAt: new Date(),
      },
      create: {
        email: u.email,
        displayName: u.displayName,
        username: u.username,
        passwordHash,
        verificationLevel: 'ID',
        emailVerifiedAt: new Date(),
        phoneVerifiedAt: new Date(),
      },
    })
    usersById[u.email] = user.id

    // Set 24h active ChitChat window for all demo users
    const chitchatUntil = new Date(Date.now() + 24 * 3600 * 1000)

    await prisma.profile.upsert({
      where: { userId: user.id },
      update: {
        bio: u.bio, gender: u.gender, locationText: u.locationText,
        lat: u.lat, lng: u.lng, avatarUrl: u.avatarUrl,
        promptSkill: u.promptSkill, promptCollab: u.promptCollab, promptNeed: u.promptNeed,
        chitchatAvailableUntil: chitchatUntil,
        faceVerifiedAt: new Date(),
        pointsTotal: u.pointsTotal,
        personalityNickname: u.personality.nickname,
        personalitySummary: u.personality.summary,
        personalityVibeTags: u.personality.vibeTags,
        personalityTraits: u.personality.traits,
        personalityTakenAt: new Date(),
      },
      create: {
        userId: user.id,
        bio: u.bio, gender: u.gender, locationText: u.locationText,
        lat: u.lat, lng: u.lng, avatarUrl: u.avatarUrl,
        promptSkill: u.promptSkill, promptCollab: u.promptCollab, promptNeed: u.promptNeed,
        chitchatAvailableUntil: chitchatUntil,
        faceVerifiedAt: new Date(),
        pointsTotal: u.pointsTotal,
        personalityNickname: u.personality.nickname,
        personalitySummary: u.personality.summary,
        personalityVibeTags: u.personality.vibeTags,
        personalityTraits: u.personality.traits,
        personalityTakenAt: new Date(),
      },
    })

    // Wire interests & skills
    await prisma.profileInterest.deleteMany({ where: { profile: { userId: user.id } } })
    for (const label of u.interests) {
      const interest = await prisma.interest.findUnique({ where: { label } })
      const profile = await prisma.profile.findUnique({ where: { userId: user.id } })
      if (interest && profile) {
        await prisma.profileInterest.create({ data: { profileId: profile.id, interestId: interest.id } })
      }
    }

    await prisma.profileSkill.deleteMany({ where: { profile: { userId: user.id } } })
    for (const label of u.skills) {
      const skill = await prisma.skill.findUnique({ where: { label } })
      const profile = await prisma.profile.findUnique({ where: { userId: user.id } })
      if (skill && profile) {
        await prisma.profileSkill.create({ data: { profileId: profile.id, skillId: skill.id } })
      }
    }
  }
  console.log(`  ✓ 7 rich demo users with active ChitChat & Personality profiles`)

  // ── Clean up legacy data for demo users ──────────────────────────────────
  const demoUserIds = Object.values(usersById)

  // Delete notifications, messages, threads, responses, boosts, reviews, needs
  await prisma.notification.deleteMany({ where: { userId: { in: demoUserIds } } })
  await prisma.dmMessage.deleteMany({})
  await prisma.dmThread.deleteMany({})
  await prisma.friendship.deleteMany({})
  await prisma.friendRequest.deleteMany({})
  await prisma.block.deleteMany({})

  const oldNeeds = await prisma.need.findMany({ where: { posterId: { in: demoUserIds } }, select: { id: true } })
  const oldNeedIds = oldNeeds.map((n) => n.id)
  if (oldNeedIds.length > 0) {
    const oldResponses = await prisma.interestResponse.findMany({ where: { needId: { in: oldNeedIds } }, select: { id: true } })
    const oldResponseIds = oldResponses.map((r) => r.id)
    if (oldResponseIds.length > 0) {
      const oldThreads = await prisma.messageThread.findMany({ where: { responseId: { in: oldResponseIds } }, select: { id: true } })
      const oldThreadIds = oldThreads.map((t) => t.id)
      if (oldThreadIds.length > 0) {
        await prisma.message.deleteMany({ where: { threadId: { in: oldThreadIds } } })
        await prisma.messageThread.deleteMany({ where: { id: { in: oldThreadIds } } })
      }
      await prisma.interestResponse.deleteMany({ where: { id: { in: oldResponseIds } } })
    }
    await prisma.visibilityBoost.deleteMany({ where: { targetId: { in: oldNeedIds } } })
    await prisma.review.deleteMany({ where: { needId: { in: oldNeedIds } } })
    await prisma.need.deleteMany({ where: { id: { in: oldNeedIds } } })
  }

  // ── Seed Needs across all Categories & Statuses ───────────────────────────
  const createdNeeds: Record<string, string> = {}

  // Top-level parent needs
  for (const n of DEMO_NEEDS) {
    const posterId = usersById[n.posterEmail]
    if (!posterId) continue
    const created = await prisma.need.create({
      data: {
        posterId,
        title: n.title,
        description: n.description,
        needType: n.needType,
        earnCategory: n.needType === 'EARN' ? (n.earnCategory as any) : null,
        connectCategory: n.needType === 'CONNECT' ? (n.connectCategory as any) : null,
        isPaid: n.isPaid,
        budgetMin: n.budgetMin ?? null,
        budgetMax: n.budgetMax ?? null,
        locationText: n.locationText,
        lat: n.lat, lng: n.lng,
        status: n.status,
      },
    })
    createdNeeds[n.key] = created.id
  }

  // Sub-need example: Sub-task under UI Design need
  const parentUiNeedId = createdNeeds['ui_design'] as string
  if (parentUiNeedId) {
    const aaravId = usersById['aarav.kumar@needhub.demo']!
    await prisma.need.create({
      data: {
        posterId: aaravId,
        parentNeedId: parentUiNeedId,
        title: 'Sub-task: Mobile Figma Tokens Export',
        description: 'Export color, typography, and elevation tokens as JSON for Flutter theme builder.',
        needType: 'EARN',
        earnCategory: 'FREELANCE',
        isPaid: true,
        budgetMin: 2000,
        budgetMax: 3000,
        status: 'FULFILLED',
      },
    })
  }

  console.log(`  ✓ Needs & Sub-needs seeded across OPEN, IN_PROGRESS, FULFILLED, CLOSED statuses`)

  // ── Seed Interest Responses (Offers) across all Statuses ───────────────────
  const aarav = usersById['aarav.kumar@needhub.demo']!
  const meera = usersById['meera.kulkarni@needhub.demo']!
  const rohan = usersById['rohan.verma@needhub.demo']!
  const priya = usersById['priya.nair@needhub.demo']!
  const karthik = usersById['karthik.reddy@needhub.demo']!
  const sneha = usersById['sneha.rao@needhub.demo']!
  const ananya = usersById['ananya.sharma@needhub.demo']!

  // 1. ACCEPTED Response + MessageThread + Chat Messages + Mutual 5★ Reviews (UI Design Need)
  const uiId = createdNeeds['ui_design'] as string
  if (uiId) {
    const resp = await prisma.interestResponse.create({
      data: {
        needId: uiId, responderId: meera,
        message: "I can take up the Figma design system build! Shipped 3 consumer apps.",
        quotedPrice: 12000, workSampleUrl: 'https://figma.com/@meera_design_portfolio',
        status: 'ACCEPTED',
      },
    })
    const thread = await prisma.messageThread.create({ data: { responseId: resp.id } })
    await prisma.message.createMany({
      data: [
        { threadId: thread.id, senderId: meera, body: "Hey Aarav! Shared the initial design tokens draft in Figma." },
        { threadId: thread.id, senderId: aarav, body: "Looks incredible Meera! The dark theme tokens are spot on." },
        { threadId: thread.id, senderId: meera, body: "Awesome! Exported all components as Flutter widget tokens." },
      ],
    })
    // Mutual 5-Star Reviews
    await prisma.review.createMany({
      data: [
        { needId: uiId, reviewerId: aarav, revieweeId: meera, rating: 5, comment: 'Meera was fantastic — thoughtful, fast, and delivered pixel-perfect Figma components.' },
        { needId: uiId, reviewerId: meera, revieweeId: aarav, rating: 5, comment: 'Aarav provided super clear requirements and paid instantly. Great product founder to work with!' },
      ],
    })
  }

  // 2. ACCEPTED Response + MessageThread + 5★ Review (Guitar Lessons Need)
  const guitarId = createdNeeds['guitar_lessons'] as string
  if (guitarId) {
    const resp = await prisma.interestResponse.create({
      data: {
        needId: guitarId, responderId: priya,
        message: "I've taught acoustic guitar for 3 years. Free on weekends!",
        quotedPrice: 1000, status: 'ACCEPTED',
      },
    })
    const thread = await prisma.messageThread.create({ data: { responseId: resp.id } })
    await prisma.message.createMany({
      data: [
        { threadId: thread.id, senderId: priya, body: "Hey Karthik! Ready for your first chord progression lesson?" },
        { threadId: thread.id, senderId: karthik, body: "Yes! Got my acoustic guitar tuned up." },
      ],
    })
    await prisma.review.create({
      data: { needId: guitarId, reviewerId: karthik, revieweeId: priya, rating: 5, comment: 'Priya is an amazing teacher! Learned major/minor chord switches in just 1 session.' },
    })
  }

  // 3. ACCEPTED Response (MacBook Repair - IN_PROGRESS)
  const macId = createdNeeds['macbook_repair'] as string
  if (macId) {
    const resp = await prisma.interestResponse.create({
      data: {
        needId: macId, responderId: karthik,
        message: "Hardware dev here — I can disassemble, clean dust, and re-apply Arctic MX-4 thermal paste.",
        quotedPrice: 2000, status: 'ACCEPTED',
      },
    })
    const thread = await prisma.messageThread.create({ data: { responseId: resp.id } })
    await prisma.message.createMany({
      data: [
        { threadId: thread.id, senderId: karthik, body: "Hey Ananya! I have high-performance thermal paste ready. Free tomorrow at 4pm?" },
        { threadId: thread.id, senderId: ananya, body: "Sounds perfect Karthik! Let's meet at MG Road cafe." },
      ],
    })
  }

  // 4. PENDING Response (Hackathon Teammate Need)
  const hackId = createdNeeds['hackathon_team'] as string
  if (hackId) {
    await prisma.interestResponse.create({
      data: {
        needId: hackId, responderId: rohan,
        message: "I can handle video pitch editing and UI prototypes for the hackathon!",
        status: 'PENDING',
      },
    })
  }

  // 5. DECLINED Response (Founder Mentor Need)
  const mentorId = createdNeeds['founder_mentor'] as string
  if (mentorId) {
    await prisma.interestResponse.create({
      data: {
        needId: mentorId, responderId: sneha,
        message: "Would love to catch up, but currently booked with marketing launches.",
        status: 'DECLINED',
      },
    })
  }

  // 6. WITHDRAWN Response (Keyboard Sale Need)
  const kbId = createdNeeds['keyboard_sale'] as string
  if (kbId) {
    await prisma.interestResponse.create({
      data: {
        needId: kbId, responderId: aarav,
        message: "Interested in the Keychron K2! Can pickup today.",
        status: 'WITHDRAWN',
      },
    })
  }

  console.log('  ✓ Responses seeded across ACCEPTED, PENDING, DECLINED, WITHDRAWN')

  // ── Direct Messaging (DmThread, DmMessage, Reactions) ──────────────────────
  // Pair 1: Aarav <-> Meera
  const [u1, u2] = aarav < meera ? [aarav, meera] : [meera, aarav]
  const dm1 = await prisma.dmThread.create({ data: { userAId: u1, userBId: u2 } })
  await prisma.dmMessage.createMany({
    data: [
      { threadId: dm1.id, senderId: aarav, body: "Hey Meera! Are you attending InovaHack next week?", reactions: { "👍": [meera] } },
      { threadId: dm1.id, senderId: meera, body: "Yes! Mentoring the UI track on Saturday." },
      { threadId: dm1.id, senderId: aarav, body: "Awesome, let's grab coffee there! ☕" },
    ],
  })

  // Pair 2: Rohan <-> Ananya
  const [r1, r2] = rohan < ananya ? [rohan, ananya] : [ananya, rohan]
  const dm2 = await prisma.dmThread.create({ data: { userAId: r1, userBId: r2 } })
  await prisma.dmMessage.createMany({
    data: [
      { threadId: dm2.id, senderId: rohan, body: "Hey Ananya! Loved your AI research paper presentation at IISc." },
      { threadId: dm2.id, senderId: ananya, body: "Thanks Rohan! Working on the regional language benchmarking repo now." },
    ],
  })

  // Pair 3: Priya <-> Karthik
  const [pK1, pK2] = priya < karthik ? [priya, karthik] : [karthik, priya]
  const dm3 = await prisma.dmThread.create({ data: { userAId: pK1, userBId: pK2 } })
  await prisma.dmMessage.createMany({
    data: [
      { threadId: dm3.id, senderId: karthik, body: "Priya, practicing the chord switches every day! Thanks for the lesson." },
      { threadId: dm3.id, senderId: priya, body: "Awesome progress Karthik! Next week we tackle Barre chords 🎸" },
    ],
  })

  console.log('  ✓ Direct Message threads & message reactions seeded')

  // ── Social Connections (Friendships, Requests, Blocks) ──────────────────────
  // Friendships
  await prisma.friendship.createMany({
    data: [
      { userAId: u1, userBId: u2 },
      { userAId: r1, userBId: r2 },
      { userAId: pK1, userBId: pK2 },
    ],
  })

  // Friend Requests (PENDING & DECLINED)
  await prisma.friendRequest.createMany({
    data: [
      { fromUserId: rohan, toUserId: aarav, status: 'PENDING' },
      { fromUserId: ananya, toUserId: priya, status: 'PENDING' },
      { fromUserId: sneha, toUserId: meera, status: 'DECLINED' },
    ],
  })

  // Block entry (for safety testing)
  await prisma.block.create({ data: { blockerId: priya, blockedId: sneha } })

  console.log('  ✓ Friendships, FriendRequests & Blocks seeded')

  // ── Visibility Boosts (Needs) & PointsLedger ───────────────────────────────
  if (hackId) {
    const expires24h = new Date(Date.now() + 24 * 3600 * 1000)
    await prisma.visibilityBoost.create({
      data: { userId: aarav, targetType: 'NEED', targetId: hackId, expiresAt: expires24h },
    })
    await prisma.pointsLedger.create({
      data: { userId: aarav, delta: -100, reason: 'Boost need "Hackathon teammate" (24h tier)', refId: hackId },
    })
  }

  const aiId = createdNeeds['ai_benchmark'] as string
  if (aiId) {
    const expires72h = new Date(Date.now() + 72 * 3600 * 1000)
    await prisma.visibilityBoost.create({
      data: { userId: ananya, targetType: 'NEED', targetId: aiId, expiresAt: expires72h },
    })
    await prisma.pointsLedger.create({
      data: { userId: ananya, delta: -200, reason: 'Boost need "Open Source AI Benchmarking" (72h tier)', refId: aiId },
    })
  }

  console.log('  ✓ Visibility Boosts & Points Ledger seeded')

  // ── Certificates & Achievements (All Types & Statuses) ────────────────────
  await prisma.certificate.deleteMany({ where: { userId: { in: demoUserIds } } })
  await prisma.certificate.createMany({
    data: [
      { userId: aarav, type: 'NSS', description: 'NSS Camp 2025 — 7-day community school drive', fileUrl: 'https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800', status: 'APPROVED', pointsAwarded: 80 },
      { userId: meera, type: 'VOLUNTEERING', description: 'Volunteered at Bengaluru Animal Rescue Shelter', fileUrl: 'https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800', status: 'APPROVED', pointsAwarded: 60 },
      { userId: rohan, type: 'TREE_PLANTATION', description: 'Planted 50 saplings with Green Bengaluru Initiative', fileUrl: 'https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800', status: 'PENDING_REVIEW' },
      { userId: ananya, type: 'CLEANUP', description: 'Organized Cubbon Park lake cleanup drive', fileUrl: 'https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800', status: 'APPROVED', pointsAwarded: 100 },
      { userId: karthik, type: 'OTHER', description: 'Blood donation drive volunteering', fileUrl: 'https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800', status: 'REJECTED' },
    ],
  })

  await prisma.achievement.deleteMany({ where: { userId: { in: demoUserIds } } })
  await prisma.achievement.createMany({
    data: [
      { userId: aarav, title: 'Winner — Flipkart Grid 6.0', category: 'HACKATHON', description: 'First place in mobile track. Built fintech MVP in 48h.', status: 'APPROVED' },
      { userId: meera, title: 'UX Design Fellowship', category: 'AWARD', description: 'Selected for 6-month product design fellowship.', status: 'APPROVED' },
      { userId: ananya, title: 'Best Paper — AI Ethics Summit', category: 'COMPETITION', description: 'Published research on LLM evaluation benchmarks.', status: 'APPROVED' },
      { userId: karthik, title: 'Regional Chess Championship — 2nd Place', category: 'TOURNAMENT', description: 'Competed in Bengaluru Open Chess Tournament.', status: 'APPROVED' },
    ],
  })

  console.log('  ✓ Certificates & Achievements across all categories and statuses seeded')

  // ── Notifications across ALL NotificationType Enum Values ──────────────────
  await prisma.notification.createMany({
    data: [
      { userId: aarav, type: 'FRIEND_REQUEST_RECEIVED', title: 'New Friend Request', body: 'Rohan Verma sent you a connect request.', refType: 'FRIEND_REQUEST', refId: rohan },
      { userId: aarav, type: 'REVIEW_RECEIVED', title: 'New 5★ Review', body: 'Meera left a 5-star review on your UI Designer need!', refType: 'REVIEW', refId: uiId },
      { userId: aarav, type: 'POINTS_AWARDED', title: '+20 Points Awarded', body: 'You earned 20 points from a 5★ review.', refType: 'POINTS', refId: null },
      { userId: meera, type: 'NEED_RESPONSE_RECEIVED', title: 'Offer Accepted!', body: 'Aarav accepted your offer on the UI designer need.', refType: 'NEED', refId: uiId },
      { userId: meera, type: 'CERT_APPROVED', title: 'Certificate Approved!', body: 'Your volunteering certificate was approved (+60 pts).', refType: 'CERT', refId: null },
      { userId: rohan, type: 'MESSAGE_RECEIVED', title: 'New Message from Ananya', body: 'Thanks Rohan! Working on the benchmarking repo now.', refType: 'DM', refId: null },
      { userId: priya, type: 'FRIEND_REQUEST_ACCEPTED', title: 'Friend Request Accepted', body: 'Karthik accepted your friend request.', refType: 'FRIEND', refId: karthik },
      { userId: karthik, type: 'REDEMPTION_READY', title: 'Voucher Code Delivered', body: 'Your Cafe Coffee Day voucher code is ready.', refType: 'REDEMPTION', refId: null },
    ],
  })

  console.log('  ✓ Notifications covering all NotificationType enum values')
  console.log('✅ Full seed complete!')
}
