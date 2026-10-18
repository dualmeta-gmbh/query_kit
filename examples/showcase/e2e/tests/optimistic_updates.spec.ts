import type { Page } from '@playwright/test'
import { button, expect, fact, segment, test, typeInto } from './fixtures'

// The add card, the strip and a list of four rows are taller than the default
// viewport, and the scaffold's list builds only what is in view.
test.use({ viewport: { width: 1280, height: 1100 } })

const TODOS = /^\/api\/todos$/

/// `holdRequest` for one method only: `page.route` cannot filter by method,
/// so the handler lets everything else through — the GET that `onSettled`
/// triggers has to land while a POST hold is still installed, and so has the
/// CORS preflight that precedes the request itself. A request the page
/// aborted while it was held has nothing left to let go, so its `continue`
/// is allowed to fail.
function holdMethod(page: Page, method: 'GET' | 'POST') {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  let seen = 0
  const routed = page.route('**/api/todos*', async (route) => {
    if (route.request().method() !== method) {
      await route.continue()
      return
    }
    seen += 1
    await held
    await route.continue().catch(() => {})
  })
  return {
    get seen() {
      return seen
    },
    async release() {
      await routed
      letGo()
    },
  }
}

const holdPost = (page: Page) => holdMethod(page, 'POST')

/// Types `text` into the field and presses `Add`.
async function add(page: Page, text: string) {
  await typeInto(page, page.getByRole('textbox'), text)
  await button(page, 'Add').click()
}

/// Switches to the cache variant and waits for its mount refetch: the
/// `QueryBuilder` is a fresh observer on an entry whose default `staleTime`
/// is zero, so the switch itself costs a GET, and a hold installed before it
/// settled would count that too.
async function viaCache(page: Page) {
  await segment(page, 'Via cache').click()
  await expect(page.getByText('Todos · via cache', { exact: true })).toBeVisible()
  await expect(fact(page, 'todos', 'fetches=2')).toBeVisible()
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
}

const refuseNext = (page: Page) => page.getByRole('checkbox', { name: 'Refuse next write' })

/// A click, then the state: Playwright's `check()` reads `aria-checked` right
/// after the click, and Flutter updates its semantics a frame later.
async function tickRefuseNext(page: Page) {
  await refuseNext(page).click()
  await expect(refuseNext(page)).toBeChecked()
}

