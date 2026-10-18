// End-to-end: the real web build in a real Chromium, against the real express
// backend. What the widget tests cannot see — the browser's HTTP stack, real
// timers, the wire — is exactly what these assert on.
//
// Flutter web paints to a canvas; the tests read the semantics tree the E2E
// build switches on (`--dart-define=E2E=true`), the same tree a screen reader
// gets: rows are groups named after the task, buttons carry their tooltips.
import { expect, test } from '@playwright/test'
import { createTask, getTask, listTasks, requestCounter, sweepTestTasks, uniqueName } from './backend'
import { trackInputListeners, typeInto } from './flutter_input'
import { deleteButton, heroTitle, holdRequests, holdWrite, open, row, waitingForScheduler } from './helpers'

// The list builds only the rows in view, and a created task lands at the
// end of it — so the leftovers of earlier runs are cleared away, and the
// viewport is tall enough for the seed rows plus a test's own.
test.beforeAll(async ({ request }) => sweepTestTasks(request))
test.afterAll(async ({ request }) => sweepTestTasks(request))
test.use({ viewport: { width: 1280, height: 1600 } })
test.beforeEach(({ page }) => trackInputListeners(page))

test('loads the tasks from the backend, one request for the whole screen', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('First load'))
  const requests = requestCounter(page)

  await open(page)
  await expect(row(page, task.name)).toBeVisible()
  await expect(page.getByText(/\d+ of \d+ synced/)).toBeVisible()

  // Header badge, list and every row render from one list response: the
  // header selects from the same cache entry, and the list's query function
  // seeds each per-task entry, so no row fetches on its own.
  await page.waitForTimeout(1500)
  expect(requests.lists()).toBe(1)
  expect(requests.details()).toBe(0)
})

test('opening a task and coming back costs no request while the data is fresh', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Fresh'))
  await open(page)
  await expect(row(page, task.name)).toBeVisible()
  const requests = requestCounter(page)

  await row(page, task.name).click()
  await expect(heroTitle(page)).toContainText(task.name)
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, task.name)).toBeVisible()

  await page.waitForTimeout(1000)
  expect(requests.details()).toBe(0)
  expect(requests.lists()).toBe(0)
})

test('the refresh button refetches without dropping the rows', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Refreshed'))
  await open(page)
  await expect(row(page, task.name)).toBeVisible()

  const refetch = page.waitForRequest((r) => r.method() === 'GET' && /\/api\/tasks$/.test(new URL(r.url()).pathname))
  await page.getByRole('button', { name: 'Reload', exact: true }).click()
  await refetch
  // Refetching, not loading: the rows stay while the request is out.
  await expect(row(page, task.name)).toBeVisible()
  await expect(page.getByRole('button', { name: 'Reload', exact: true })).not.toHaveAttribute('aria-disabled', 'true', { timeout: 10_000 })
})

test('renames optimistically and the backend keeps the name', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Before'))
  const newName = uniqueName('After')
  await open(page)
  await row(page, task.name).click()

  // The semantic input mirrors the field's text once it has focus, and a
  // click is what focuses it — the same as for a user.
  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(task.name)
  await typeInto(page, field, newName)

  // Hold the write at the network layer, so "optimistic" is proven by
  // construction: the backend has provably not answered while we assert. A
  // wall-clock budget instead would be a guess about how fast the browser
  // repaints and republishes its semantics tree, which is what a busy machine
  // makes flaky.
  const write = holdWrite(page)
  await page.getByRole('button', { name: 'Rename', exact: true }).click()
  await expect(heroTitle(page)).toContainText(newName)
  await write.release()

  // And still there once the write has gone through.
  await expect(page.getByRole('button', { name: 'Rename', exact: true })).not.toHaveAttribute('aria-disabled', 'true', { timeout: 10_000 })
  await expect(heroTitle(page)).toContainText(newName)
  expect((await getTask(request, task.id))?.name).toBe(newName)

  // The overview row reads the same per-task query, so it agrees without a
  // list refetch; and a fresh page load agrees because the backend does.
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, newName)).toBeVisible()
  await page.reload()
  await expect(row(page, newName)).toBeVisible()
})

