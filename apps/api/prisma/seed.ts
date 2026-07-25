import 'dotenv/config'
import { PrismaClient } from '@prisma/client'
import { PrismaNeon } from '@prisma/adapter-neon'
import bcrypt from 'bcryptjs'

const connectionString = process.env.DATABASE_URL
if (!connectionString) throw new Error('DATABASE_URL is not set')

const prisma = new PrismaClient({
  adapter: new PrismaNeon({ connectionString }),
})

/**
 * Idempotent demo seed. Safe to run multiple times — uses upserts everywhere.
 * Populates:
 *   - SYSTEM user (for auto-moderation reports)
 *   - 6 realistic demo users with profiles + interests + skills + avatars
 *   - Interest + Skill catalog labels
 *   - 10 needs (mix of top-level and sub-needs, across EARN and CONNECT)
 *   - Friendship, pending friend request, block
 *   - Chit-chat availability on 2 users
 *   - 6 redemption items
 *   - Notifications for the primary demo user
 *
 * After seeding, `lightyagamimaitreya3@gmail.com` / `Test1234!` is the
 * primary demo account (already verified — email flow was tested).
 */

const INTERESTS = [
  'Coding', 'Design', 'Photography', 'Music', 'Sports', 'Startup',
  'Reading', 'Chess', 'Cooking', 'Gaming', 'Travel', 'Fitness',
]

const SKILLS = [
  'Flutter', 'React', 'Node.js', 'Python', 'UI/UX', 'Figma',
  'Copywriting', 'Video Editing', 'Machine Learning', 'Guitar', 'Yoga', 'Public Speaking',
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
  chitchatHours?: number
}

const DEMO_USERS: DemoUser[] = [
  {
    email: 'aarav.kumar@needhub.demo',
    username: 'aarav',
    displayName: 'Aarav Kumar',
    bio: 'CS student. Loves Flutter and building side projects on weekends.',
    gender: 'male',
    locationText: 'Koramangala, Bengaluru',
    lat: 12.9352, lng: 77.6245,
    avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200',
    interests: ['Coding', 'Startup', 'Gaming'],
    skills: ['Flutter', 'React', 'Node.js'],
    promptSkill: 'Flutter — I can spin up a mobile MVP in 48 hours',
    promptCollab: 'Someone who ships fast and cares about polish',
    promptNeed: 'A designer for my next indie app',
    chitchatHours: 6,
  },
  {
    email: 'meera.kulkarni@needhub.demo',
    username: 'meera',
    displayName: 'Meera Kulkarni',
    bio: 'Product designer & aspiring founder. Also a chess enthusiast.',
    gender: 'female',
    locationText: 'HSR Layout, Bengaluru',
    lat: 12.9081, lng: 77.6476,
    avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200',
    interests: ['Design', 'Startup', 'Chess'],
    skills: ['UI/UX', 'Figma', 'Copywriting'],
    promptSkill: 'UI/UX design — I have shipped 3 consumer products',
    promptCollab: 'Engineers who care about the craft',
    promptNeed: 'A frontend engineer who understands motion design',
    chitchatHours: 4,
  },
  {
    email: 'rohan.verma@needhub.demo',
    username: 'rohan',
    displayName: 'Rohan Verma',
    bio: 'Freelance photographer. Cafe-hopper. Currently learning ML.',
    gender: 'male',
    locationText: 'Indiranagar, Bengaluru',
    lat: 12.9784, lng: 77.6408,
    avatarUrl: 'https://images.unsplash.com/photo-1568602471122-7832951cc4c5?w=200',
    interests: ['Photography', 'Coding', 'Travel'],
    skills: ['Video Editing', 'Machine Learning'],
    promptSkill: 'Portrait and event photography',
    promptCollab: 'Content creators and small brands',
    promptNeed: 'A mentor to help me break into ML research',
  },
  {
    email: 'priya.nair@needhub.demo',
    username: 'priya',
    displayName: 'Priya Nair',
    bio: 'Fitness coach and yoga instructor. Also into DSA.',
    gender: 'female',
    locationText: 'Whitefield, Bengaluru',
    lat: 12.9698, lng: 77.7500,
    avatarUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200',
    interests: ['Fitness', 'Sports', 'Coding'],
    skills: ['Yoga', 'Public Speaking'],
    promptSkill: 'Personal training — strength and mobility',
    promptCollab: 'Study partners for DSA and system design',
    promptNeed: 'A running buddy for early mornings',
    chitchatHours: 8,
  },
  {
    email: 'karthik.reddy@needhub.demo',
    username: 'karthik',
    displayName: 'Karthik Reddy',
    bio: 'Backend dev. Guitar player on weekends.',
    gender: 'male',
    locationText: 'BTM Layout, Bengaluru',
    lat: 12.9165, lng: 77.6101,
    avatarUrl: 'https://images.unsplash.com/photo-1633332755192-727a05c4013d?w=200',
    interests: ['Coding', 'Music', 'Reading'],
    skills: ['Node.js', 'Python', 'Guitar'],
    promptSkill: 'Backend at scale — APIs, queues, databases',
    promptCollab: 'Musicians for weekend jam sessions',
    promptNeed: 'Someone to teach me singing basics',
  },
  {
    email: 'sneha.rao@needhub.demo',
    username: 'sneha',
    displayName: 'Sneha Rao',
    bio: 'Content writer, foodie, avid reader.',
    gender: 'female',
    locationText: 'Jayanagar, Bengaluru',
    lat: 12.9250, lng: 77.5938,
    avatarUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200',
    interests: ['Reading', 'Cooking', 'Travel'],
    skills: ['Copywriting', 'Public Speaking'],
    promptSkill: 'Website copy that converts',
    promptCollab: 'Book club buddies',
    promptNeed: 'A cooking swap partner — I trade for lessons',
  },
]

