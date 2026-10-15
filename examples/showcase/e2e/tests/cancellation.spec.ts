import { expect, fact, factIn, holdRequest, strip, test, type Page, typeInto } from './fixtures'

// Two cards and up to three strips: taller than the default viewport, and a
// lazily built list only has what is in view.
test.use({ viewport: { width: 1280, height: 1800 } })

const POSTS = /^\/api\/posts$/
const SEARCH = /^\/api\/search$/

/// A card's facts live in a group of their own, because `status=` and
/// `fetchStatus=` are also what the debug strips say about the same entries.
const slow = (page: Page, text: string) => factIn(page, 'slow facts', text)

const searched = (page: Page, text: string) => factIn(page, 'search facts', text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

/// Every request the browser gave up on, by URL fragment. An aborted XHR is
/// reported as `requestfailed` with `net::ERR_ABORTED`, which is the browser's
/// own word for "the signal reached the transport" — no clock involved.
function abortedRequests(page: Page, fragment: string) {
  const aborted: string[] = []
  page.on('requestfailed', (request) => {
    if (request.url().includes(fragment)) aborted.push(request.failure()?.errorText ?? 'failed')
  })
  return aborted
}

async function typeNeedle(page: Page, needle: string) {
  await typeInto(page, page.getByRole('textbox'), needle)
}

test('cancelling the slow fetch reverts it to idle and aborts the request', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/posts')
  await open('/cancellation')

  // The screen's own fetch is out, and three seconds from an answer.
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
  await expect(slow(page, 'cancels=0')).toBeVisible()

  await button(page, 'Cancel').click()

  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await expect(slow(page, 'cancels=1')).toBeVisible()
  // `revert` is the default: a cancelled first fetch is pending again, not an
  // error, and holds nothing.
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
  await expect(fact(page, 'slow', 'fetchStatus=idle')).toBeVisible()

  // The browser gave the request up, and the backend — still sleeping out the
  // three seconds — never answered it.
  await expect.poll(() => aborted.length).toBe(1)
  expect(await scenario.count('GET', POSTS)).toBe(0)
})

test('a silent cancel leaves the reader with no error', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/posts')
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  await button(page, 'Cancel silently').click()

  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await expect(slow(page, 'cancels=1')).toBeVisible()
  // The whole point of `silent`: nothing about the status changed.
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(fact(page, 'slow', 'status=pending')).toBeVisible()
  await expect(fact(page, 'slow', 'failures=0')).toBeVisible()
  await expect.poll(() => aborted.length).toBe(1)
  expect(await scenario.count('GET', POSTS)).toBe(0)
})

test('a cancelled entry starts over and loads all thirty posts', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await button(page, 'Cancel').click()
  await expect(slow(page, 'status=pending')).toBeVisible()

  await button(page, 'Start slow fetch').click()
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  await expect(slow(page, 'posts=30')).toBeVisible()
  await expect(slow(page, 'status=success')).toBeVisible()
  expect(await scenario.count('GET', POSTS)).toBe(1)
})

test('two keystrokes inside the debounce window send one request', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(searched(page, 'needle=none')).toBeVisible()

  const field = page.getByRole('textbox')
  await typeInto(page, field, 'met')
  await field.fill('metr')

  // Only the last needle ever became a key, so nothing was there to cancel.
  await expect(searched(page, 'needle=metr')).toBeVisible()
  await expect(searched(page, 'results=1')).toBeVisible()
  await expect(searched(page, 'searchCancels=0')).toBeVisible()
  await expect(page.getByText('Metrics dashboard: setup guide', { exact: true })).toBeVisible()
  await expect(strip(page, 'previous')).toBeHidden()
  expect(await scenario.count('GET', SEARCH)).toBe(1)
})

