import { createServer } from 'http'
import { app } from './app'
import { config } from './config'
import { initSocket } from './lib/socket'

const httpServer = createServer(app)
initSocket(httpServer)

httpServer.listen(config.port, '0.0.0.0', () => {
  console.log(`API listening on port ${config.port}`)
})