// Realistic needs — the AI ranker will surface these based on user interests.
const DEMO_NEEDS = [
  {
    posterEmail: 'aarav.kumar@needhub.demo',
    title: 'Need a UI designer for my Flutter app MVP',
    description: 'Building an indie note-taking app in Flutter. Have a working prototype, need a designer for 2 weeks — Figma mockups + component tokens. Portfolio required. Can pay ₹8000–15000.',
    needType: 'EARN' as const,
    earnCategory: 'FREELANCE' as const,
    isPaid: true,
    budgetMin: 8000, budgetMax: 15000,
    locationText: 'Koramangala', lat: 12.9352, lng: 77.6245,
  },
  {
    posterEmail: 'meera.kulkarni@needhub.demo',
    title: 'Study partner for GATE 2026 — CS/IT',
    description: 'Forming a small weekend study group. Focus on Data Structures, Algorithms, and Operating Systems. Meeting at the HSR public library.',
    needType: 'CONNECT' as const,
    connectCategory: 'STUDY_PARTNER' as const,
    isPaid: false,
    locationText: 'HSR Layout', lat: 12.9081, lng: 77.6476,
  },
  {
    posterEmail: 'rohan.verma@needhub.demo',
    title: 'Wedding photographer needed — Sunday brunch event',
    description: 'Small family gathering, ~30 guests, 3 hours. Looking for someone with a decent mirrorless setup. Will cover food + travel.',
    needType: 'EARN' as const,
    earnCategory: 'FREELANCE' as const,
    isPaid: true,
    budgetMin: 3000, budgetMax: 6000,
    locationText: 'Indiranagar', lat: 12.9784, lng: 77.6408,
  },
  {
    posterEmail: 'priya.nair@needhub.demo',
    title: 'Yoga classes for corporate team — 4 weeks',
    description: 'Weekly virtual yoga session for our 15-person startup team. Beginner-friendly, 45 mins each. Preference for someone certified.',
    needType: 'EARN' as const,
    earnCategory: 'TUTORING' as const,
    isPaid: true,
    budgetMin: 5000, budgetMax: 10000,
    locationText: 'Whitefield', lat: 12.9698, lng: 77.7500,
  },
  {
    posterEmail: 'karthik.reddy@needhub.demo',
    title: 'Guitar teacher — beginner acoustic',
    description: 'Looking for a patient teacher for 45-min sessions, 2x per week. I have my own guitar. Prefer someone who can meet in Koramangala or online.',
    needType: 'EARN' as const,
    earnCategory: 'TUTORING' as const,
    isPaid: true,
    budgetMin: 500, budgetMax: 1500,
    locationText: 'BTM Layout', lat: 12.9165, lng: 77.6101,
  },
  {
    posterEmail: 'sneha.rao@needhub.demo',
    title: 'Cooking swap — I teach English, you teach South Indian dishes',
    description: 'Skill-swap: I have taught English lit for 3 years. Want to learn dosa, sambar, rasam basics. Weekend sessions in Jayanagar.',
    needType: 'CONNECT' as const,
    connectCategory: 'HOBBY' as const,
    isPaid: false,
    locationText: 'Jayanagar', lat: 12.9250, lng: 77.5938,
  },
  {
    posterEmail: 'aarav.kumar@needhub.demo',
    title: 'Hackathon teammate — need a designer, weekend of Aug 3',
    description: 'InovaHack finals coming up. Team of 3 — me on Flutter, backend guy locked in, need a designer who can move fast. Prize pool ₹50k.',
    needType: 'CONNECT' as const,
    connectCategory: 'ACTIVITY_PARTNER' as const,
    isPaid: false,
    locationText: 'Koramangala', lat: 12.9352, lng: 77.6245,
  },
  {
    posterEmail: 'meera.kulkarni@needhub.demo',
    title: 'Mentor wanted — early-stage founder',
    description: 'Just quit my job to build a consumer B2B tool. Looking for a mentor who has been through the 0→1 grind. Coffee once a fortnight.',
    needType: 'CONNECT' as const,
    connectCategory: 'MENTOR' as const,
    isPaid: false,
    locationText: 'HSR Layout', lat: 12.9081, lng: 77.6476,
  },
  {
    posterEmail: 'karthik.reddy@needhub.demo',
    title: 'Selling — mechanical keyboard (Keychron K2, barely used)',
    description: 'Bought 4 months ago, used maybe twice. Full box, warranty card. Retail ₹9500, selling for ₹6500. Pickup only.',
    needType: 'EARN' as const,
    earnCategory: 'GOODS_SELL' as const,
    isPaid: true,
    budgetMin: 6500, budgetMax: 6500,
    locationText: 'BTM Layout', lat: 12.9165, lng: 77.6101,
  },
  {
    posterEmail: 'priya.nair@needhub.demo',
    title: 'Running buddy — early mornings, ~5km',
    description: 'Looking for a running partner in Whitefield area. 5:30am start, 5–8km depending on mood. Currently do ~8:30 min/km pace.',
    needType: 'CONNECT' as const,
    connectCategory: 'ACTIVITY_PARTNER' as const,
    isPaid: false,
    locationText: 'Whitefield', lat: 12.9698, lng: 77.7500,
  },
]