test('a needle typed while the last is in flight cancels it', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  const aborted = abortedRequests(page, '/api/search')
  await open('/cancellation')
  await expect(searched(page, 'needle=none')).toBeVisible()

  // `a` is held in the browser, so it is still in flight when `az` is
  // committed however long the typing takes — the one-second answer alone
  // was outrun by WebKit under load.
  const hold = holdRequest(page, (url) => url.pathname === '/api/search' && url.searchParams.get('q') === 'a')
  await typeNeedle(page, 'a')
  await expect(searched(page, 'needle=a')).toBeVisible()
  await expect(searched(page, 'searching=true')).toBeVisible()
  await expect.poll(() => hold.seen).toBe(1)

  await typeNeedle(page, 'az')

  await expect(searched(page, 'needle=az')).toBeVisible()
  await expect(searched(page, 'searchCancels=1')).toBeVisible()
  await expect.poll(() => aborted.length).toBe(1)
  await hold.release()
  // The abandoned needle keeps its entry, reverted to before the fetch.
  await expect(fact(page, 'previous', 'fetchStatus=idle')).toBeVisible()
  await expect(fact(page, 'previous', 'status=pending')).toBeVisible()

  // `az` matches nothing and `a` matches most posts: neither arrives.
  await expect(searched(page, 'results=0')).toBeVisible()
  await expect(page.getByText('Local development: setup guide', { exact: true })).toBeHidden()
  expect(await scenario.count('GET', SEARCH)).toBe(1)
})

test('an abandoned needle whose answer arrives after the next one never shows', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  const ignores = page.getByRole('switch', { name: 'Search ignores the signal', exact: true })
  await ignores.click()
  await expect(ignores).toBeChecked()

  // `a` is held in the browser: not aborted, since nothing reads the signal,
  // and answered only once `az` has been.
  const hold = holdRequest(page, (url) => url.pathname === '/api/search' && url.searchParams.get('q') === 'a')
  await typeNeedle(page, 'a')
  await expect(searched(page, 'needle=a')).toBeVisible()
  await expect.poll(() => hold.seen).toBe(1)

  await typeNeedle(page, 'az')
  await expect(searched(page, 'needle=az')).toBeVisible()
  await expect(searched(page, 'results=0')).toBeVisible()
  await expect(searched(page, 'searching=false')).toBeVisible()
  expect(await scenario.count('GET', SEARCH)).toBe(1)

  // Now `a`'s answer: most of the posts, delivered to the app after `az`'s.
  const late = page.waitForResponse((response) => new URL(response.url()).searchParams.get('q') === 'a')
  await hold.release()
  expect((await late).ok()).toBe(true)
  const order = (await scenario.requests()).filter((entry) => SEARCH.test(entry.path)).map((entry) => entry.query.q)
  expect(order).toEqual(['az', 'a'])

  // Thrown away: the screen stays on `az`, and the cancelled entry was
  // reverted rather than written.
  await expect(fact(page, 'previous', 'status=pending')).toBeVisible()
  await expect(fact(page, 'previous', 'fetchStatus=idle')).toBeVisible()
  await expect(searched(page, 'needle=az')).toBeVisible()
  await expect(searched(page, 'results=0')).toBeVisible()
  await expect(page.getByText('Local development: setup guide', { exact: true })).toBeHidden()
})

test('a query function that ignores the signal is cancelled, its request is not', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/cancellation')
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()

  // Clear the fetch the screen started on mount; the switch governs the next.
  await button(page, 'Cancel').click()
  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  await scenario.clearRequests()

  const ignore = page.getByRole('switch', { name: 'Ignore the signal', exact: true })
  await ignore.click()
  await expect(ignore).toBeChecked()

  await button(page, 'Start slow fetch').click()
  await expect(slow(page, 'fetchStatus=fetching')).toBeVisible()
  await button(page, 'Cancel').click()
  await expect(slow(page, 'fetchStatus=idle')).toBeVisible()
  // Nothing registered an `onCancel` this time, so the count is unchanged.
  await expect(slow(page, 'cancels=1')).toBeVisible()

  // The token never reached dio, so the backend answers the request in full —
  // and the query, cancelled and reverted, throws that answer away.
  await expect.poll(() => scenario.count('GET', POSTS), { timeout: 15_000 }).toBe(1)
  await expect(slow(page, 'status=pending')).toBeVisible()
  await expect(slow(page, 'posts=none')).toBeVisible()
})
