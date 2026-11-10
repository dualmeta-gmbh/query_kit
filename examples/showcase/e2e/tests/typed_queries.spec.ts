import { button, expect, fact, factIn, test, type Page, type Scenario } from './fixtures'

// Two toolbars, five readers, four strips and a card of notes: a 720-tall
// window holds a third of it, and only what is on screen is in Flutter's
// semantics tree.
test.use({ viewport: { width: 1280, height: 2400 } })

const firstTitle = 'Local development: setup guide'
const secondTitle = 'Continuous integration: setup guide'
const writtenTitle = 'Written through the reference'

const reader = (page: Page, name: string, text: string) => factIn(page, `reader ${name}`, text)

/// Opens the screen and waits until every entry has its first answer.
async function openLoaded(page: Page, open: (route: string) => Promise<void>) {
  await open('/typed-queries')
  await expect(reader(page, 'post 1', `title=${firstTitle}`)).toBeVisible()
  await expect(reader(page, 'raw post 1', `title=${firstTitle}`)).toBeVisible()
  await expect(reader(page, 'post 2', `title=${secondTitle}`)).toBeVisible()
  await expect(reader(page, 'posts', 'count=30')).toBeVisible()
  await expect(reader(page, 'time', 'serial=1')).toBeVisible()
}

/// Every strip's fetch count at once, and nothing in flight on any of them.
async function expectFetches(page: Page, post1: number, post2: number, posts: number, time: number) {
  for (const [label, count] of [
    ['post 1', post1],
    ['post 2', post2],
    ['posts', posts],
    ['time', time],
  ] as const) {
    await expect(fact(page, label, `fetches=${count}`), label).toBeVisible()
    await expect(fact(page, label, 'fetchStatus=idle'), label).toBeVisible()
  }
}

/// The backend's own count of each read, in this test's scenario.
async function expectRequests(scenario: Scenario, post1: number, post2: number, posts: number, time: number) {
  expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(post1)
  expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(post2)
  expect(await scenario.count('GET', /^\/api\/posts$/)).toBe(posts)
  expect(await scenario.count('GET', /^\/api\/time$/)).toBe(time)
}

test("each entry is fetched once, and the raw reader of post 1 shares the typed reader's entry", async ({
  page,
  open,
  scenario,
}) => {
  await openLoaded(page, open)

  await expect(reader(page, 'posts', `first=${firstTitle}`)).toBeVisible()
  await expectFetches(page, 1, 1, 1, 1)
  // Two observers, one entry, one request.
  await expect(fact(page, 'post 1', 'observers=2')).toBeVisible()
  await expect(fact(page, 'post 2', 'observers=1')).toBeVisible()
  await expect(factIn(page, 'typed facts', 'readAll=2')).toBeVisible()
  await expect(factIn(page, 'typed facts', 'equalRefs=true')).toBeVisible()
  await expectRequests(scenario, 1, 1, 1, 1)
})

test('Write post 1 puts the value into the entry with no request, and the raw reader shows it too', async ({
  page,
  open,
  scenario,
}) => {
  await openLoaded(page, open)
  await expect(fact(page, 'post 1', 'updates=1')).toBeVisible()

  await button(page, 'Write post 1').click()

  await expect(reader(page, 'post 1', `title=${writtenTitle}`)).toBeVisible()
  await expect(reader(page, 'raw post 1', `title=${writtenTitle}`)).toBeVisible()
  await expect(reader(page, 'post 2', `title=${secondTitle}`)).toBeVisible()
  await expect(fact(page, 'post 1', 'updates=2')).toBeVisible()
  await expectFetches(page, 1, 1, 1, 1)
  await expectRequests(scenario, 1, 1, 1, 1)
})

test('Update post 2 derives the new title from the cached one', async ({ page, open, scenario }) => {
  await openLoaded(page, open)

  await button(page, 'Update post 2').click()

  await expect(reader(page, 'post 2', `title=${secondTitle} (updated)`)).toBeVisible()
  await expect(reader(page, 'post 1', `title=${firstTitle}`)).toBeVisible()
  await expect(fact(page, 'post 2', 'updates=2')).toBeVisible()
  await expect(fact(page, 'post 1', 'updates=1')).toBeVisible()
  await expectFetches(page, 1, 1, 1, 1)
  await expectRequests(scenario, 1, 1, 1, 1)
})

test('Patch every detail runs over both cached details and not the list', async ({ page, open, scenario }) => {
  await openLoaded(page, open)

  await button(page, 'Patch every detail').click()

  await expect(reader(page, 'post 1', `title=${firstTitle} (patched)`)).toBeVisible()
  await expect(reader(page, 'raw post 1', `title=${firstTitle} (patched)`)).toBeVisible()
  await expect(reader(page, 'post 2', `title=${secondTitle} (patched)`)).toBeVisible()
  await expect(fact(page, 'post 1', 'updates=2')).toBeVisible()
  await expect(fact(page, 'post 2', 'updates=2')).toBeVisible()
  // The list is a sibling of the family, not a member of it.
  await expect(reader(page, 'posts', `first=${firstTitle}`)).toBeVisible()
  await expect(fact(page, 'posts', 'updates=1')).toBeVisible()
  await expectFetches(page, 1, 1, 1, 1)
  await expectRequests(scenario, 1, 1, 1, 1)
})

test('Invalidate post 1 refetches exactly that entry', async ({ page, open, scenario }) => {
  await openLoaded(page, open)

  await button(page, 'Invalidate post 1').click()

  await expectFetches(page, 2, 1, 1, 1)
  // One refetch for the entry, whichever of its two observers asked.
  await expectRequests(scenario, 2, 1, 1, 1)
  await expect(fact(page, 'post 1', 'isStale=false')).toBeVisible()
})

test('Invalidate details refetches every detail and not the list', async ({ page, open, scenario }) => {
  await openLoaded(page, open)

  await button(page, 'Invalidate details').click()

  await expectFetches(page, 2, 2, 1, 1)
  await expectRequests(scenario, 2, 2, 1, 1)
})

test('Invalidate posts refetches everything under the namespace and not the time beside it', async ({
  page,
  open,
  scenario,
}) => {
  await openLoaded(page, open)

  await button(page, 'Invalidate posts').click()

  await expectFetches(page, 2, 2, 2, 1)
  await expectRequests(scenario, 2, 2, 2, 1)
  await expect(reader(page, 'time', 'serial=1')).toBeVisible()
})

test('a write is replaced by the refetch an invalidation asks for, in both readers', async ({
  page,
  open,
  scenario,
}) => {
  await openLoaded(page, open)
  await button(page, 'Write post 1').click()
  await expect(reader(page, 'raw post 1', `title=${writtenTitle}`)).toBeVisible()

  await button(page, 'Invalidate post 1').click()

  await expect(reader(page, 'post 1', `title=${firstTitle}`)).toBeVisible()
  await expect(reader(page, 'raw post 1', `title=${firstTitle}`)).toBeVisible()
  await expectFetches(page, 2, 1, 1, 1)
  await expectRequests(scenario, 2, 1, 1, 1)
})