const TEST_USERS = [
  { email: 'a@t.co', displayName: 'a', username: 'a' },
  { email: 'b@t.co', displayName: 'b', username: 'b' },
  { email: 'c@t.co', displayName: 'c', username: 'c' },
  { email: 'd@t.co', displayName: 'd', username: 'd' },
  { email: 'e@t.co', displayName: 'e', username: 'e' },
  { email: 'f@t.co', displayName: 'f', username: 'f' },
]

const REDEMPTION_ITEMS = [
  { title: 'Amazon Voucher ₹100', description: 'Redeemable on Amazon India', pointsCost: 120, stock: 50 },
  { title: 'Cafe Coffee Day ₹150', description: 'Any small food + coffee combo', pointsCost: 180, stock: 30 },
  { title: 'Blinkit ₹200 off', description: 'Free delivery + ₹200 off any order', pointsCost: 220, stock: 40 },
  { title: 'BookMyShow ₹300', description: 'Movie ticket credit', pointsCost: 340, stock: 20 },
  { title: 'Zomato Gold — 1 month', description: 'Free delivery for a month', pointsCost: 500, stock: 15 },
  { title: 'Bluetooth Speaker (Boat)', description: 'Boat Stone 190 mini speaker, ₹1200 MRP', pointsCost: 900, stock: 5 },
]

