// The site's own search, the navbar box `@easyops-cn/docusaurus-search-local`
// adds (#74): a lunr index built into `build/` and loaded in the browser, no
// service behind it. (search.spec.ts is about search *engines*.) These specs
// type into the box the way a reader does and follow what it offers.
import type { Page } from '@playwright/test'
import { BASE, expect, test } from './fixtures'

const searchBox = (page: Page) => page.getByLabel('Search', { exact: true })

// `QueriesController` is documented in the widgets and controllers reference
// (as a heading) and used in a guide and an example; a reader who types the
// name gets all of them.
test('typing a class name lists the page that documents it, and Enter opens it', async ({ page }) => {
  await page.goto(`${BASE}docs/overview`)
  await searchBox(page).click()
  await searchBox(page).pressSequentially('QueriesController')

  const results = page.getByRole('listbox').getByRole('option')
  await expect(results.first()).toContainText('QueriesController')
  await expect(results.first()).toContainText('Widgets and controllers')
  // Also the pages that merely use it.
  await expect(results.filter({ hasText: 'Parallel queries' }).first()).toBeVisible()

  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(`${BASE}docs/reference/widgets-and-controllers#queriescontroller`)
  await expect(page.getByRole('heading', { level: 3, name: 'QueriesController' })).toBeVisible()
  // The plugin's highlight option is off: it would add a query string.
  expect(new URL(page.url()).search).toBe('')
})

test('a result can be clicked', async ({ page }) => {
  await page.goto(`${BASE}docs/overview`)
  await searchBox(page).click()
  await searchBox(page).pressSequentially('QueriesController')
  await page.getByRole('listbox').getByRole('option').filter({ hasText: 'Parallel queries' }).first().click()
  await expect(page).toHaveURL(new RegExp(`${BASE}docs/guides/parallel-queries`))
})

test('a term that is nowhere on the site shows the no-results state', async ({ page }) => {
  await page.goto(`${BASE}docs/overview`)
  await searchBox(page).click()
  await searchBox(page).pressSequentially('zzzqqxxnonsense')
  await expect(page.getByRole('listbox').getByText('No results')).toBeVisible()
  await expect(page.getByRole('listbox').getByRole('option')).toHaveCount(0)
})

test('the index is a static file with a hashed name, loaded when the box is used', async ({ page, request }) => {
  const loaded = page.waitForResponse((response) => /\/search-index-[0-9a-f]+\.json$/.test(response.url()))
  await page.goto(`${BASE}docs/overview`)
  await searchBox(page).click()
  const response = await loaded
  expect(response.status()).toBe(200)

  const index: { documents: { u: string }[] }[] = await (await request.get(response.url())).json()
  const pages = index.flatMap((part) => part.documents).map((doc) => doc.u)
  // The guides are in it; the vendored dartdoc and the search page are not.
  expect(pages).toContain('/docs/reference/widgets-and-controllers')
  expect(pages.every((path) => path.startsWith('/docs/'))).toBe(true)
})

// The results page is `/search`. The plugin marks it `noindex` with a
// `property` attribute that crawlers do not read, so the site says it with
// `name` (src/theme/SearchPage), and keeps the page out of the sitemap.
test('the search results page is neither indexable nor in the sitemap', async ({ page, request }) => {
  await page.goto(`${BASE}search?q=QueriesController`)
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', 'noindex, follow')

  const sitemap = await (await request.get(`${BASE}sitemap.xml`)).text()
  expect(sitemap).toContain('/docs/overview')
  expect(sitemap).not.toMatch(/<loc>[^<]*\/search<\/loc>/)
})
