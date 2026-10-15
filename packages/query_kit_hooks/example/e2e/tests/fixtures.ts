// What every spec shares: a backend scenario of the test's own, the app
// opened inside it, and the selectors the app's semantics groups are built
// for. Shaped after the showcase's fixtures (examples/showcase/e2e), whose
// backend this suite runs against.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { expect, test as base, type APIRequestContext, type Locator, type Page } from '@playwright/test'

export const BACKEND = 'http://localhost:5178/api'

export type LogEntry = {
  method: string
  path: string
  query: Record<string, string>
  at: string
  status: number
}

export type FailNext = { method: string; path: string; count: number; status: number; message?: string }

export type ScenarioConfig = { latency?: number; errorRate?: number; failNext?: FailNext[] }

export class Scenario {
  constructor(
    readonly id: string,
    private readonly request: APIRequestContext,
  ) {}

  private url(tail: string) {
    return `${BACKEND}/__scenario/${this.id}/${tail}`
  }

  async reset() {
    await this.request.post(this.url('reset'))
  }

  async config(config: ScenarioConfig) {
    const response = await this.request.post(this.url('config'), { data: config })
    expect(response.ok(), await response.text()).toBe(true)
  }

  async requests(): Promise<LogEntry[]> {
    return (await this.request.get(this.url('requests'))).json()
  }

  /// How many answered requests match `method` and `path` (a RegExp on the
  /// full path, `/api/posts/1`).
  async count(method: string, path: RegExp) {
    const log = await this.requests()
    return log.filter((entry) => entry.method === method && path.test(entry.path)).length
  }

  /// A direct call into this scenario, for checking what the backend holds.
  async api(method: 'get' | 'post' | 'patch' | 'delete', path: string, data?: unknown) {
    return this.request[method](`${BACKEND}${path}`, { headers: { 'x-scenario': this.id }, data })
  }
}

declare global {
  interface Window {
    __inputListeners?: (element: Element | null) => number
  }
}

/// The one font the app does not ship. Without a Roboto of its own, the web
/// engine fetches its regular weight from fonts.gstatic.com before the first
/// frame, and a suite would boot only as fast as that answers. The archive
/// ships no fonts (an example is not where a package's users want 500 kB
/// of them), so the suite answers that request from the showcase's copy,
/// which the repository holds anyway. Any other font request is refused:
/// the app draws nothing Roboto cannot.
const roboto = readFileSync(
  fileURLToPath(new URL('../../../../../examples/showcase/fonts/Roboto-Regular.ttf', import.meta.url)),
)

export const test = base.extend<{ scenario: Scenario; open: () => Promise<void> }>({
  page: async ({ page }, use) => {
    await page.route('https://fonts.gstatic.com/**', (route) =>
      /\/roboto\//.test(route.request().url())
        ? route.fulfill({ body: roboto, contentType: 'font/ttf' })
        : route.abort(),
    )
    // Every page counts the `input` listeners added to each element, before
    // the app's own code runs: `typeInto` types only once Flutter listens to
    // the focused field.
    await page.addInitScript(() => {
      const counts = new WeakMap<EventTarget, number>()
      const add = EventTarget.prototype.addEventListener
      const remove = EventTarget.prototype.removeEventListener
      EventTarget.prototype.addEventListener = function (type, listener, options) {
        if (type === 'input') counts.set(this, (counts.get(this) ?? 0) + 1)
        return add.call(this, type, listener, options)
      }
      EventTarget.prototype.removeEventListener = function (type, listener, options) {
        if (type === 'input') counts.set(this, Math.max(0, (counts.get(this) ?? 0) - 1))
        return remove.call(this, type, listener, options)
      }
      window.__inputListeners = (element) => (element ? (counts.get(element) ?? 0) : 0)
    })
    await use(page)
  },
  scenario: async ({ request }, use, testInfo) => {
    // Unique per test and per run, so a re-run never meets an old world.
    const scenario = new Scenario(`${testInfo.testId}-${Date.now().toString(36)}`, request)
    await scenario.reset()
    await use(scenario)
  },
  open: async ({ page, scenario }, use) => {
    await use(async () => {
      // The scenario rides in the query string; the app reads it once.
      await page.goto(`/?scenario=${scenario.id}`)
      await expect(factIn(page, 'activity', `scenario ${scenario.id}`)).toBeVisible()
    })
  },
})

export { expect }
export type { Page }

/// The semantics group named `name`: the app's `Group` widget
/// (`lib/src/group.dart`), whose label is this name.
export const group = (page: Page, name: string) => page.getByRole('group', { name, exact: true })

/// One text inside that group, exactly.
export const factIn = (page: Page, name: string, text: string) => group(page, name).getByText(text, { exact: true })

/// A todo's checkbox, by its text.
export const todo = (page: Page, text: string) => group(page, 'todos').getByRole('checkbox', { name: text, exact: true })

/// Clicks a Flutter text field and types `text` into it, once Flutter
/// listens to the focused element: the showcase's `typeInto`, which says why.
export async function typeInto(page: Page, field: Locator, text: string) {
  const listenersOnFocus = () =>
    page.evaluate(() => {
      let element = document.activeElement
      while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement
      return window.__inputListeners?.(element) ?? -1
    })
  const heard = () =>
    expect
      .poll(listenersOnFocus, { timeout: 2000 })
      .toBeGreaterThan(0)
      .then(
        () => true,
        () => false,
      )
  await expect(async () => {
    await field.click({ timeout: 1000 })
    await expect(field).toBeFocused({ timeout: 1000 })
    if (await heard()) return
    await field.press('Tab', { timeout: 1000 })
    await page.keyboard.press('Shift+Tab')
    await expect(field).toBeFocused({ timeout: 1000 })
    if (await heard()) return
    throw new Error('Flutter does not listen to the focused field')
  }).toPass({ timeout: 20_000, intervals: [100, 250, 500] })
  await field.fill(text)
  await expect(field).toHaveValue(text)
}

/// Holds every request matching `glob` in the browser until `release()`, so
/// an assertion between the action and the release runs while the backend
/// provably has not answered: the showcase's `holdRequest`, which says why
/// the handler stays a passthrough after the release.
export function holdRequest(page: Page, glob: Parameters<Page['route']>[0]) {
  let letGo: () => void = () => {}
  const held = new Promise<void>((resolve) => {
    letGo = resolve
  })
  let seen = 0
  const routed = page.route(glob, async (route) => {
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
