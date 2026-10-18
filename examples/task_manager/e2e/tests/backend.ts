// Talks to the express backend directly — to set a test up (a task of its
// own, so tests do not depend on the seed data or on each other) and to check
// afterwards what the backend really holds.
import { expect, type APIRequestContext, type Page, type Request } from '@playwright/test'

export const BACKEND = 'http://localhost:5174/api'

export type Task = {
  id: string
  name: string
  project: string
  priority: string
  progress: number
  estimate: number
  synced: boolean
  reminder: boolean
  reminderPending: boolean
  reminderTarget: boolean | null
}

let counter = 0

/// A name no other test and no earlier run can have produced.
// The counter is per worker, and workers — three browsers running one test
// at once, say — can share a millisecond: a random part keeps them apart.
export const uniqueName = (prefix: string) =>
  `${prefix} ${Date.now().toString(36)}${(counter++).toString(36)}${Math.random().toString(36).slice(2, 6)}`

export async function createTask(
  request: APIRequestContext,
  name: string,
  fields: { project?: string; priority?: 'low' | 'normal' | 'high' } = {},
): Promise<Task> {
  const response = await request.post(`${BACKEND}/tasks`, { data: { name, project: 'Inbox', ...fields } })
  if (!response.ok()) throw new Error(`create failed: ${response.status()}`)
  return (await response.json()) as Task
}

/// Asks the scheduler for `value` and waits until the backend has taken it,
/// which it does a few seconds later. A task whose reminder is already on is
/// a setup a test cannot get through the app without a second confirmation.
export async function confirmReminder(request: APIRequestContext, id: string, value: boolean) {
  const response = await request.put(`${BACKEND}/tasks/${id}/reminder`, { data: { value } })
  if (!response.ok()) throw new Error(`reminder failed: ${response.status()}`)
  await expect
    .poll(async () => (await getTask(request, id))?.reminderPending, { timeout: 10_000 })
    .toBe(false)
}

/// Every task the backend holds, in its order.
export async function listTasks(request: APIRequestContext): Promise<Task[]> {
  const response = await request.get(`${BACKEND}/tasks`)
  return ((await response.json()) as { tasks: Task[] }).tasks
}

export async function getTask(request: APIRequestContext, id: string): Promise<Task | null> {
  const response = await request.get(`${BACKEND}/tasks/${id}`)
  return response.ok() ? ((await response.json()) as Task) : null
}

/// Counts the backend requests the app makes, so a test can say "one list
/// fetch, no per-task fetch" — the cache policy, observed at the wire.
export function requestCounter(page: Page) {
  const seen: Request[] = []
  page.on('request', (request) => {
    if (request.url().startsWith(BACKEND)) seen.push(request)
  })
  const count = (method: string, path: RegExp) =>
    seen.filter((request) => request.method() === method && path.test(new URL(request.url()).pathname)).length
  return {
    lists: () => count('GET', /^\/api\/tasks$/),
    details: () => count('GET', /^\/api\/tasks\/[^/]+$/),
    creates: () => count('POST', /^\/api\/tasks$/),
    /// The `search` and `project` of every list fetch so far, in order.
    listQueries: () =>
      seen
        .filter((request) => request.method() === 'GET' && new URL(request.url()).pathname === '/api/tasks')
        .map((request) => {
          const { searchParams } = new URL(request.url())
          return { search: searchParams.get('search'), project: searchParams.get('project') }
        }),
    reset: () => seen.splice(0, seen.length),
  }
}

/// What the app's "New task" button names a task: the same for every press,
/// so it carries no `uniqueName` suffix and the sweep knows it by name.
export const NEW_TASK_NAME = 'New task'

/// Deletes every task a test created — the names carry the `uniqueName`
/// suffix, which is a base-36 timestamp and more: ten characters at least. A
/// shorter word is not one of ours, and the seed's "Archive last quarter"
/// ends in seven. The tasks the "New task" button makes are swept by their
/// fixed name. The backend refuses every second delete, so each is tried
/// twice.
export async function sweepTestTasks(request: APIRequestContext) {
  const tasks = await listTasks(request)
  for (const task of tasks.filter((s) => s.name === NEW_TASK_NAME || / [0-9a-z]{10,}$/.test(s.name))) {
    for (let attempt = 0; attempt < 2 && (await getTask(request, task.id)); attempt++) {
      await request.delete(`${BACKEND}/tasks/${task.id}`)
    }
  }
}