async function main() {
  console.log('▶ Seeding NeedHub demo data…')

  // ── SYSTEM user — required by moderation auto-reports ─────────────────────
  // Keyed by email (the unique field) so re-runs never collide.
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

  // ── Interest + Skill catalog ──────────────────────────────────────────────
  for (const label of INTERESTS) {
    await prisma.interest.upsert({ where: { label }, update: {}, create: { label } })
  }
  for (const label of SKILLS) {
    await prisma.skill.upsert({ where: { label }, update: {}, create: { label } })
  }
  console.log(`  ✓ ${INTERESTS.length} interests, ${SKILLS.length} skills`)

  // ── Demo users ────────────────────────────────────────────────────────────
  const passwordHash = await bcrypt.hash('Demo1234!', 10)
  const usersById: Record<string, string> = {}

  for (const u of DEMO_USERS) {
    const user = await prisma.user.upsert({
      where: { email: u.email },
      update: { displayName: u.displayName, username: u.username, emailVerifiedAt: new Date() },
      create: {
        email: u.email,
        displayName: u.displayName,
        username: u.username,
        passwordHash,
        emailVerifiedAt: new Date(),
      },
    })
    usersById[u.email] = user.id

    const chitchatUntil = u.chitchatHours != null
      ? new Date(Date.now() + u.chitchatHours * 3600 * 1000)
      : null

    await prisma.profile.upsert({
      where: { userId: user.id },
      update: {
        bio: u.bio, gender: u.gender, locationText: u.locationText,
        lat: u.lat, lng: u.lng, avatarUrl: u.avatarUrl,
        promptSkill: u.promptSkill, promptCollab: u.promptCollab, promptNeed: u.promptNeed,
        chitchatAvailableUntil: chitchatUntil,
        pointsTotal: 340,
      },
      create: {
        userId: user.id,
        bio: u.bio, gender: u.gender, locationText: u.locationText,
        lat: u.lat, lng: u.lng, avatarUrl: u.avatarUrl,
        promptSkill: u.promptSkill, promptCollab: u.promptCollab, promptNeed: u.promptNeed,
        chitchatAvailableUntil: chitchatUntil,
        pointsTotal: 340,
      },
    })

    // Wire interests + skills.
    await prisma.profileInterest.deleteMany({ where: { profile: { userId: user.id } } })
    for (const label of u.interests) {
      const interest = await prisma.interest.findUnique({ where: { label } })
      const profile = await prisma.profile.findUnique({ where: { userId: user.id } })
      if (interest && profile) {
        await prisma.profileInterest.create({
          data: { profileId: profile.id, interestId: interest.id },
        })
      }
    }
    await prisma.profileSkill.deleteMany({ where: { profile: { userId: user.id } } })
    for (const label of u.skills) {
      const skill = await prisma.skill.findUnique({ where: { label } })
      const profile = await prisma.profile.findUnique({ where: { userId: user.id } })
      if (skill && profile) {
        await prisma.profileSkill.create({
          data: { profileId: profile.id, skillId: skill.id },
        })
      }
    }
  }
  console.log(`  ✓ ${DEMO_USERS.length} demo users with profiles`)

  // ── Test users (password: 0) ──────────────────────────────────────────────
  const testPasswordHash = await bcrypt.hash('0', 10)
  for (const t of TEST_USERS) {
    const user = await prisma.user.upsert({
      where: { email: t.email },
      update: { displayName: t.displayName, username: t.username, emailVerifiedAt: new Date() },
      create: {
        email: t.email,
        displayName: t.displayName,
        username: t.username,
        passwordHash: testPasswordHash,
        emailVerifiedAt: new Date(),
      },
    })
    await prisma.profile.upsert({
      where: { userId: user.id },
      update: {},
      create: { userId: user.id, pointsTotal: 100 },
    })
  }
  console.log(`  ✓ ${TEST_USERS.length} test users (password: 0)`)

  // ── Demo needs — clear old ones from the demo posters, then reseed ────────
  const demoPosterIds = Object.values(usersById)
  const oldNeeds = await prisma.need.findMany({ where: { posterId: { in: demoPosterIds } }, select: { id: true } })
  const oldNeedIds = oldNeeds.map(n => n.id)
  if (oldNeedIds.length > 0) {
    const oldResponses = await prisma.interestResponse.findMany({ where: { needId: { in: oldNeedIds } }, select: { id: true } })
    const oldResponseIds = oldResponses.map(r => r.id)
    if (oldResponseIds.length > 0) {
      const oldThreads = await prisma.messageThread.findMany({ where: { responseId: { in: oldResponseIds } }, select: { id: true } })
      const oldThreadIds = oldThreads.map(t => t.id)
      if (oldThreadIds.length > 0) {
        await prisma.message.deleteMany({ where: { threadId: { in: oldThreadIds } } })
        await prisma.messageThread.deleteMany({ where: { id: { in: oldThreadIds } } })
      }
      await prisma.interestResponse.deleteMany({ where: { id: { in: oldResponseIds } } })
    }
    await prisma.need.deleteMany({ where: { id: { in: oldNeedIds } } })
  }

  for (const n of DEMO_NEEDS) {
    const posterId = usersById[n.posterEmail]
    if (!posterId) continue
    await prisma.need.create({
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
        status: 'OPEN',
      },
    })
  }
  console.log(`  ✓ ${DEMO_NEEDS.length} demo needs`)

  // ── One friendship + one pending request + one block ──────────────────────
  const aarav = usersById['aarav.kumar@needhub.demo']
  const meera = usersById['meera.kulkarni@needhub.demo']
  const rohan = usersById['rohan.verma@needhub.demo']
  const priya = usersById['priya.nair@needhub.demo']

  if (aarav && meera) {
    const [a, b] = aarav < meera ? [aarav, meera] : [meera, aarav]
    await prisma.friendship.upsert({
      where: { userAId_userBId: { userAId: a, userBId: b } },
      update: {},
      create: { userAId: a, userBId: b },
    })
  }

  // Pending request Rohan → Aarav (so Aarav has one in inbox).
  if (rohan && aarav) {
    await prisma.friendRequest.upsert({
      where: { fromUserId_toUserId: { fromUserId: rohan, toUserId: aarav } },
      update: { status: 'PENDING' },
      create: { fromUserId: rohan, toUserId: aarav, status: 'PENDING' },
    })
  }

  // Block: Priya blocks a non-connected user (Sneha) — so admin can see one.
  const sneha = usersById['sneha.rao@needhub.demo']
  if (priya && sneha) {
    const existing = await prisma.block.findFirst({
      where: { blockerId: priya, blockedId: sneha },
    })
    if (!existing) {
      await prisma.block.create({
        data: { blockerId: priya, blockedId: sneha },
      })
    }
  }
  console.log('  ✓ friendship, pending request, block')

  // ── Redemption catalog ────────────────────────────────────────────────────
  for (const it of REDEMPTION_ITEMS) {
    const existing = await prisma.redemptionItem.findFirst({
      where: { title: it.title },
    })
    if (!existing) {
      await prisma.redemptionItem.create({
        data: {
          title: it.title, description: it.description,
          pointsCost: it.pointsCost, stock: it.stock, active: true,
        },
      })
    }
  }
  console.log(`  ✓ ${REDEMPTION_ITEMS.length} redemption items`)

  // ── Pending certificates for admin review ────────────────────────────────
  const certDefs = [
    { email: 'aarav.kumar@needhub.demo', type: 'NSS' as const, description: 'NSS camp 2025 — 7-day community service at govt school in Tumkur' },
    { email: 'meera.kulkarni@needhub.demo', type: 'VOLUNTEERING' as const, description: 'Volunteered at Bangalore animal shelter for 3 months' },
    { email: 'rohan.verma@needhub.demo', type: 'TREE_PLANTATION' as const, description: 'Planted 50 saplings with Green Bengaluru drive — July 2025' },
  ]
  for (const cd of certDefs) {
    const uid = usersById[cd.email]
    if (!uid) continue
    const existing = await prisma.certificate.findFirst({ where: { userId: uid, type: cd.type } })
    if (!existing) {
      await prisma.certificate.create({
        data: {
          userId: uid,
          type: cd.type,
          description: cd.description,
          fileUrl: `https://images.unsplash.com/photo-1568702846914-96b305d2aaeb?w=800`,
          status: 'PENDING_REVIEW',
        },
      })
    }
  }
  console.log('  ✓ 3 pending certificates')

  // ── Sample notifications for the primary demo account ─────────────────────
  const primaryEmail = 'lightyagamimaitreya3@gmail.com'
  const primary = await prisma.user.findUnique({ where: { email: primaryEmail } })
  if (primary) {
    await prisma.notification.deleteMany({ where: { userId: primary.id } })
    await prisma.notification.createMany({
      data: [
        {
          userId: primary.id, type: 'FRIEND_REQUEST_RECEIVED',
          title: 'New friend request', body: 'Aarav Kumar wants to connect',
          refType: 'FRIEND_REQUEST', refId: null,
        },
        {
          userId: primary.id, type: 'MESSAGE_RECEIVED',
          title: 'New message from Meera', body: 'Hey! I saw your post about the hackathon…',
          refType: 'DM_THREAD', refId: null,
        },
        {
          userId: primary.id, type: 'POINTS_AWARDED',
          title: '+20 points', body: 'You earned 20 points from a 5★ review.',
          refType: 'REVIEW', refId: null,
        },
      ],
    })
    console.log(`  ✓ 3 notifications for ${primaryEmail}`)
  }

  console.log('✅ Seed complete.')
}

main()
  .catch((err) => { console.error(err); process.exit(1) })
  .finally(() => prisma.$disconnect())
