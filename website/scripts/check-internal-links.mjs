// Fails when a documentation page is barely linked from the other pages, or
// when the sitemap and the built pages disagree.
//
// A crawler finds a page by following links, and weighs it by how many pages
// point at it. The navbar, the sidebar and the footer are on every page, so
// they say nothing about a page; the links a human wrote into the body of
// other pages do. This counts those: for every doc page of the build, how
// many other pages link to it from inside their content (the article of a doc
// page, the `<main>` of the home page), and fails below MIN_INBOUND.
//
// The second check is the sitemap's. Every URL in it must be a page of the
// build, and every doc page that has content must be in it. The page at
// `/docs` is a redirect stub that `@docusaurus/plugin-client-redirects`
// writes: it has no content and is not canonical, so it must stay out.
//
//   node scripts/check-internal-links.mjs [build-dir]   (default: build)
//
// Run by `npm run build`, after Docusaurus, because it reads the build. Needs
// nothing but Node.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// A page with fewer than this many inbound content links fails.
const MIN_INBOUND = 2

// Doc routes that may fall below MIN_INBOUND, each with the reason. Empty
// today: link the page from the one that explains it rather than adding to
// this list.
const ALLOWED_LOW_INBOUND = new Map([
  // ['/docs/some/page', 'why nothing should link to it'],
])

const site = join(dirname(fileURLToPath(import.meta.url)), '..')
const build = resolve(process.argv[2] ?? join(site, 'build'))
if (!existsSync(build)) {
  console.error(`check-internal-links: ${build} does not exist; run the Docusaurus build first`)
  process.exit(1)
}

const files = []
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) walk(path)
    else if (name.endsWith('.html')) files.push(path)
  }
}
walk(build)

// `build/docs/guides/queries.html` is the route `/docs/guides/queries`, and
// `build/index.html` is `/` (trailingSlash is false in docusaurus.config.ts).
const route = (path) =>
  '/' + relative(build, path).replace(/index\.html$/, '').replace(/\.html$/, '').replace(/\/$/, '')
const pages = new Map(files.map((file) => [route(file), file]))

const docContent = /<div class="theme-doc-markdown markdown">([\s\S]*?)<\/article>/
const mainContent = /<main[^>]*>([\s\S]*?)<\/main>/

const inbound = new Map()
const docRoutes = []
for (const [path, file] of pages) {
  const html = readFileSync(file, 'utf8')
  const doc = html.match(docContent)
  if (doc && path.startsWith('/docs/')) {
    docRoutes.push(path)
    inbound.set(path, new Set())
  }
}
for (const [path, file] of pages) {
  const html = readFileSync(file, 'utf8')
  const content = (html.match(docContent) ?? html.match(mainContent))?.[1]
  if (content === undefined) continue
  // Minified HTML leaves attribute values unquoted, so the quote is optional.
  for (const [, href] of content.matchAll(/href="?(\/[^"#? >]*)/g)) {
    const target = href.replace(/\/$/, '') || '/'
    if (target !== path && inbound.has(target)) inbound.get(target).add(path)
  }
}

const problems = []

const counts = docRoutes.map((r) => inbound.get(r).size).sort((a, b) => a - b)
const median = counts.length === 0 ? 0 : counts[Math.floor(counts.length / 2)]
const low = docRoutes
  .filter((r) => inbound.get(r).size < MIN_INBOUND)
  .sort((a, b) => inbound.get(a).size - inbound.get(b).size || a.localeCompare(b))
const allowed = low.filter((r) => ALLOWED_LOW_INBOUND.has(r))
for (const r of low.filter((r) => !ALLOWED_LOW_INBOUND.has(r))) {
  problems.push(`${r} has ${inbound.get(r).size} inbound content link(s); at least ${MIN_INBOUND} are required`)
}
for (const r of ALLOWED_LOW_INBOUND.keys()) {
  if (!docRoutes.includes(r)) problems.push(`${r} is allowed to be unlinked but is not a page of the build; drop it from the list`)
}

// The sitemap: one `<loc>` per canonical page.
const sitemapFile = join(build, 'sitemap.xml')
if (!existsSync(sitemapFile)) {
  problems.push('build/sitemap.xml is missing')
} else {
  const listed = new Set(
    [...readFileSync(sitemapFile, 'utf8').matchAll(/<loc>([^<]*)<\/loc>/g)].map(([, loc]) => {
      const path = new URL(loc).pathname.replace(/\/$/, '')
      return path === '' ? '/' : path
    }),
  )
  for (const path of listed) {
    if (!pages.has(path)) problems.push(`the sitemap lists ${path}, which is not a page of the build`)
    else if (path === '/docs') problems.push('the sitemap lists /docs, a redirect stub that is not canonical')
  }
  for (const path of docRoutes) {
    if (!listed.has(path)) problems.push(`${path} is a doc page but is not in the sitemap`)
  }
}

console.log(
  `check-internal-links: ${docRoutes.length} doc pages, inbound content links min ${counts[0] ?? 0}, median ${median}` +
    (allowed.length > 0 ? `, ${allowed.length} allowed below ${MIN_INBOUND}` : ''),
)
if (problems.length > 0) {
  console.error(`check-internal-links: ${problems.length} problem(s):\n  ${problems.join('\n  ')}`)
  console.error(
    'Link the page from the guide, example or recipe a reader would come from it by, in a sentence or a "See also" list.',
  )
  process.exit(1)
}
