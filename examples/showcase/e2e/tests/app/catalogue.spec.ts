// The catalogue screen itself: the list a human opens the app on.
//
// Every other spec deep-links into one feature, so the rows, their texts and
// the navigation between the list and a screen were exercised by nothing in a
// browser (#79). This file is not about one feature, so it lives beside no
// `<id>.spec.ts`: `test/catalogue_test.dart` reads `e2e/tests` without
// descending into `app/`, and Playwright's `testDir` does.
//
// The expected rows come from the site's copy of the catalogue, which
// `test/demo_mode_test.dart` holds equal to `lib/routes.dart` — ids, titles,
// summaries and order — so a feature added to the app is expected here
// without anybody editing this file.
import { readFileSync } from 'node:fs'
import type { Page } from '@playwright/test'
import { expect, test } from '../fixtures'
import { button } from './../fixtures'

type Feature = { id: string; title: string; summary: string }

const features: Feature[] = JSON.parse(
  readFileSync(new URL('../../../../../website/src/components/LiveDemo/showcase-features.json', import.meta.url), 'utf8'),
)

/// A row is one button, named by its title and its summary.
const nameOf = (feature: Feature) => `${feature.title} ${feature.summary}`
const row = (page: Page, feature: Feature) => button(page, nameOf(feature))
const rows = (page: Page) => page.getByRole('button')
const catalogueTitle = (page: Page) => page.getByRole('heading', { name: 'query_kit showcase', exact: true })
const heading = (page: Page, title: string) => page.getByRole('heading', { name: title, exact: true })
const back = (page: Page) => button(page, 'Back')

/// Every request the page sends to the backend, from now on.
function backendRequests(page: Page) {
  const urls: string[] = []
  page.on('request', (request) => {
    if (request.url().includes(':5175/')) urls.push(`${request.method()} ${request.url()}`)
  })
  return urls
}

// A lazy `ListView` builds only what is in view: a window that holds every row.
test.use({ viewport: { width: 1280, height: 2600 } })

test('lists every feature once, in the catalogue order', async ({ page, open }) => {
  await open('/')

  await expect(catalogueTitle(page)).toBeVisible()
  await expect(rows(page)).toHaveCount(features.length)
  for (const [index, feature] of features.entries()) {
    await expect(rows(page).nth(index), `row ${index + 1} is ${feature.id}`).toHaveAccessibleName(nameOf(feature))
  }
})

test('every row in the catalogue opens a screen titled after it', async ({ page, open }) => {
  // Every screen mounted, read once and left: the one proof that all of the
  // routes work in a browser. Slow on purpose.
  test.setTimeout(240_000)
  await open('/')

  for (const feature of features) {
    await row(page, feature).click()

    await expect(heading(page, feature.title), `${feature.id} opens`).toBeVisible()
    await expect(page).toHaveURL(new RegExp(`#/${feature.id}$`))
    await expect(catalogueTitle(page), `${feature.id} is not the catalogue`).toBeHidden()

    await back(page).click()
    await expect(catalogueTitle(page), `${feature.id} returns`).toBeVisible()
    await expect(rows(page)).toHaveCount(features.length)
  }
})

test('coming back from a feature sends no request of its own', async ({ page, open, scenario }) => {
  const simple = features.find((feature) => feature.id === 'simple')!
  await open('/')

  await row(page, simple).click()
  await expect(heading(page, simple.title)).toBeVisible()
  await expect(page.getByText('Local development: setup guide')).toBeVisible()
  const log = await scenario.requests()
  expect(log.filter((entry) => /^\/api\/posts\/1$/.test(entry.path))).toHaveLength(1)

  await back(page).click()
  await expect(catalogueTitle(page)).toBeVisible()
  await expect(rows(page)).toHaveCount(features.length)

  // The screen is gone and the list asks for nothing on its way back. (Opening
  // the feature again would fetch again: its post is stale at once.)
  expect(await scenario.requests()).toEqual(log)
})

test('the catalogue itself reaches the backend for nothing', async ({ page, open, scenario }) => {
  const requests = backendRequests(page)
  await open('/')
  await expect(rows(page)).toHaveCount(features.length)

  // `HomeScreen` holds no query; this is what keeps it that way.
  expect(requests).toEqual([])
  expect(await scenario.requests()).toEqual([])
})

test('a row is reachable by keyboard, and Enter opens the row that has focus', async ({ page, open }) => {
  const third = features[2]
  await open('/')
  await expect(rows(page)).toHaveCount(features.length)

  // Tab walks the rows in order; the third is the one that is left focused.
  await expect(async () => {
    await page.keyboard.press('Tab')
    await expect(row(page, third)).toBeFocused({ timeout: 250 })
  }).toPass({ timeout: 10_000, intervals: [50] })
  await page.keyboard.press('Enter')

  await expect(heading(page, third.title)).toBeVisible()
  await expect(page).toHaveURL(new RegExp(`#/${third.id}$`))
})

// A window shorter than the list, so a scroll position exists to be kept.
test.describe('in a window shorter than the list', () => {
  test.use({ viewport: { width: 1280, height: 600 } })

  test('coming back from a feature leaves the list scrolled where it was', async ({ page, open }) => {
    const first = features[0]
    const last = features[features.length - 1]
    await open('/')
    await expect(row(page, first)).toBeInViewport()
    await expect(row(page, last)).toHaveCount(0)

    // The wheel goes to Flutter's own scrolling; the last row exists once the
    // list has been turned far enough, and is on screen when it stops.
    await page.mouse.move(640, 300)
    await expect(async () => {
      await page.mouse.wheel(0, 400)
      await expect(row(page, last)).toBeInViewport({ ratio: 1, timeout: 250 })
    }).toPass({ timeout: 20_000, intervals: [100] })
    await expect(row(page, first)).toHaveCount(0)

    await row(page, last).click()
    await expect(heading(page, last.title)).toBeVisible()
    await back(page).click()

    await expect(catalogueTitle(page)).toBeVisible()
    await expect(row(page, last)).toBeInViewport({ ratio: 1 })
    await expect(row(page, first)).toHaveCount(0)
  })
})