test('a refused rename rolls back on screen and in the field', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Unchanged'))
  await open(page)
  await row(page, task.name).click()

  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(task.name)
  await typeInto(page, field, 'fail')

  // Same as the rename above: the rejected name has to be on screen while the
  // backend still owes an answer, so the write is held until we have seen it.
  const write = holdWrite(page)
  await page.getByRole('button', { name: 'Rename', exact: true }).click()
  await expect(heroTitle(page)).toContainText('fail')
  await write.release()

  await expect(page.getByText('The server refused the write')).toBeVisible()
  await expect(heroTitle(page)).toContainText(task.name)
  await field.click()
  await expect(field).toHaveValue(task.name)
  expect((await getTask(request, task.id))?.name).toBe(task.name)
})

test('renaming to an empty name is refused and the field keeps the old name', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Keeps its name'))
  await open(page)
  await row(page, task.name).click()

  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(task.name)
  await typeInto(page, field, '')
  // Nothing on screen reflects typed text before the press reads it, so Flutter
  // is given two frames to take the emptied text up: the first runs of this
  // test, on a loaded machine, met a press that still saw the old name (3 of
  // ~50, none in ~450 since — the cause was not pinned down).
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))))

  // The app sends it: nothing on the screen stops an empty name, the backend
  // does (a 400), and the optimistic empty title rolls back like any refusal.
  const write = holdWrite(page)
  const refused = page.waitForResponse((r) => r.request().method() === 'PUT' && r.url().endsWith('/name'))
  await page.getByRole('button', { name: 'Rename', exact: true }).click()
  await write.release()
  expect((await refused).status()).toBe(400)

  await expect(page.getByText('Field "name" is missing or empty')).toBeVisible()
  await expect(heroTitle(page)).toContainText(task.name)
  await field.click()
  await expect(field).toHaveValue(task.name)
  expect((await getTask(request, task.id))?.name).toBe(task.name)
})

test('the list shows its skeleton until the backend answers', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('After the skeleton'))
  // Held at the network layer: the list is provably still owed while the
  // screen is looked at, however long the browser takes to paint it.
  const list = holdRequests(page, 'GET', '**/api/tasks?*')
  await open(page)

  // The skeleton has no semantics of its own; it is the screen with the
  // toolbar and none of the alternatives — no rows, no header count, no empty
  // state, no error panel — while the reload button is out of the tree
  // because the list is fetching.
  await expect(page.getByRole('button', { name: 'Reload', exact: true })).toHaveCount(0)
  await expect(row(page, task.name)).toHaveCount(0)
  await expect(page.getByRole('button', { name: /^Delete / })).toHaveCount(0)
  await expect(page.getByText(/\d+ of \d+ synced/)).toHaveCount(0)
  await expect(page.getByText('No tasks found.')).toHaveCount(0)
  await expect(page.getByText('Try again')).toHaveCount(0)

  await list.release()
  await expect(row(page, task.name)).toBeVisible()
  await expect(page.getByText(/\d+ of \d+ synced/)).toBeVisible()
})

test("the facts card shows the backend's progress, estimate, project and board state", async ({ page, request }) => {
  // A seeded task, because its progress and estimate are not the ones a new
  // task starts with — the expectation is read from the backend, not typed
  // in, so it follows the seed.
  const seeded = (await listTasks(request)).find((t) => t.name === 'Write the release notes')!
  expect(seeded.priority).toBe('high')
  expect(seeded.progress).toBeGreaterThan(0)
  await open(page)
  // A row's texts are one accessible name, one line per text.
  await expect
    .poll(async () => (await row(page, seeded.name).getAttribute('aria-label'))?.replace(/\s+/g, ' '))
    .toBe(`${seeded.name} High · ${seeded.project} · ${seeded.progress} %`)

  await row(page, seeded.name).click()
  await expect(page.getByText(new RegExp(`High · ${seeded.project}$`))).toBeVisible()
  // The card's rows are one node in the semantics tree, label and value in
  // reading order, so it is read as one line.
  await expect(
    page.getByText(
      `Progress ${seeded.progress} % Estimate ${seeded.estimate.toFixed(2)} h Project ${seeded.project} Board ${seeded.synced ? 'Synced' : 'Not synced'}`,
    ),
  ).toBeVisible()
})

