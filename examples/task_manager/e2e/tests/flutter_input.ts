// Typing into a Flutter web text field, in every browser.
//
// Flutter reads a field's text from an `input` listener it adds to the DOM
// element it is editing. A click can leave that connection inactive, and a
// `fill` then lands in an element nobody listens to: the DOM holds the text,
// so `toHaveValue` passes, and the app never sees it. Chromium's DevTools can
// list an element's listeners; Firefox and WebKit have no such session, and
// under load on Linux they met exactly that. So every page counts the `input`
// listeners added to each element — an init script, before the app's own
// code, that changes nothing the app does — and a field is typed into only
// once the element in focus has one.
import { expect, type Locator, type Page } from '@playwright/test'

declare global {
  interface Window {
    __inputListeners?: (element: Element | null) => number
  }
}

/// Counts `input` listeners per element on every page of `page`'s context
/// from the next navigation on.
export async function trackInputListeners(page: Page) {
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
}

/// How many `input` listeners the focused element has, through shadow roots.
const listenersOnFocus = (page: Page) =>
  page.evaluate(() => {
    let element = document.activeElement
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement
    return window.__inputListeners?.(element) ?? -1
  })

/// Focuses `field` until Flutter listens to it, then replaces its text with
/// `text`. Needs `trackInputListeners` on the page before it was opened.
///
/// Waiting alone cannot repair a focus Flutter did not take up, so a try it
/// has not taken up within two seconds walks the focus away and back.
export async function typeInto(page: Page, field: Locator, text: string) {
  // Flutter attaches its listener a round trip through the framework after
  // the focus, later still under load: walking away before then would break
  // the connection on its way up.
  const heard = () =>
    expect
      .poll(() => listenersOnFocus(page), { timeout: 2000 })
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
