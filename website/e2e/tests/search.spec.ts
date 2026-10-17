// What a search engine reads: the AI notice is on every page but never the
// page's snippet, the home page names the site for Google's result label, and
// the favicon is there in the raster sizes Google's results show.
import { BASE, expect, test } from './fixtures'

const pages = [BASE, `${BASE}docs/overview`, `${BASE}docs/reference/api`]

test.describe('the AI notice', () => {
  // The HTML as served, as a crawler first reads it: no hydration.
  test.use({ javaScriptEnabled: false })

  // The site's chrome — the announcement bar, the footer, the home page's
  // hero — not a doc page's own text: where a page says it in its body
  // (the overview, the credits) it is that page's content.
  test('is shown on every page, and kept out of snippets', async ({ page }) => {
    for (const path of pages) {
      await page.goto(path)
      const found = await page.evaluate(() => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
        const notices: boolean[] = []
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (
            node.textContent?.includes('query_kit is an entirely AI-coded project') &&
            node.parentElement?.closest('.theme-doc-markdown') == null
          ) {
            notices.push(node.parentElement?.closest('[data-nosnippet]') != null)
          }
        }
        return notices
      })
      expect(found.length, path).toBeGreaterThan(0)
      expect(found, path).not.toContain(false)
    }
  })
})

test('the home page names the site query_kit', async ({ request }) => {
  const html = await (await request.get(BASE)).text()
  const json = html.match(/<script[^>]*type="?application\/ld\+json"?[^>]*>(.*?)<\/script>/s)
  expect(json).not.toBeNull()
  const graph: { '@type': string; name?: string; url?: string }[] = JSON.parse(json![1])['@graph']
  const site = graph.find((node) => node['@type'] === 'WebSite')
  expect(site?.name).toBe('query_kit')
  expect(site?.url).toBe(`https://query-kit.dualmeta.io${BASE}`)
})

test('the favicon is served as SVG, PNG and ICO', async ({ request }) => {
  const html = await (await request.get(BASE)).text()
  for (const href of ['/img/favicon.svg', '/img/favicon-96x96.png', '/img/apple-touch-icon.png']) {
    expect(html, href).toContain(`href=${href}`)
    expect((await request.get(href)).ok(), href).toBe(true)
  }
  expect((await request.get('/favicon.ico')).ok()).toBe(true)
})