test('the reminder switch flips at once, waits for the scheduler, then settles', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Nudge'))
  await open(page)
  await row(page, task.name).click()
  const requests = requestCounter(page)

  const reminder = page.getByRole('switch')
  await expect(reminder).toHaveAttribute('aria-checked', 'false')
  const write = holdRequests(page, 'PUT', '**/api/tasks/*/reminder')
  await reminder.click()
  // Optimistic: the requested value shows before the write is accepted.
  await expect(reminder).toHaveAttribute('aria-checked', 'true')
  await write.release()

  // Accepted, not confirmed: the backend answers with `pending`, the switch
  // is locked for the confirmation window, and the app polls the task.
  await expect(waitingForScheduler(page)).toBeVisible()
  await expect(waitingForScheduler(page)).not.toHaveAttribute('flt-tappable')
  await expect.poll(() => requests.details(), { timeout: 3000 }).toBeGreaterThan(0)

  // The device confirms after ~3 s: the poll stops, the switch unlocks, and
  // the value it shows is the one the backend now holds.
  await expect(page.getByRole('switch', { name: /Confirmed by the scheduler/ })).toBeVisible({ timeout: 10_000 })
  await expect(reminder).toHaveAttribute('aria-checked', 'true')
  await expect(reminder).not.toHaveAttribute('aria-disabled', 'true')
  const polls = requests.details()
  await page.waitForTimeout(1500)
  expect(requests.details()).toBe(polls)
  const confirmed = await getTask(request, task.id)
  expect(confirmed?.reminder).toBe(true)
  expect(confirmed?.reminderPending).toBe(false)

  // The overview row shows the confirmed state from the same cache entry.
  // Flutter folds a row's texts into the group's accessible name rather than
  // leaving them as text nodes, so the pill is asserted there — the group's
  // own innerText is just the delete button's tooltip.
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, task.name)).toHaveAttribute('aria-label', /reminder$/)
})

test('a refused delete springs back with a notice; the retry goes through', async ({ page, request }) => {
  // The backend refuses every second delete, counting across the whole run.
  // Whatever the count stands at, deleting `first` until it is gone ends on
  // a success — so `second`'s first attempt is the refused one, on purpose.
  const first = await createTask(request, uniqueName('First'))
  const second = await createTask(request, uniqueName('Second'))
  await open(page)
  await expect(row(page, second.name)).toBeVisible()

  for (let attempt = 0; attempt < 2 && (await getTask(request, first.id)); attempt++) {
    const held = holdRequests(page, 'DELETE', '**/api/tasks/*')
    await deleteButton(page, first.name).click()
    await expect(row(page, first.name)).toBeHidden()
    await held.release()
    await expect
      .poll(async () => (await getTask(request, first.id)) === null || (await row(page, first.name).isVisible()), {
        timeout: 5000,
      })
      .toBe(true)
  }
  expect(await getTask(request, first.id)).toBeNull()

  const held = holdRequests(page, 'DELETE', '**/api/tasks/*')
  await deleteButton(page, second.name).click()
  // Optimistically gone …
  await expect(row(page, second.name)).toBeHidden()
  await held.release()
  // … and back, with the backend's own words.
  await expect(page.getByText('The server refused the delete — try again')).toBeVisible()
  await expect(row(page, second.name)).toBeVisible()
  expect(await getTask(request, second.id)).not.toBeNull()

  await deleteButton(page, second.name).click()
  await expect(row(page, second.name)).toBeHidden()
  await expect.poll(() => getTask(request, second.id)).toBeNull()
  await page.reload()
  await expect(row(page, second.name)).toBeHidden()
})

