import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    testTimeout: 20000,  // Neon cold-start can take a few seconds
    hookTimeout: 20000,
  },
})
