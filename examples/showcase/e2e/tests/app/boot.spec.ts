// How the app starts when nobody has told it a scenario: what a human in a
// browser gets, and what a typed or stale URL does.
//
// **Read-only against the `default` world, and serial.** These tests carry no
// `?scenario=`, so they live in the backend's one shared `default` world. They
// never reset or configure it — a `reset` or a `config` there reaches outside
// the test, and with a reused server (`reuseExistingServer`) it would stomp a
// developer's own session — and they count requests in the browser
// (`page.on('request')`) rather than in the scenario's log, which `default`
// shares with whoever else is using it. Serial, because what they have in
// common is that world. Green twice in a row is what shows one left it as it
// found it.
import type { Page } from '@playwright/test'
import { expect, fact, test } from '../fixtures'

test.describe.configure({ mode: 'serial' })

const catalogueTitle = (page: Page) => page.getByRole('heading', { name: 'query_kit showcase', exact: true })
const heading = (page: Page, title: string) => page.getByRole('heading', { name: title, exact: true })
const back = (page: Page) => page.getByRole('button', { name: 'Back', exact: true })

/// Every request the page sends to the backend, from now on.
function backendRequests(page: Page) {
  const urls: string[] = []
  page.on('request', (request) => {
    if (request.url().includes(':5175/')) urls.push(`${request.method()} ${new URL(request.url()).pathname}`)
  })
  return urls
}

test('opened with no scenario in the query string, the app runs in the default world', async ({ page }) => {
  await page.goto('/')

  await expect(catalogueTitle(page)).toBeVisible()
  await expect(page.getByText('scenario default', { exact: true })).toBeVisible()
})

test('an unknown route in the hash falls back to the catalogue and keeps the name it was asked for', async ({
  page,
}) => {
  await page.goto('/#/no-such-feature')

  await expect(catalogueTitle(page)).toBeVisible()
  await expect(page.getByRole('button', { name: /^Simple / })).toBeVisible()
  // A typo is not rewritten into a route the app does have.
  await expect(page).toHaveURL(/#\/no-such-feature$/)
  await expect(page.getByText('scenario default', { exact: true })).toBeVisible()
})

test('a feature route in the hash opens that feature directly, with no row pressed', async ({ page }) => {
  await page.goto('/#/simple')

  await expect(heading(page, 'Simple')).toBeVisible()
  await expect(catalogueTitle(page)).toBeHidden()
  await expect(page.getByText('scenario default', { exact: true })).toBeVisible()
  // Flutter expands an initial route into the catalogue beneath the feature,
  // so the way out of a deep link is the catalogue.
  await back(page).click()
  await expect(catalogueTitle(page)).toBeVisible()
})

test('a reload on a feature route comes back to the same feature', async ({ page }) => {
  await page.goto('/#/pagination')
  await expect(heading(page, 'Pagination')).toBeVisible()

  await page.reload()

  await expect(heading(page, 'Pagination')).toBeVisible()
  await expect(catalogueTitle(page)).toBeHidden()
  await expect(page).toHaveURL(/#\/pagination$/)
})

test('a feature opened in the default world fetches from the backend and renders', async ({ page }) => {
  const requests = backendRequests(page)
  await page.goto('/#/simple')

  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  await expect(fact(page, 'post', 'status=success')).toBeVisible()
  await expect(fact(page, 'post', 'scenario=default')).toBeVisible()
  // The app asked its own world for the post: one read, and nothing else.
  expect(requests.filter((request) => request.startsWith('GET ') && request.endsWith('/api/posts/1'))).toHaveLength(1)
  expect(requests.filter((request) => !request.startsWith('OPTIONS '))).toEqual(['GET /api/posts/1'])
})
