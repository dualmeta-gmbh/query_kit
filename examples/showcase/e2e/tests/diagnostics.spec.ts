import type { Page } from '@playwright/test'
import { expect, fact, factIn, group, test } from './fixtures'

// One fact of a card, by its group and exact text — `status=error` is said by
// the mutation's facts and by the strip alike.
const factOf = (page: Page, label: string, text: string) => factIn(page, `facts ${label}`, text)

const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })

const INCREMENT = /^\/api\/counter\/increment$/

test('a read as the entry\'s type answers, a read as another type throws QueryDataTypeError', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
  await expect(factOf(page, 'typed', 'read=none')).toBeVisible()

  await button(page, 'Read as int').click()
  await expect(factOf(page, 'typed', 'read=int 0')).toBeVisible()

  await button(page, 'Read as String').click()
  await expect(factOf(page, 'typed', 'read=QueryDataTypeError')).toBeVisible()
  await expect(factOf(page, 'typed', 'expected=String')).toBeVisible()
  await expect(factOf(page, 'typed', 'actual=int')).toBeVisible()
})

test('a write of another type throws too and leaves the entry alone', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(fact(page, 'counter', 'updates=1')).toBeVisible()

  await button(page, 'Write a String').click()

  await expect(factOf(page, 'typed', 'write=QueryDataTypeError')).toBeVisible()
  await expect(factOf(page, 'typed', 'expected=String')).toBeVisible()
  await expect(factOf(page, 'typed', 'actual=int')).toBeVisible()
  // Nothing was written: the entry still holds its one int.
  await expect(fact(page, 'counter', 'updates=1')).toBeVisible()
  await expect(fact(page, 'counter', 'status=success')).toBeVisible()
  await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
})

test('a mutation without a function fails with MissingMutationFunctionError and sends nothing', async ({
  page,
  open,
  scenario,
}) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await expect(factOf(page, 'no-function', 'status=idle')).toBeVisible()
  await expect(factOf(page, 'no-function', 'default=none')).toBeVisible()

  await button(page, 'Mutate without a function').click()

  await expect(factOf(page, 'no-function', 'status=error')).toBeVisible()
  await expect(factOf(page, 'no-function', 'error=MissingMutationFunctionError')).toBeVisible()
  await expect(page.getByText(/No mutationFn was provided/)).toBeVisible()
  await page.waitForTimeout(500)
  expect(await scenario.count('POST', INCREMENT)).toBe(0)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(0)
})

test('a default mutationFn registered for the key is the cure', async ({ page, open, scenario }) => {
  await scenario.config({ latency: 0 })
  await open('/diagnostics')
  await button(page, 'Mutate without a function').click()
  await expect(factOf(page, 'no-function', 'status=error')).toBeVisible()

  await button(page, 'Register a default mutationFn').click()
  await expect(factOf(page, 'no-function', 'default=registered')).toBeVisible()

  await button(page, 'Mutate without a function').click()

  await expect(factOf(page, 'no-function', 'status=success')).toBeVisible()
  await expect(factOf(page, 'no-function', 'data=1')).toBeVisible()
  expect(await scenario.count('POST', INCREMENT)).toBe(1)
  expect((await (await scenario.api('get', '/counter')).json()).value).toBe(1)
})

test.describe('options that throw in a build', () => {
  // The third card sits below the fold of the default viewport.
  test.use({ viewport: { width: 1280, height: 2000 } })

  const COUNTER = /^\/api\/counter$/

  async function read(page: Page, label: 'the counter' | 'the String entry') {
    const choice = group(page, 'keyed knob').getByRole('radio', { name: label, exact: true })
    await choice.click()
    await expect(choice).toBeChecked()
  }

  test('show the app\'s error widget, keep the observer, and recover', async ({ page, open, scenario }) => {
    await scenario.config({ latency: 0 })
    await open('/diagnostics')
    await expect(factOf(page, 'keyed', 'value=0')).toBeVisible()
    // The card's builder and the one in the first card's header.
    await expect(fact(page, 'counter', 'observers=2')).toBeVisible()
    const requests = await scenario.count('GET', COUNTER)

    await read(page, 'the String entry')
    const failure = group(page, 'build failure')
    await expect(failure).toBeVisible()
    await expect(failure).toContainText('holds String but was used as int')
    await expect(factOf(page, 'keyed', 'value=0')).toBeHidden()
    // Only that builder failed: the rest of the screen still answers, and
    // the refused options left its observer on the counter.
    await expect(page.getByText('counter=0', { exact: true })).toBeVisible()
    await expect(fact(page, 'counter', 'observers=2')).toBeVisible()
    await button(page, 'Read as int').click()
    await expect(factOf(page, 'typed', 'read=int 0')).toBeVisible()

    await read(page, 'the counter')
    await expect(failure).toBeHidden()
    await expect(factOf(page, 'keyed', 'value=0')).toBeVisible()
    await expect(fact(page, 'counter', 'observers=2')).toBeVisible()
    expect(await scenario.count('GET', COUNTER)).toBe(requests)
  })
})
