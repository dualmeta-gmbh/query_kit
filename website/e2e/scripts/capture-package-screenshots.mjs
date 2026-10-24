import { chromium, expect } from '@playwright/test'
import { mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

// Real showcase screens, backed by the demo's in-memory API. Build and serve
// the site first (website/e2e/serve.mjs); no API server or production data.
const base = process.env.SITE_URL ?? 'http://localhost:3100'
const destination = new URL('../../../packages/query_kit_flutter/screenshots/', import.meta.url)
const browser = await chromium.launch()
try {
  await mkdir(destination, { recursive: true })
  const page = await browser.newPage({
    viewport: { width: 1000, height: 1008 },
    deviceScaleFactor: 1,
    colorScheme: 'dark',
  })
  const open = async (feature) => {
    await page.goto(`${base}/demo/showcase/?embed=1&semantics=1&theme=dark#/${feature}`)
    await expect(page.getByText('in-memory backend', { exact: true })).toBeVisible()
  }
  const save = async (name) => {
    await page.screenshot({ path: fileURLToPath(new URL(name, destination)) })
    console.log(`Captured ${name}`)
  }

  await open('cache-inspector')
  await page.getByRole('switch', { name: 'Keep readers', exact: true }).click()
  const posts = page.getByRole('group', { name: 'entry ["posts"]', exact: true })
  await expect(posts.getByText('status=success', { exact: true })).toBeVisible()
  await expect(posts.getByText('isStale=false', { exact: true })).toBeVisible()
  await save('cache-inspector.png')

  await page.setViewportSize({ width: 1000, height: 750 })
  await open('optimistic-updates')
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()
  // Exercise a real write before capturing the resulting list.
  const input = page.getByRole('textbox')
  await input.click()
  await input.fill('Try optimistic updates')
  await page.getByRole('button', { name: 'Add', exact: true }).click()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  await expect(page.getByText('Try optimistic updates', { exact: true })).toBeVisible()
  await input.blur()
  await save('optimistic-updates.png')
} finally {
  await browser.close()
}
