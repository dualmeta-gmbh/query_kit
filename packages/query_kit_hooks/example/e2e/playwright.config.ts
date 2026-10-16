import { defineConfig, devices } from '@playwright/test'

// The app under test is `flutter build web --dart-define=E2E=true
// --dart-define=BACKEND=http://localhost:5178/api` (npm run build), served as
// static files; the backend is the showcase's express server, on a port of
// this suite's own so it can run beside the showcase's. Both are started
// here.
//
// Every test lives in a scenario of its own on the backend (see
// tests/fixtures.ts), so the suite runs in parallel.
const appPort = process.env.APP_PORT ?? '8125'

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // A CanvasKit tab costs a core at boot; the CI runner has four.
  workers: process.env.CI ? 2 : 4,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${appPort}`,
    trace: 'retain-on-failure',
  },
  // Chromium on every push; Firefox and WebKit with E2E_BROWSERS=all, as
  // the showcase's suite does.
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    ...(process.env.E2E_BROWSERS === 'all'
      ? [
          { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
          { name: 'webkit', use: { ...devices['Desktop Safari'] } },
        ]
      : []),
  ],
  webServer: [
    {
      command: 'node server.ts',
      cwd: '../../../../examples/showcase/server',
      env: { PORT: '5178' },
      url: 'http://localhost:5178/api/__scenario/probe/requests',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'node serve.mjs ../build/web',
      env: { PORT: appPort },
      url: `http://localhost:${appPort}`,
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
})
