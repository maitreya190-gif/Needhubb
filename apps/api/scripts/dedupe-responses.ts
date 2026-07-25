import { prisma } from '../src/lib/prisma'

async function main() {
  const dupes = await prisma.$queryRawUnsafe<Array<{ needId: string; responderId: string; c: number }>>(
    `SELECT "needId", "responderId", COUNT(*)::int as c FROM "InterestResponse" GROUP BY "needId", "responderId" HAVING COUNT(*) > 1`
  )
  console.log('duplicate groups:', dupes.length)
  for (const d of dupes) {
    const rows = await prisma.interestResponse.findMany({
      where: { needId: d.needId, responderId: d.responderId },
      orderBy: { createdAt: 'desc' },
    })
    const dropIds = rows.slice(1).map((r) => r.id)
    await prisma.interestResponse.deleteMany({ where: { id: { in: dropIds } } })
    console.log(`cleaned need=${d.needId} responder=${d.responderId} kept=1 dropped=${dropIds.length}`)
  }
  await prisma.$disconnect()
}

main().catch((e) => { console.error(e); process.exit(1) })
