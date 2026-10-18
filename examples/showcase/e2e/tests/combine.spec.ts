import { button, expect, expectSelected, fact, factIn, factNumber, group, holdRequest, segment, test, type Page } from './fixtures'

// The controls, three strips and the combined card: taller than the default
// viewport, and the scaffold's list builds only what is in view.
test.use({ viewport: { width: 1280, height: 1400 } })

const POST = /^\/api\/posts\/1$/
const COMMENTS = /^\/api\/posts\/1\/comments$/
const COUNTER = /^\/api\/counter$/

const TITLE = 'Local development: setup guide'

/// What the three amount to together, and what the combiner made of them.
const combined = (page: Page, text: string) => factIn(page, 'combined', text)

const overview = (page: Page, text: string) => factIn(page, 'overview', text)


/// A click, then the state: Flutter updates its semantics a frame later.
async function setPostRead(page: Page, label: 'answers' | 'is refused') {
  const choice = segment(group(page, 'post knob'), label)
  await choice.click()
  await expectSelected(choice)
}

test('pending until every source has data, then the combination', async ({ page, open }) => {
  // Held before the screen opens: two sources land, the third provably has not.
  const hold = holdRequest(page, '**/api/counter*')
  await open('/combine')

  await expect(fact(page, 'post', 'status=success')).toBeVisible()
  await expect(fact(page, 'comments', 'status=success')).toBeVisible()
  await expect(fact(page, 'counter', 'fetchStatus=fetching')).toBeVisible()
  await expect(combined(page, 'state=pending')).toBeVisible()
  await expect(combined(page, 'isFetching=true')).toBeVisible()
  // The combiner has nothing to run on yet.
  await expect(combined(page, 'combines=0')).toBeVisible()
  await expect(group(page, 'overview')).toBeHidden()
  expect(hold.seen).toBe(1)
  await hold.release()

  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await expect(combined(page, 'combines=1')).toBeVisible()
  await expect(page.getByText(TITLE, { exact: true })).toBeVisible()
  await expect(overview(page, 'comments=3')).toBeVisible()
  await expect(overview(page, 'counter=0')).toBeVisible()
  await expect(overview(page, 'refetchError=none')).toBeVisible()
})

