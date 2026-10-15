// The shell around every tab: the activity line and the page fetched before
// its tab exists.
import { expect, factIn, holdRequest, test } from './fixtures'

test.describe('useIsFetching', () => {
  test('counts the queries fetching, app-wide, and goes back to none', async ({ page, open }) => {
    const posts = holdRequest(page, /\/api\/posts$/)
    await open()
    // The projects page answers; the list is still held.
    await expect(factIn(page, 'activity', 'fetching 1')).toBeVisible()
    await expect(page.getByText('Loading posts…', { exact: true })).toBeVisible()
    await expect.poll(() => posts.seen).toBe(1)

    await posts.release()
    await expect(factIn(page, 'activity', 'fetching 0')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Local development: setup guide' })).toBeVisible()
  })
})

test.describe('usePrefetchInfiniteQuery', () => {
  test('the projects tab opens on the page fetched before it was built', async ({ page, open, scenario }) => {
    await open()
    await expect(factIn(page, 'activity', 'fetching 0')).toBeVisible()
    expect((await scenario.requests()).filter((entry) => entry.path === '/api/projects').map((entry) => entry.query)).toEqual([
      { cursor: '0', limit: '10' },
    ])

    await page.getByRole('tab', { name: 'Projects' }).click()
    await expect(factIn(page, 'projects', '10 projects loaded')).toBeVisible()
    await expect(page.getByText('Loading projects…', { exact: true })).toHaveCount(0)
    expect(await scenario.count('GET', /^\/api\/projects$/)).toBe(1)
  })
})
