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
    expect(write.seen).toBe(1)

    await write.release()
    await expect(factIn(page, 'activity', 'saving 0')).toBeVisible()
    await expect(todo(page, checklist)).toBeChecked()
    expect((await (await scenario.api('get', '/todos')).json())[0].done).toBe(true)
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
    expect(writes.seen).toBe(2)

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
})
