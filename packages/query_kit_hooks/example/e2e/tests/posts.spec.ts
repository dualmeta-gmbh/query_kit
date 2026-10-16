// The Posts tab: the list, the posts recently viewed, and a post's detail.
import { expect, factIn, group, holdRequest, test } from './fixtures'

const first = 'Local development: setup guide'
const second = 'Continuous integration: setup guide'
const third = 'Code review: setup guide'
const lastButOne = 'Data export: setup guide'
const last = 'Analytics events: setup guide'

test.describe('useQuery', () => {
  test('the list loads, and a refusal shows the backend’s sentence', async ({ page, open, scenario }) => {
    await open()
    await expect(page.getByRole('button', { name: first })).toBeVisible()

    // The first attempt and the client's one retry.
    await scenario.config({ failNext: [{ method: 'GET', path: '/api/posts/1', count: 2, status: 503 }] })
    const post = holdRequest(page, /\/api\/posts\/1$/)
    await page.getByRole('button', { name: first }).click()
    await expect(page.getByText('Loading post…', { exact: true })).toBeVisible()

    await post.release()
    await expect(page.getByText('Scripted failure 503', { exact: true })).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(2)
  })
})

test.describe('usePrefetchQuery', () => {
  test('a post’s comments are asked for beside the post, not after it', async ({ page, open, scenario }) => {
    await open()
    const post = holdRequest(page, /\/api\/posts\/1$/)
    await page.getByRole('button', { name: first }).click()
    await expect(page.getByText('Loading post…', { exact: true })).toBeVisible()

    // The post is held in the browser, so the widget that reads the comments
    // does not exist yet; their request is answered all the same.
    await expect.poll(() => scenario.count('GET', /^\/api\/posts\/1\/comments$/)).toBe(1)
    expect(await scenario.count('GET', /^\/api\/posts\/1$/)).toBe(0)

    await post.release()
    await expect(factIn(page, 'comments', '3 comments')).toBeVisible()
    await expect(page.getByText('Loading comments…', { exact: true })).toHaveCount(0)
    expect(await scenario.count('GET', /^\/api\/posts\/1\/comments$/)).toBe(1)
  })
})

test.describe('useSelectQuery', () => {
  test('the post after this one comes from the list’s ids, in order', async ({ page, open }) => {
    await open()
    await page.getByRole('button', { name: second }).click()
    await expect(factIn(page, 'up next', `Up next: ${third}, then Release notes: setup guide`)).toBeVisible()
  })
})

test.describe('useCombinedQueries', () => {
  test('two posts as one answer, and the next post opens from the cache', async ({ page, open, scenario }) => {
    await open()
    await page.getByRole('button', { name: first }).click()
    await expect(factIn(page, 'up next', `Up next: ${second}, then ${third}`)).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)

    await group(page, 'up next').getByRole('button', { name: 'Next post' }).click()
    await expect(page.getByRole('heading', { name: 'Post 2' })).toBeVisible()
    await expect(group(page, 'post').getByText(second, { exact: false })).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
  })

  test('one post left is an answer of one, and none is no answer', async ({ page, open }) => {
    await open()
    // The wheel lands on the list under the pointer; the end of the list has
    // the last two posts.
    const firstBox = (await page.getByRole('button', { name: first }).boundingBox())!
    await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + firstBox.height / 2)
    const target = page.getByRole('button', { name: lastButOne })
    await expect(async () => {
      await page.mouse.wheel(0, 4000)
      await expect(target).toBeVisible({ timeout: 500 })
    }).toPass()

    await target.click()
    await expect(page.getByRole('heading', { name: 'Post 29' })).toBeVisible()
    await expect(factIn(page, 'up next', `Up next: ${last}`)).toBeVisible()

    await group(page, 'up next').getByRole('button', { name: 'Next post' }).click()
    await expect(page.getByRole('heading', { name: 'Post 30' })).toBeVisible()
    await expect(group(page, 'post').getByText(last, { exact: false })).toBeVisible()
    await expect(group(page, 'up next')).toHaveCount(0)
  })

  test('one failure fails the answer, and retry asks again', async ({ page, open, scenario }) => {
    await open()
    // The first attempt and the client's one retry.
    await scenario.config({ failNext: [{ method: 'GET', path: '/api/posts/3', count: 2, status: 500 }] })
    await page.getByRole('button', { name: first }).click()
    const retry = group(page, 'up next').getByRole('button', { name: 'Up next failed: Scripted failure 500. Try again' })
    await expect(retry).toBeVisible()

    await retry.click()
    await expect(factIn(page, 'up next', `Up next: ${second}, then ${third}`)).toBeVisible()
    expect(await scenario.count('GET', /^\/api\/posts\/3$/)).toBe(3)
    // Retry asks again for what failed, not for what had arrived.
    expect(await scenario.count('GET', /^\/api\/posts\/2$/)).toBe(1)
  })
})

test.describe('useQueries', () => {
  test('the posts opened, newest first, read from the cache', async ({ page, open, scenario }) => {
    await open()
    await expect(page.getByRole('button', { name: first })).toBeVisible()
    await expect(page.getByText('Recently viewed', { exact: true })).toHaveCount(0)

    await page.getByRole('button', { name: first }).click()
    await group(page, 'up next').getByRole('button', { name: 'Next post' }).click()
    await expect(page.getByRole('heading', { name: 'Post 2' })).toBeVisible()
    await page.getByRole('button', { name: 'Back' }).click()

    const viewed = group(page, 'recently viewed')
    await expect(viewed.getByRole('button')).toHaveText([second, first])
    expect(await scenario.count('GET', /^\/api\/posts\/[12]$/)).toBe(2)
  })
})