test('via variables, a held write is a saving row and not a cache entry', async ({ page, open, scenario }) => {
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()

  const hold = holdPost(page)
  await add(page, 'Order new batteries')

  // The backend has provably not answered: the POST is held in the browser.
  // The row is the mutation's variables; the cache still holds three.
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=true', { exact: true })).toBeVisible()
  await expect(button(page, 'Add')).toHaveAttribute('aria-disabled', 'true')
  expect(hold.seen).toBe(1)
  expect(await scenario.count('POST', TODOS)).toBe(0)
  await hold.release()

  // One write, one refetch, and the row is the backend's now.
  await expect(page.getByText('#4', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeHidden()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
  expect(await scenario.count('GET', TODOS)).toBe(2)
})

test('via variables, a refused write keeps its row as an error with Retry', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()

  await tickRefuseNext(page)
  await add(page, 'Order new batteries')

  await expect(page.getByText('Not saved: Requested: 500', { exact: true })).toBeVisible()
  await expect(button(page, 'Retry')).toBeVisible()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeHidden()
  // Three real rows plus the error row: the cache was never written, and
  // `onSettled` refetched it all the same.
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
  expect(await scenario.count('GET', TODOS)).toBe(2)
  // The refusal was consumed by the write that carried it.
  await expect(refuseNext(page)).not.toBeChecked()

  await button(page, 'Retry').click()

  await expect(page.getByText('#4', { exact: true })).toBeVisible()
  await expect(page.getByText('Not saved: Requested: 500', { exact: true })).toBeHidden()
  await expect(button(page, 'Retry')).toBeHidden()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(2)
  expect(await scenario.count('GET', TODOS)).toBe(3)
})

test('via cache, a held write is in the cache before the backend answers', async ({ page, open, scenario }) => {
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await viaCache(page)
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()

  const hold = holdPost(page)
  await add(page, 'Order new batteries')

  // Held in the browser, and the list already has four rows: the fourth is
  // the cache's optimistic entry.
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=true', { exact: true })).toBeVisible()
  await expect(page.getByText('#4', { exact: true })).toBeHidden()
  expect(hold.seen).toBe(1)
  expect(await scenario.count('POST', TODOS)).toBe(0)
  await hold.release()

  // The refetch on settle replaces the temporary row with the backend's.
  await expect(page.getByText('#4', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeHidden()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
  expect(await scenario.count('GET', TODOS)).toBe(3)
})

test('via cache, a refused write is rolled back and the list refetched', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await viaCache(page)
  await tickRefuseNext(page)

  // Held first, so the row is seen before the refusal takes it away again.
  const hold = holdPost(page)
  await add(page, 'Order new batteries')
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await hold.release()

  await expect(page.getByText('Rolled back: Requested: 500', { exact: true })).toBeVisible()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeHidden()
  await expect(page.getByText('todos=3', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  await expect(refuseNext(page)).not.toBeChecked()
  expect(await scenario.count('POST', TODOS)).toBe(1)
  // The refetch on settle happened after the failed write too.
  expect(await scenario.count('GET', TODOS)).toBe(3)
  const todos = (await (await scenario.api('get', '/todos')).json()) as Array<{ id: number }>
  expect(todos.map((todo) => todo.id)).toEqual([1, 2, 3])
})

test("via cache, onMutate's cancelQueries ends a refetch that is in flight before the row is written", async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await viaCache(page)
  const reads = await scenario.count('GET', TODOS)

  // A refetch the backend has not answered: held in the browser. (Both holds
  // route `**/api/todos*`; Playwright runs the later-registered route first, so
  // the POST hold below shadows this one for the GET `onSettled` triggers —
  // each hold passes through what is not its own method.)
  const holdGet = holdMethod(page, 'GET')
  await button(page, 'Refetch').click()
  await expect.poll(() => holdGet.seen).toBe(1)
  await expect(fact(page, 'todos', 'fetchStatus=fetching')).toBeVisible()

  const holdWrite = holdPost(page)
  await add(page, 'Order new batteries')

  // With the POST held too, the only thing that can have ended the refetch is
  // the write's own `cancelQueries`: the entry is idle while its request is
  // still unanswered, and the optimistic row is already in the cache. Its
  // late answer would have put the backend's three rows back over it.
  await expect.poll(() => holdWrite.seen).toBe(1)
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  await expect(page.getByText('Order new batteries', { exact: true })).toBeVisible()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await holdGet.release()
  await holdWrite.release()

  await expect(page.getByText('#4', { exact: true })).toBeVisible()
  await expect(page.getByText('saving', { exact: true })).toBeHidden()
  await expect(page.getByText('todos=4', { exact: true })).toBeVisible()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  expect(await scenario.count('POST', TODOS)).toBe(1)
  // The cancelled refetch never reached the backend; the settle's did.
  expect(await scenario.count('GET', TODOS)).toBe(reads + 1)
})

test('a blank entry sends nothing, and an accepted one empties the field', async ({ page, open, scenario }) => {
  await open('/optimistic-updates')
  await expect(fact(page, 'todos', 'fetchStatus=idle')).toBeVisible()
  const field = page.getByRole('textbox')

  await typeInto(page, field, '   ')
  await button(page, 'Add').click()

  // Nothing started: no row, no pending write, and the button is still free.
  await expect(page.getByText('saving', { exact: true })).toBeHidden()
  await expect(page.getByText('pending=false', { exact: true })).toBeVisible()
  await expect(button(page, 'Add')).not.toHaveAttribute('aria-disabled', 'true')

  // The same field, now with a text: the first and only write.
  await typeInto(page, field, 'Order new batteries')
  await button(page, 'Add').click()
  await expect(page.getByText('#4', { exact: true })).toBeVisible()
  await expect(field).toHaveValue('')
  expect(await scenario.count('POST', TODOS)).toBe(1)
  const todos = (await (await scenario.api('get', '/todos')).json()) as Array<{ text: string }>
  expect(todos.map((todo) => todo.text)).toEqual(expect.arrayContaining(['Order new batteries']))
  expect(todos).toHaveLength(4)
})
