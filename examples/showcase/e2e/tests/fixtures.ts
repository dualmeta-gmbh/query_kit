// What every spec shares: a backend scenario of the test's own, a way to open
// a feature inside it, and the two selectors the debug strip is built for.
import { expect, test as base, type APIRequestContext, type Locator, type Page } from '@playwright/test'

/// A button by its label, inside `scope`: the page, or a group.
///
/// Flutter 3.47's web engine names a button twice once it has been tapped
/// ("Refetch Refetch": the label's text node is attached to the button as an
/// owned child), so that name is accepted too. A button whose label merely
/// starts with `name` is not: "Refetch all" is not "Refetch".
export const button = (scope: Page | Locator, name: string) => {
  const label = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return scope.getByRole('button', { name: new RegExp(`^${label}(?: ${label})?$`) })
}

export const BACKEND = 'http://localhost:5175/api'

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

  async clearRequests() {
    await this.request.delete(this.url('requests'))
  }

  /// How many answered requests match `method` and `path` (a RegExp on the
  /// full path, `/api/posts/1`).
  async count(method: string, path: RegExp) {
    const log = await this.requests()
    return log.filter((entry) => entry.method === method && path.test(entry.path)).length
  }

  /// A direct call into this scenario, for setup and for checking what the
  /// backend really holds.
  async api(method: 'get' | 'post' | 'patch' | 'delete', path: string, data?: unknown) {
    return this.request[method](`${BACKEND}${path}`, { headers: { 'x-scenario': this.id }, data })
  }
}

declare global {
  interface Window {
    __inputListeners?: (element: Element | null) => number
  }
}

export const test = base.extend<{ scenario: Scenario; open: (route: string) => Promise<void> }>({
  // Every page counts the `input` listeners added to each element, before
  // the app's own code runs and without changing what it does: `typeInto`
  // types only once Flutter listens to the focused field.
  page: async ({ page }, use) => {
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
    await use(async (route: string) => {
      // The scenario rides in the query string, before the hash, so it
      // survives every in-app navigation.
      await page.goto(`/?scenario=${scenario.id}#${route}`)
      await expect(page.getByText(`scenario ${scenario.id}`, { exact: true })).toBeVisible()
    })
  },
})

export { expect }
export type { Page }

/// Clicks a Flutter text field and types `text` into it. A click can leave
/// Flutter's input connection inactive, and a `fill` then lands in an
/// element nobody listens to: the DOM holds the text, so `toHaveValue`
/// passes, and the app never sees it. So the field is focused — and, when
/// two seconds bring no listener, the focus walked away and back, which
/// waiting alone cannot repair — until the focused element has the `input`
/// listener Flutter reads it through, as the `page` fixture counts them in
/// every browser. Firefox and WebKit on Linux met exactly that under load.
/// The task manager's suite does the same.
export async function typeInto(page: Page, field: Locator, text: string) {
  const listenersOnFocus = () =>
    page.evaluate(() => {
      let element = document.activeElement
      while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement
      return window.__inputListeners?.(element) ?? -1
    })
  // Flutter attaches its listener a round trip through the framework after
  // the focus, later still under load: walking away before then would break
  // the connection on its way up.
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

/// The semantics group named `name`.
///
/// One name addresses a group in both test layers: the screen publishes it
/// once through `SemanticsGroup` (`lib/shared/fact_group.dart`), which is the
/// semantics label read here and the widget key `groupNamed` reads in
/// `test/harness.dart` (C56, #51). Every group locator in this suite goes
/// through this function, so `getByRole('group', …)` is written once.
export const group = (page: Page, name: string) => page.getByRole('group', { name, exact: true })

/// A `SegmentedButton` segment, by its label, inside `scope`: a knob's group,
/// or the page where only one segment carries that label.
///
/// Flutter 3.38 publishes a segment as a `radio` whose selection is
/// `aria-checked`; Flutter 3.47 publishes it as a `button` whose selection is
/// `aria-current`. Either is found, so the suite reads the same screen under
/// both, and a segment is never located with a role of its own elsewhere.
export const segment = (scope: Page | Locator, name: string) =>
  scope.getByRole('radio', { name, exact: true }).or(button(scope, name))

/// Waits until `seg` is the selected segment, under either way of saying so.
/// A click is a DOM event and Flutter applies it a frame later, so a test
/// that acts on a knob right after clicking it reads the selection first.
export async function expectSelected(seg: Locator) {
  await expect
    .poll(() => seg.evaluate((element) => element.getAttribute('aria-checked') ?? element.getAttribute('aria-current')))
    .toBe('true')
}

/// One fact inside that group, by its exact leaf text: `status=success`,
/// `fetchStatus=idle`, `fetches=2`.
export const factIn = (page: Page, name: string, text: string) => group(page, name).getByText(text, { exact: true })

/// The number a fact carries: `factNumber(page, 'reader mixin', 'builds')`
/// reads `3` off the exact text `builds=3` inside that group.
///
/// The reading half of the same convention `factIn` serves, for the case a
/// spec cannot spell as an exact text — a *delta*, where what is asserted is
/// the number before plus what the action should have moved. Three specs wrote
/// this out themselves and each one differently (#69).
///
/// `factIn` is still the right tool wherever the expected text is known: it
/// retries into the frame, while a number read once races it. The pattern is
/// anchored, so `data builds=1` is never read as `builds=1`.
export async function factNumber(page: Page, name: string, key: string): Promise<number> {
  const text = await group(page, name)
    .getByText(new RegExp(`^${key}=\\d+$`))
    .textContent()
  return Number(text!.slice(key.length + 1))
}

/// The debug strip labelled `label`: the group named `debug <label>`, the one
/// group that is about the cache rather than about the screen.
export const strip = (page: Page, label: string) => group(page, `debug ${label}`)

export const fact = (page: Page, label: string, text: string) => factIn(page, `debug ${label}`, text)

/// A SnackBar's text, or any other live region's. Flutter web renders a
/// `liveRegion` twice: as its node in the semantics tree, and — for a few
/// hundred milliseconds after it appears — as a copy in the
/// `<flt-announcement-host>` that screen readers are told about, which sits
/// outside the tree. A bare `page.getByText(text)` then resolves to both and
/// strict mode refuses the locator, or to one, depending on when it runs
/// (ninth review, C44). Scoped to the semantics host, so only the tree's copy
/// is ever matched.
export const snackBar = (page: Page, text: string) => page.locator('flt-semantics-host').getByText(text, { exact: true })

/// Holds every request matching `glob` — a glob, a RegExp or a predicate on
/// the URL, as `page.route` takes — in the browser until `release()`, so
/// an assertion between the action and the release runs while the backend
/// provably has not answered. After the release the handler is a passthrough;
/// unrouting it would race the handler that is still letting the held request
/// go. A request the page aborted while it was held has nothing left to let
/// go, so its `continue` is allowed to fail.
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
    /// How many requests the hold has caught so far.
    get seen() {
      return seen
    },
    async release() {
      await routed
      letGo()
    },
  }
}
