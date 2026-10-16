// The Projects tab: a list loaded a page at a time.
import { expect, factIn, group, holdRequest, test } from './fixtures'

test.describe('useInfiniteQuery', () => {
  test('a page at a time, each from the cursor the last one named', async ({ page, open, scenario }) => {
    await open()
    await page.getByRole('tab', { name: 'Projects' }).click()
    await expect(factIn(page, 'projects', '10 projects loaded')).toBeVisible()

    const next = holdRequest(page, /\/api\/projects\?cursor=10&limit=10$/)
    await group(page, 'projects').getByRole('button', { name: 'Load more' }).click()
    await expect(factIn(page, 'projects', 'Loading more…')).toBeVisible()
    await expect(factIn(page, 'projects', '10 projects loaded')).toBeVisible()

    await next.release()
    await expect(factIn(page, 'projects', '20 projects loaded')).toBeVisible()
    await expect(group(page, 'projects').getByRole('button', { name: 'Load more' })).toBeVisible()
    expect((await scenario.requests()).filter((entry) => entry.path === '/api/projects').map((entry) => entry.query.cursor)).toEqual([
      '0',
      '10',
    ])
  })

  test('the last page says so', async ({ page, open, scenario }) => {
    await open()
    await page.getByRole('tab', { name: 'Projects' }).click()
    for (let loaded = 10; loaded < 100; loaded += 10) {
      await expect(factIn(page, 'projects', `${loaded} projects loaded`)).toBeVisible()
      await group(page, 'projects').getByRole('button', { name: 'Load more' }).click()
    }
    await expect(factIn(page, 'projects', '100 projects loaded')).toBeVisible()
    await expect(factIn(page, 'projects', 'All loaded')).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(10)
  })
})
