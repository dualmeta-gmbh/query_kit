// The reminder, beyond the happy path `tasks.spec.ts` walks: turning it off,
// a write the scheduler refuses, the window in which the row says it is
// confirming, and a task the backend has not synced.
//
// The scheduler takes a value ~3 s after it accepted the write (CONFIRM_AFTER
// in the backend's config). Where a test needs to stand in that window it
// holds the app's polls instead of racing the clock.
import { expect, test } from '@playwright/test'
import { confirmReminder, createTask, getTask, sweepTestTasks, uniqueName } from './backend'
import { holdRequests, open, refuseRequests, row, waitingForScheduler } from './helpers'

test.beforeAll(async ({ request }) => sweepTestTasks(request))
test.afterAll(async ({ request }) => sweepTestTasks(request))
test.use({ viewport: { width: 1280, height: 1600 } })

test('turning a reminder off again waits for the scheduler and settles off', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Nudge off'))
  await confirmReminder(request, task.id, true)
  await open(page)
  await expect(row(page, task.name)).toHaveAttribute('aria-label', /reminder$/)
  await row(page, task.name).click()

  const reminder = page.getByRole('switch')
  await expect(reminder).toHaveAttribute('aria-checked', 'true')
  const write = holdRequests(page, 'PUT', '**/api/tasks/*/reminder')
  await reminder.click()
  // Optimistic: the requested value shows before the write is accepted.
  await expect(reminder).toHaveAttribute('aria-checked', 'false')
  await write.release()

  await expect(waitingForScheduler(page)).toBeVisible()
  await expect(page.getByRole('switch', { name: /Confirmed by the scheduler/ })).toBeVisible({ timeout: 10_000 })
  await expect(reminder).toHaveAttribute('aria-checked', 'false')
  await expect(reminder).not.toHaveAttribute('aria-disabled', 'true')
  const settled = await getTask(request, task.id)
  expect(settled?.reminder).toBe(false)
  expect(settled?.reminderPending).toBe(false)

  // The row has lost its pill, from the same cache entry.
  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, task.name)).not.toHaveAttribute('aria-label', /(reminder|confirming)$/)
})

test('a refused reminder write rolls the switch back', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Nudge refused'))
  await open(page)
  await row(page, task.name).click()

  const reminder = page.getByRole('switch')
  await expect(reminder).toHaveAttribute('aria-checked', 'false')
  // The backend is never asked: the refusal is the browser's, held until the
  // optimistic value has been seen.
  const write = refuseRequests(page, 'PUT', '**/api/tasks/*/reminder', 'The scheduler refused the reminder')
  await reminder.click()
  await expect(reminder).toHaveAttribute('aria-checked', 'true')
  await write.release()

  // Back off, and unlocked: nothing is outstanding. (The screen has no notice
  // for a refused reminder, unlike the rename's.)
  await expect(reminder).toHaveAttribute('aria-checked', 'false')
  await expect(reminder).not.toHaveAttribute('aria-disabled', 'true')
  await expect(page.getByRole('switch', { name: /Confirmed by the scheduler/ })).toBeVisible()
  const held = await getTask(request, task.id)
  expect(held?.reminder).toBe(false)
  expect(held?.reminderPending).toBe(false)
  expect(held?.reminderTarget).toBeNull()

  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, task.name)).not.toHaveAttribute('aria-label', /(reminder|confirming)$/)
})

test('the row shows "confirming" while the scheduler has not taken the value', async ({ page, request }) => {
  const task = await createTask(request, uniqueName('Nudge window'))
  await open(page)
  await row(page, task.name).click()

  // The write goes through, but the polls that would learn of the scheduler's
  // answer are held: the app stays in the window between "accepted" and
  // "confirmed" for as long as the test stands in it.
  const polls = holdRequests(page, 'GET', '**/api/tasks/*')
  const reminder = page.getByRole('switch')
  await reminder.click()
  await expect(waitingForScheduler(page)).toBeVisible()
  await expect(page.getByText(/confirming$/)).toBeVisible()

  await page.getByRole('button', { name: 'Back', exact: true }).click()
  await expect(row(page, task.name)).toHaveAttribute('aria-label', /confirming$/)

  // Let the polls through: the scheduler confirms and the pill turns into the
  // reminder's.
  await polls.release()
  await expect(row(page, task.name)).toHaveAttribute('aria-label', /reminder$/, { timeout: 10_000 })
  expect((await getTask(request, task.id))?.reminder).toBe(true)
})

test('a task the backend has not synced shows "not synced"', async ({ page }) => {
  // `synced` is the backend's own: no write sets it, so the seed's one
  // unsynced task is the only way to meet it.
  await open(page)
  const unsynced = row(page, /^Archive last quarter/)
  await expect(unsynced).toHaveAttribute('aria-label', /not synced$/)

  await unsynced.click()
  await expect(page.getByText(/not synced$/)).toBeVisible()
  await expect(page.getByText(/Board\s+Not synced$/)).toBeVisible()
})