test('a source with nothing to show is the error even while another loads, and retry refetches only it', async ({
  page,
  open,
  scenario,
}) => {
  // Exact path: the comments live under it and are not refused.
  await scenario.config({ failNext: [{ method: 'GET', path: '/api/posts/1', count: 1, status: 500 }] })
  const hold = holdRequest(page, '**/api/counter*')
  await open('/combine')

  // The counter is still out, and waiting for it would not cure the post:
  // the error wins over the pending.
  await expect(fact(page, 'post', 'status=error')).toBeVisible()
  await expect(fact(page, 'counter', 'fetchStatus=fetching')).toBeVisible()
  await expect(combined(page, 'state=error')).toBeVisible()
  await expect(combined(page, 'isFetching=true')).toBeVisible()
  await expect(page.getByText('Scripted failure 500', { exact: true })).toBeVisible()
  await hold.release()

  await expect(fact(page, 'counter', 'status=success')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await expect(combined(page, 'state=error')).toBeVisible()
  await expect(combined(page, 'combines=0')).toBeVisible()
  // `RetryPolicy.never`: refused once, asked once.
  expect(await scenario.count('GET', POST)).toBe(1)

  await button(page, 'Retry').click()

  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(combined(page, 'combines=1')).toBeVisible()
  await expect(page.getByText(TITLE, { exact: true })).toBeVisible()
  await expect(page.getByText('Scripted failure 500', { exact: true })).toBeHidden()
  // `retry()` went to the failed source and left the other two alone.
  expect(await scenario.count('GET', POST)).toBe(2)
  expect(await scenario.count('GET', COMMENTS)).toBe(1)
  expect(await scenario.count('GET', COUNTER)).toBe(1)
})

test('a failed background refetch keeps the data and shows up as refetchError', async ({ page, open, scenario }) => {
  await open('/combine')
  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await scenario.clearRequests()

  await setPostRead(page, 'is refused')
  const hold = holdRequest(page, '**/api/posts/1/comments*')
  await button(page, 'Refetch all').click()

  // `isFetching` is "any source is" — here the comments, held — and the
  // content stays where it is.
  await expect(combined(page, 'isFetching=true')).toBeVisible()
  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(page.getByText(TITLE, { exact: true })).toBeVisible()
  await expect(button(page, 'Refetch all')).toHaveAttribute('aria-disabled', 'true')
  expect(hold.seen).toBe(1)
  await hold.release()

  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await expect(fact(page, 'post', 'status=error')).toBeVisible()
  // Not an error state: the stale post is still part of the combination.
  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(page.getByText(TITLE, { exact: true })).toBeVisible()
  await expect(overview(page, 'comments=3')).toBeVisible()
  await expect(overview(page, 'refetchError=Requested: 500')).toBeVisible()
  await expect(page.getByText('Could not refresh: Requested: 500', { exact: true })).toBeVisible()
  // `refetch()` went to all three.
  expect(await scenario.count('GET', POST)).toBe(1)
  expect(await scenario.count('GET', COMMENTS)).toBe(1)
  expect(await scenario.count('GET', COUNTER)).toBe(1)

  // Answered again, the next refetch clears it.
  await setPostRead(page, 'answers')
  await button(page, 'Refetch all').click()
  await expect(overview(page, 'refetchError=none')).toBeVisible()
  await expect(page.getByText('Could not refresh: Requested: 500', { exact: true })).toBeHidden()
})

test('reset with the post refused is the error state until a retry is answered', async ({ page, open }) => {
  await open('/combine')
  await expect(combined(page, 'state=data')).toBeVisible()
  await setPostRead(page, 'is refused')

  // Reset drops the data, so this refusal has nothing to fall back on.
  await button(page, 'Reset').click()
  await expect(combined(page, 'state=error')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await expect(page.getByText('Requested: 500', { exact: true })).toBeVisible()
  await expect(group(page, 'overview')).toBeHidden()

  await setPostRead(page, 'answers')
  await button(page, 'Retry').click()
  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(overview(page, 'refetchError=none')).toBeVisible()
  await expect(page.getByText(TITLE, { exact: true })).toBeVisible()
})

test('the memo skips the combiner while every source holds the same data', async ({ page, open, scenario }) => {
  await open('/combine')
  await expect(combined(page, 'state=data')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  await expect(combined(page, 'combines=1')).toBeVisible()
  const builds = await factNumber(page, 'combined', 'builds')

  // Nothing changed at the backend: every source keeps the instance it had,
  // the screen rebuilt for `isFetching`, and the combiner was not asked again.
  await button(page, 'Refetch all').click()
  await expect(fact(page, 'counter', 'fetches=2')).toBeVisible()
  await expect(combined(page, 'isFetching=false')).toBeVisible()
  expect(await scenario.count('GET', COUNTER)).toBe(2)
  expect(await factNumber(page, 'combined', 'builds')).toBeGreaterThan(builds)
  await expect(combined(page, 'combines=1')).toBeVisible()

  // A source with new data is a new combination.
  await button(page, 'Increment counter').click()
  await expect(overview(page, 'counter=1')).toBeVisible()
  await expect(combined(page, 'combines=2')).toBeVisible()
})

test.describe('a list, its details and a pinned post', () => {
  // The section sits below the combined card: tall enough that the
  // scaffold's list builds it without a scroll.
  test.use({ viewport: { width: 1280, height: 2400 } })

  const LIST = /^\/api\/posts$/
  const DETAILS = /^\/api\/posts\/[234]$/
  const THIRD = /^\/api\/posts\/4$/
  const DELETED = /^\/api\/posts\/999$/
  const DETAIL_TITLES = [
    'Continuous integration: setup guide',
    'Code review: setup guide',
    'Release notes: setup guide',
  ].join(' · ')
  const PINNED = 'Staging environment: setup guide'

  const details = (page: Page, text: string) => factIn(page, 'details', text)

  const pinned = (page: Page, text: string) => factIn(page, 'pinned', text)

  async function choose(page: Page, knob: string, label: string) {
    const choice = segment(group(page, knob), label)
    await choice.click()
    await expectSelected(choice)
  }

  test('combineWith: the list and a read per item are one combination', async ({ page, open, scenario }) => {
    // The second detail held: the list and two details are in, and the
    // whole still waits.
    const hold = holdRequest(page, '**/api/posts/3*')
    await open('/combine')

    // The details go out once the list is in.
    await expect.poll(() => hold.seen).toBe(1)
    await expect.poll(() => scenario.count('GET', DETAILS)).toBe(2)
    await expect(details(page, 'state=pending')).toBeVisible()
    await expect(details(page, 'isFetching=true')).toBeVisible()
    await hold.release()

    await expect(details(page, 'state=data')).toBeVisible()
    await expect(details(page, 'items=3')).toBeVisible()
    await expect(details(page, 'refetchError=none')).toBeVisible()
    await expect(page.getByText(DETAIL_TITLES, { exact: true })).toBeVisible()
    expect(await scenario.count('GET', LIST)).toBe(1)
    expect(await scenario.count('GET', DETAILS)).toBe(3)
  })

  test('a refused detail keeps the titles as refetchError, and retry reads only that detail', async ({
    page,
    open,
    scenario,
  }) => {
    await open('/combine')
    await expect(details(page, 'items=3')).toBeVisible()
    await expect(details(page, 'isFetching=false')).toBeVisible()
    await scenario.clearRequests()

    await choose(page, 'detail knob', 'the third is refused')
    await button(page, 'Refetch details').click()

    await expect(details(page, 'refetchError=Requested: 500')).toBeVisible()
    await expect(details(page, 'isFetching=false')).toBeVisible()
    // Not an error state: every title is still on screen.
    await expect(details(page, 'state=data')).toBeVisible()
    await expect(page.getByText(DETAIL_TITLES, { exact: true })).toBeVisible()
    // `refetch()` went to the list and every detail.
    expect(await scenario.count('GET', LIST)).toBe(1)
    expect(await scenario.count('GET', DETAILS)).toBe(3)

    await choose(page, 'detail knob', 'all answer')
    await scenario.clearRequests()
    await button(page, 'Retry details').click()

    await expect(details(page, 'refetchError=none')).toBeVisible()
    await expect(details(page, 'isFetching=false')).toBeVisible()
    // `retry()` went to the refused detail alone.
    expect(await scenario.count('GET', THIRD)).toBe(1)
    expect(await scenario.count('GET', DETAILS)).toBe(1)
    expect(await scenario.count('GET', LIST)).toBe(0)
  })

  test('optional: a deleted pinned post leaves the combination data, and retry still reads it', async ({
    page,
    open,
    scenario,
  }) => {
    await open('/combine')
    await expect(pinned(page, `pinned=${PINNED}`)).toBeVisible()
    await expect(pinned(page, 'state=data')).toBeVisible()

    await choose(page, 'pinned knob', 'a deleted post')

    // A 404 with nothing to fall back on — and the whole is still data.
    await expect(pinned(page, 'pinned=none')).toBeVisible()
    await expect(pinned(page, 'state=data')).toBeVisible()
    await expect(pinned(page, 'isFetching=false')).toBeVisible()
    expect(await scenario.count('GET', DELETED)).toBe(1)

    await scenario.clearRequests()
    await button(page, 'Retry pinned').click()

    // The stand-in remembers its origin: retry reached the refused read and
    // left the list alone.
    await expect.poll(() => scenario.count('GET', DELETED)).toBe(1)
    await expect(pinned(page, 'isFetching=false')).toBeVisible()
    await expect(pinned(page, 'pinned=none')).toBeVisible()
    expect(await scenario.count('GET', LIST)).toBe(0)
  })
})
