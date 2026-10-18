// What the specs share: the boot marker, the locators for what a row and a
// button are called in the semantics tree, and the request holds that stand in
// for a stopwatch.
import { expect, type Page } from '@playwright/test'

export const open = async (page: Page) => {
  await page.goto('/')
  // The toolbar is up as soon as the app has booted; the rows come after the
  // backend's ~900 ms.
  await expect(page.getByRole('button', { name: 'New task', exact: true })).toBeVisible()
}

export const row = (page: Page, name: string | RegExp) => page.getByRole('group', { name })
export const deleteButton = (page: Page, name: string) => page.getByRole('button', { name: `Delete ${name}` })
export const newTaskButton = (page: Page) => page.getByRole('button', { name: 'New task', exact: true })
export const searchField = (page: Page) => page.getByRole('textbox', { name: 'Search tasks…' })
// A control by the name it carries, whatever role Flutter publishes it with.
// A locked control that contains a spinner (the reload button while fetching,
// "New task" while creating, the reminder switch while it waits) is a
// `button` or `switch` with `aria-disabled` on Flutter 3.38 and a node of
// another role on 3.41, so a role locator finds it in one version only. The
// name is the text or the label in both. What both versions agree on is
// `flt-tappable`, which a node has exactly while a press on it does something:
// assert a lock as its absence, and always beside the attribute's presence on
// the same node when it is unlocked, or the absence proves nothing.
export const control = (page: Page, name: string) =>
  page.locator(`flt-semantics:text-is("${name}"), flt-semantics[aria-label="${name}"]`)
export const reminderControl = (page: Page) => page.locator('flt-semantics[aria-label^="Reminder"]')
export const waitingForScheduler = (page: Page) =>
  page.locator('flt-semantics[aria-label^="Reminder"][aria-label*="Waiting for the scheduler"]')
export const heroTitle = (page: Page) => page.getByText(/Normal · Inbox/)

// Holds every rename write in the browser until `release()`, so an assertion
// between the click and the release runs while the backend provably has not
// answered. After the release the handler is a passthrough, so the rest of the
// test talks to the backend normally — unrouting it here would race the
// handler that is still letting the held request go.
export function holdWrite(page: Page) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  const routed = page.route('**/api/tasks/*/name', async (route) => {
    await held
    await route.continue()
  })
  return {
    async release() {
      await routed
      letGo()
    },
  }
}

// The same for any other request: `method` requests to `glob` are held, so
// "optimistic" is asserted while the backend provably owes its answer, not
// within a guessed number of milliseconds a busy browser may not keep. Other
// requests to the same paths pass — `page.route` cannot filter by method, so
// the handler falls back for the rest, a CORS preflight included.
export function holdRequests(page: Page, method: string, glob: string) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  const routed = page.route(glob, async (route) => {
    if (route.request().method() !== method) return route.fallback()
    await held
    await route.continue()
  })
  return {
    async release() {
      await routed
      letGo()
    },
  }
}

// A write the backend "refuses" without the backend being asked: held until
// `release()` like `holdRequests`, then answered 500 in the browser. The
// backend keeps no trace of it — what a test asserts afterwards is the app's
// rollback against a backend that never changed. The answer carries the CORS
// header a page on another origin needs to read it.
export function refuseRequests(page: Page, method: string, glob: string, message: string) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  const routed = page.route(glob, async (route) => {
    if (route.request().method() !== method) return route.fallback()
    await held
    await route.fulfill({
      status: 500,
      headers: { 'access-control-allow-origin': '*' },
      json: { message },
    })
  })
  return {
    async release() {
      await routed
      letGo()
    },
  }
}

/// Opens the project dropdown, which is named after the project it shows, and
/// picks another. The menu is a popup of menu items.
export async function pickProject(page: Page, from: string, to: string) {
  await page.getByRole('button', { name: from, exact: true }).click()
  await page.getByRole('menuitem', { name: to, exact: true }).click()
  await expect(page.getByRole('button', { name: to, exact: true })).toBeVisible()
}

/// The list is settled: not fetching, which is when the toolbar's reload
/// button can be pressed again. A test that says "no request" asserts it after
/// this, so a fetch the last change started would have locked the button.
export async function listSettled(page: Page) {
  await expect(control(page, 'Reload')).toHaveAttribute('flt-tappable', { timeout: 10_000 })
}
