// The Todos tab: a list written to optimistically, through the cache and
// through the mutation's own variables.
import { expect, factIn, group, holdRequest, test, todo, typeInto, type Page } from './fixtures'

const checklist = 'Update the deploy checklist'
const token = 'Replace the expired API token'

async function openTodos(page: Page, open: () => Promise<void>) {
  await open()
  await page.getByRole('tab', { name: 'Todos' }).click()
  await expect(factIn(page, 'open todos', '2 open')).toBeVisible()
}

test.describe('useMutation', () => {
  test('a tick shows before the backend has it, and stays', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    const write = holdRequest(page, /\/api\/todos\/1$/)
    await todo(page, checklist).click()
    await expect(todo(page, checklist)).toBeChecked()
    await expect(factIn(page, 'activity', 'saving 1')).toBeVisible()
    await expect.poll(() => write.seen).toBe(1)
    // A todo with a write in flight takes no second one.
    await expect(todo(page, checklist)).toBeDisabled()

    await write.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect(todo(page, checklist)).toBeChecked()
    await expect(todo(page, checklist)).toBeEnabled()
    expect((await (await scenario.api('get', '/todos')).json())[0].done).toBe(true)
  })

  test('a tick answered first leaves another todo’s tick in flight alone', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    const slow = holdRequest(page, /\/api\/todos\/3$/)
    const refetch = holdRequest(page, /\/api\/todos$/)
    await todo(page, token).click()
    await todo(page, checklist).click()
    await expect.poll(() => slow.seen).toBe(1)

    // The other write is answered and settles without a refetch, which would
    // find the held tick undone.
    await expect.poll(() => scenario.count('PATCH', /^\/api\/todos\/1$/)).toBe(1)
    await expect(factIn(page, 'activity', 'saving 1')).toBeVisible()
    expect(refetch.seen).toBe(0)
    await expect(todo(page, token)).toBeChecked()
    await expect(factIn(page, 'open todos', '0 open')).toBeVisible()

    // The write that settles with no other in flight refetches, and the
    // backend agrees.
    await refetch.release()
    await slow.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect(todo(page, token)).toBeChecked()
    await expect(todo(page, checklist)).toBeChecked()
    expect(refetch.seen).toBe(1)
    await expect.poll(() => scenario.count('GET', /^\/api\/todos$/)).toBe(2)
    const stored = await (await scenario.api('get', '/todos')).json()
    expect(stored.map((todo: { done: boolean }) => todo.done)).toEqual([true, true, true])
  })
})

test.describe('useQuery', () => {
  test('a tab change while a tick is in flight reads no list over it', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    const slow = holdRequest(page, /\/api\/todos\/3$/)
    const reads = holdRequest(page, /\/api\/todos$/)
    await todo(page, token).click()
    await expect.poll(() => slow.seen).toBe(1)

    // Away and back. The list is never fresh, but a read now could answer
    // before the write, with the todo unticked. A read would be held, and
    // the activity would say so.
    await page.getByRole('tab', { name: 'Posts' }).click()
    await expect(group(page, 'todos')).toHaveCount(0)
    await page.getByRole('tab', { name: 'Todos' }).click()
    await expect(todo(page, token)).toBeChecked()
    await expect(factIn(page, 'activity', 'fetching 0')).toBeVisible()
    expect(reads.seen).toBe(0)

    // The write answers, and its refetch is the read.
    await slow.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect.poll(() => reads.seen).toBe(1)
    await reads.release()
    await expect(factIn(page, 'activity', 'fetching 0')).toBeVisible()
    await expect(todo(page, token)).toBeChecked()
    await expect.poll(() => scenario.count('GET', /^\/api\/todos$/)).toBe(2)
  })
})

