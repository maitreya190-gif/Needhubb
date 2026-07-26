import 'dotenv/config'
import { runSeed } from '../src/lib/demo-seed'

runSeed()
  .catch((err) => { console.error(err); process.exit(1) })
  .finally(() => process.exit(0))
