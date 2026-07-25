import { app } from './app'
import { config } from './config'

// Listen on 0.0.0.0 so Android emulator (10.0.2.2) can reach it
app.listen(config.port, '0.0.0.0', () => {
  console.log(`API listening on port ${config.port}`)
})