test.describe('useQueryClient', () => {
  test('the write goes to the cache: the open count moves before the backend answers', async ({ page, open }) => {
    await openTodos(page, open)
    const write = holdRequest(page, /\/api\/todos\/1$/)
    await todo(page, checklist).click()
    // The heading reads the same cache entry through its own selector, so
    // it moving says the client wrote the entry, not that a widget did.
    await expect(factIn(page, 'open todos', '1 open')).toBeVisible()

    await write.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect(factIn(page, 'open todos', '1 open')).toBeVisible()
  })
})

test.describe('useMutationState', () => {
  test('a refused tick is taken back, and the failure counted', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    await scenario.config({ failNext: [{ method: 'PATCH', path: '/api/todos/1', count: 1, status: 409, message: 'Taken' }] })
    await todo(page, checklist).click()

    await expect(factIn(page, 'activity', 'failed 1')).toBeVisible()
    await expect(factIn(page, 'activity', 'last failure: Taken')).toBeVisible()
    await expect(todo(page, checklist)).not.toBeChecked()
    await expect(factIn(page, 'open todos', '2 open')).toBeVisible()
    expect((await (await scenario.api('get', '/todos')).json())[0].done).toBe(false)
  })
})

test.describe('useIsMutating', () => {
  test('counts the todo writes in flight', async ({ page, open }) => {
    await openTodos(page, open)
    const writes = holdRequest(page, /\/api\/todos\/[13]$/)
    await todo(page, checklist).click()
    await todo(page, token).click()
    await expect(factIn(page, 'activity', 'saving 2')).toBeVisible()
    await expect.poll(() => writes.seen).toBe(2)

    await writes.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect(factIn(page, 'open todos', '0 open')).toBeVisible()
  })
})

test.describe('useTypedMutationState', () => {
  test('an added todo shows as pending until the list has it', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    const add = holdRequest(page, /\/api\/todos$/)
    await typeInto(page, page.getByRole('textbox', { name: 'New todo' }), 'Write the README')
    await page.getByRole('button', { name: 'Add' }).click()
    await expect(factIn(page, 'todos', 'Adding: Write the README')).toBeVisible()
    await expect(factIn(page, 'activity', 'saving 1')).toBeVisible()

    // `add` holds the list's refetch as well as the write; both go now.
    await add.release()
    await expect(todo(page, 'Write the README')).toBeVisible()
    await expect(factIn(page, 'todos', 'Adding: Write the README')).toHaveCount(0)
    await expect(factIn(page, 'open todos', '3 open')).toBeVisible()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(1)
    await expect(group(page, 'todos').getByRole('checkbox')).toHaveCount(4)
  })

  test('every add in flight is a row, and the rows outlive the tab that started them', async ({ page, open, scenario }) => {
    await openTodos(page, open)
    const adds = holdRequest(page, /\/api\/todos$/)
    for (const text of ['Write the README', 'Tag the release']) {
      await typeInto(page, page.getByRole('textbox', { name: 'New todo' }), text)
      await page.getByRole('button', { name: 'Add' }).click()
      await expect(factIn(page, 'todos', `Adding: ${text}`)).toBeVisible()
    }
    await expect.poll(() => adds.seen).toBe(2)

    // Away and back: the tab is built anew, and the adds are in the
    // mutation cache, not in the tab.
    await page.getByRole('tab', { name: 'Posts' }).click()
    await expect(group(page, 'todos')).toHaveCount(0)
    await page.getByRole('tab', { name: 'Todos' }).click()
    await expect(factIn(page, 'todos', 'Adding: Write the README')).toBeVisible()
    await expect(factIn(page, 'todos', 'Adding: Tag the release')).toBeVisible()
    await expect(factIn(page, 'activity', 'saving 2')).toBeVisible()

    await adds.release()
    await expect(todo(page, 'Write the README')).toBeVisible()
    await expect(todo(page, 'Tag the release')).toBeVisible()
    await expect(group(page, 'todos').getByText(/^Adding: /)).toHaveCount(0)
    await expect(factIn(page, 'open todos', '4 open')).toBeVisible()
    expect(await scenario.count('POST', /^\/api\/todos$/)).toBe(2)
  })
})
