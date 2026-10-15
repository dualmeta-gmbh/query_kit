/**
 * Where a page's share image lives, relative to the site's root (no base
 * URL): `/docs/quick-start` → `img/og/docs/quick-start.png`, the landing page
 * `img/og/index.png`. `plugins/og-images.ts` writes the files there, and the
 * pages that point `og:image` at them ask this, so the two cannot drift.
 */
export function ogImagePath(permalink: string, baseUrl: string): string {
  const path = (permalink.startsWith(baseUrl) ? permalink.slice(baseUrl.length) : permalink)
    .replace(/^\/+/, '')
    .replace(/\/$/, '')
  return `img/og/${path === '' ? 'index' : path}.png`
}
