// Creating a task through the UI, and the empty state a search can leave.
//
// The "New task" button makes a task named "New task" every time — no unique
// name to find it by — so each test starts from a backend that holds none
// (the sweep removes them by that fixed name) and counts from there.
import { expect, test, type APIRequestContext, type Page } from '@playwright/test'
import { NEW_TASK_NAME, listTasks, requestCounter, sweepTestTasks, uniqueName } from './backend'
import { trackInputListeners, typeInto } from './flutter_input'
import { control, holdRequests, listSettled, newTaskButton, open, row, searchField } from './helpers'

test.beforeEach(async ({ page, request }) => {
  await trackInputListeners(page)
  await sweepTestTasks(request)
})
test.afterAll(async ({ request }) => sweepTestTasks(request))
test.use({ viewport: { width: 1280, height: 1600 } })

// The row of a created task: its name, then the defaults the backend gives it.
const created = (page: Page) => row(page, /^New task Normal · Inbox · 0 %/)
const createdOnBackend = async (request: APIRequestContext) =>
  (await listTasks(request)).filter((task) => task.name === NEW_TASK_NAME)

test('the New task button creates a task and the row appears on screen', async ({ page, request }) => {
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)
  const header = page.getByText(/\d+ of \d+ synced/)
  const [synced, total] = ((await header.textContent()) ?? '').match(/\d+/g)!.map(Number)

  await newTaskButton(page).click()

  // No optimistic row: the task is the backend's to make (it owns the id and
  // the server-side fields), so the row is there once the create has
  // invalidated the list and the list has come back with it.
  await expect(created(page)).toHaveCount(1)
  expect(requests.creates()).toBe(1)
  expect(requests.lists()).toBe(1)
  expect(await createdOnBackend(request)).toHaveLength(1)
  // The header counts it too (it is synced): it selects from the same list
  // entry.
  await expect(header).toHaveText(`${synced + 1} of ${total + 1} synced`)
})

test('the create button is locked while the write is in flight', async ({ page, request }) => {
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)

  // Held at the network layer, so the lock is asserted while the backend
  // provably has not answered. The lock is `flt-tappable` going away from the
  // node (see `control`), with the attribute on the same node before the
  // press and after the write as the control that the absence means something.
  const create = control(page, 'New task')
  await expect(create).toHaveAttribute('flt-tappable')
  const box = (await newTaskButton(page).boundingBox())!
  const write = holdRequests(page, 'POST', '**/api/tasks')
  await create.click()
  await expect(create).not.toHaveAttribute('flt-tappable')
  // A second press, at the place the button is, does nothing.
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  expect(await createdOnBackend(request)).toHaveLength(0)

  await write.release()
  await expect(created(page)).toHaveCount(1)
  await expect(create).toHaveAttribute('flt-tappable')
  // Exactly one task, and one write: the second press made no second task.
  expect(await createdOnBackend(request)).toHaveLength(1)
  expect(requests.creates()).toBe(1)
})

test('a created task survives a reload, because the backend has it', async ({ page }) => {
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()
  await newTaskButton(page).click()
  await expect(created(page)).toHaveCount(1)

  await page.reload()
  await expect(created(page)).toHaveCount(1)
})

test('a search that matches nothing shows the empty state', async ({ page }) => {
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()

  await typeInto(page, searchField(page), uniqueName('Nothing called'))
  await expect(page.getByText('No tasks found.')).toBeVisible()
  await expect(page.getByRole('button', { name: /^Delete / })).toHaveCount(0)
})

test('clearing the search brings the rows back without a new request', async ({ page }) => {
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()
  const search = searchField(page)
  await typeInto(page, search, uniqueName('Nothing called'))
  await expect(page.getByText('No tasks found.')).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)

  // The unfiltered entry is still cached and still fresh (45 s), so the
  // rows are back from it: the list is settled — not fetching — in the very
  // frame they appear in, which is what "no request" means here.
  await typeInto(page, search, '')
  await expect(row(page, 'Write the release notes')).toBeVisible()
  await expect(page.getByText('No tasks found.')).toBeHidden()
  await listSettled(page)
  expect(requests.lists()).toBe(0)
})