test('searching narrows the list through the backend, once per pause in typing', async ({ page, request }) => {
  const needle = uniqueName('Needle')
  const task = await createTask(request, needle)
  await open(page)
  await expect(row(page, task.name)).toBeVisible()
  const requests = requestCounter(page)

  const searched = page.waitForRequest((r) => new URL(r.url()).searchParams.get('search') === needle)
  const search = page.getByRole('textbox', { name: 'Search tasks…' })
  await typeInto(page, search, needle)
  await searched
  await expect(row(page, task.name)).toBeVisible()
  await expect(page.getByRole('button', { name: /^Delete / })).toHaveCount(1)
  // Debounced: one request for the whole word, not one per keystroke.
  expect(requests.lists()).toBe(1)
})

test('an unreachable backend shows the error panel after one retry, and recovers', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Back again'))
  let attempts = 0
  await page.route('**/api/tasks?*', (route) => {
    attempts++
    return route.abort('connectionrefused')
  })

  await open(page)
  // The panel's texts merge into its group's accessible name.
  await expect(page.getByRole('group', { name: /Is the backend running on port 5174\?/ })).toBeVisible({ timeout: 15_000 })
  await expect(page.getByText('Server offline')).toBeVisible()
  // `retry: 1` in the demo's client defaults: the first attempt and one
  // retry, not upstream's three.
  expect(attempts).toBe(2)

  await page.unroute('**/api/tasks?*')
  await page.getByRole('button', { name: 'Try again', exact: true }).click()
  await expect(row(page, task.name)).toBeVisible()
  await expect(page.getByText(/\d+ of \d+ synced/)).toBeVisible()
})

test('shared data stays consistent through rename, rollback and network recovery', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Confidence'))
  const renamed = uniqueName('Confirmed')
  const requests = requestCounter(page)
  await open(page)
  await expect(row(page, task.name)).toBeVisible()
  await row(page, task.name).click()
  await expect(heroTitle(page)).toContainText(task.name)
  expect(requests.lists()).toBe(1)
  expect(requests.details()).toBe(0)

  const field = page.getByRole('textbox', { name: /^Name/ })
  await field.click()
  await expect(field).toHaveValue(task.name)
  await typeInto(page, field, renamed)
  const successfulWrite = holdWrite(page)
  await page.getByRole('button', { name: 'Rename', exact: true }).click()
  await expect(heroTitle(page)).toContainText(renamed)
  // The actual backend still has the old value while the UI is optimistic.
  expect((await getTask(request, task.id))?.name).toBe(task.name)
  await successfulWrite.release()
  await expect(page.getByRole('button', { name: 'Rename', exact: true })).not.toHaveAttribute('aria-disabled', 'true')
  expect((await getTask(request, task.id))?.name).toBe(renamed)

  // After the button click the field still holds the confirmed name; a
  // click alone can leave Flutter's input connection inactive, which
  // `typeInto` repairs before it types.
  await field.click()
  await expect(field).toHaveValue(renamed)
  await typeInto(page, field, 'fail')
  const rejectedWrite = holdWrite(page)
  const rejectedRequest = page.waitForRequest((r) =>
    r.method() === 'PUT' && new URL(r.url()).pathname.endsWith('/name'))
  await page.getByRole('button', { name: 'Rename', exact: true }).click()
  expect((await rejectedRequest).postDataJSON()).toEqual({ name: 'fail' })
  await expect(heroTitle(page)).toContainText('fail')
  await rejectedWrite.release()
  await expect(page.getByText('The server refused the write')).toBeVisible()
  await expect(heroTitle(page)).toContainText(renamed)
  await field.click()
  await expect(field).toHaveValue(renamed)
  expect((await getTask(request, task.id))?.name).toBe(renamed)
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, renamed)).toBeVisible()

  let attempts = 0
  await page.route('**/api/tasks?*', (route) => {
    attempts++
    return route.abort('connectionrefused')
  })
  await page.reload()
  await expect(page.getByRole('group', { name: /Is the backend running on port 5174\?/ })).toBeVisible()
  expect(attempts).toBe(2)
  await page.unroute('**/api/tasks?*')
  await page.getByRole('button', { name: 'Try again', exact: true }).click()
  await expect(row(page, renamed)).toBeVisible()
  expect((await getTask(request, task.id))?.name).toBe(renamed)
})
