import { defineConfig, devices } from '@playwright/test'

// The app under test is `flutter build web --dart-define=E2E=true` (npm run
// build), served as static files; the backend is the real express server in
// `../server`. Both are started here.
export default defineConfig({
  testDir: './tests',
  // The backend keeps one in-memory state per run and scripts "every second
  // delete fails", so tests run one at a time, in file order.
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: 'http://localhost:8123',
    trace: 'retain-on-failure',
    // The build registers Flutter's service worker, and in WebKit a request
    // from a page it controls goes past `page.route`: the tests that refuse
    // the backend's connections would see it answer. The app's own requests
    // are what the suite is about, so the worker stays out in every browser.
    serviceWorkers: 'block',
  },
  // Chromium on every push; Firefox and WebKit (Safari's engine) with
  // E2E_BROWSERS=all, which the release-time run sets — three browsers triple
  // the minutes, and the engine differences they catch move slowly.
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
      cwd: '../server',
      url: 'http://localhost:5174/api/tasks',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'node serve.mjs ../build/web',
      url: 'http://localhost:8123',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
})
