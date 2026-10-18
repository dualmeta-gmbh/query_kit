import type * as Preset from '@docusaurus/preset-classic'
import type { Config } from '@docusaurus/types'
import { execSync } from 'node:child_process'
import dartSource from './plugins/dart-source'
import llmsTxt, { type LlmsTxtOptions } from './plugins/llms-txt'
import ogImages, { type OgImagesOptions } from './plugins/og-images'
import { geist } from './src/prismThemes'

// The live documentation site's coordinates: GitHub Pages under the custom
// domain query-kit.dualmeta.io, at its root. The repository's name is still
// the Pages project name. Every hard-coded link that `baseUrl` does not reach
// (the announcement bar is raw HTML) is built from `baseUrl`, so moving the
// site is one edit here; the domain itself is a Pages setting
// (docs/releasing.md, "Documentation site").
const repository = 'query_kit'
const baseUrl = '/'
const siteUrl = 'https://query-kit.dualmeta.io'

// The project's AI disclosure, in the one wording used everywhere a reader
// can land first.
//
// Where it is raw HTML (the announcement bar, the footer) it sits in a
// `data-nosnippet` span: a reader sees it on every page, but a search engine
// does not quote it as the page's summary. Being the first text of every
// page's body, it was the snippet Google showed for every result instead of
// the page's own description.
const nosnippet = (html: string) => `<span data-nosnippet>${html}</span>`
const aiNotice =
  "query_kit is an entirely AI-coded project: all code, tests and documentation were written by AI coding agents (Anthropic's Claude). A human maintainer set the goals and reviews releases, but did not write the code."

// The commit the site is built from. `<DartSource>` links an excerpt to its
// lines on GitHub at this commit, not at `main`, where later edits would move
// them. CI names it; a local build asks git; outside a checkout, `main`.
function sourceRevision(): string {
  if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA
  try {
    return execSync('git rev-parse HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return 'main'
  }
}

const config: Config = {
  title: 'query_kit',
  tagline: 'TanStack Query for Dart and Flutter, ported test for test',
  favicon: 'img/favicon.svg',

  url: siteUrl,
  baseUrl,
  organizationName: 'dualmeta-gmbh',
  projectName: repository,
  trailingSlash: false,

  // A link to a page that does not exist fails the build, and so does a
  // link to a heading that does not exist. That is the point of building the
  // site in CI.
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: { hooks: { onBrokenMarkdownLinks: 'throw' } },

  future: { v4: true, faster: true },

  customFields: { sourceRevision: sourceRevision() },

  // Geist and Geist Mono. `custom.css` falls back to the system stack,
  // so a blocked or slow font request costs the face and nothing else — and
  // the build never reaches for the network, only the rendered page does.
  headTags: [
    {
      tagName: 'link',
      attributes: { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'preconnect',
        href: 'https://fonts.gstatic.com',
        crossorigin: 'anonymous',
      },
    },
    // The favicon as PNG and as an Apple touch icon, beside the SVG that
    // `favicon` names: Google's results show a site's icon only from a size
    // that is a multiple of 48px, and Safari's home-screen icon takes no SVG.
    // `static/favicon.ico` answers the crawlers that ask for that path alone.
    // All three are rendered from `static/img/favicon.svg` by
    // `scripts/render-favicons.mjs`.
    {
      tagName: 'link',
      attributes: { rel: 'icon', type: 'image/png', sizes: '96x96', href: `${baseUrl}img/favicon-96x96.png` },
    },
    {
      tagName: 'link',
      attributes: { rel: 'apple-touch-icon', sizes: '180x180', href: `${baseUrl}img/apple-touch-icon.png` },
    },
    // The site's index for AI agents (`plugins/llms-txt.ts`). It lives under
    // the base path, not at the host's root, so a page says where it is.
    {
      tagName: 'link',
      attributes: { rel: 'alternate', type: 'text/plain', title: 'llms.txt', href: `${baseUrl}llms.txt` },
    },
    // Ownership proof for the Google Search Console property of the site's
    // former address, `https://dualmeta-gmbh.github.io/query_kit/`, which now
    // redirects here. The domain property `dualmeta.io` covers the current
    // address by DNS.
    {
      tagName: 'meta',
      attributes: {
        name: 'google-site-verification',
        content: 'uLToA5k0XxJoDHXEH5Pw0t7MQCZd1e1XM-BLf3BHb-4',
      },
    },
  ],
  stylesheets: [
    'https://fonts.googleapis.com/css2?family=Geist:wght@400..700&family=Geist+Mono:wght@400..600&display=swap',
  ],

  i18n: { defaultLocale: 'en', locales: ['en'] },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/docs',
          editUrl: 'https://github.com/dualmeta-gmbh/query_kit/tree/main/website/',
          showLastUpdateTime: false,
        },
        blog: false,
        // The search plugin's results page lives at `/search`: it has no
        // content of its own, and it says `noindex`, so it stays out of the
        // sitemap too.
        sitemap: { ignorePatterns: ['/search'] },
        theme: { customCss: './src/css/custom.css' },
      } satisfies Preset.Options,
    ],
  ],

  // Search is built here and served from the same static files as the pages:
  // `npm run build` writes a lunr index into `build/`, and the browser loads
  // it on first use. No account, no crawler, no API key in the repository, and
  // no outside service at runtime (#74); Algolia DocSearch would need all
  // four. Only the doc pages are indexed: the home page repeats the overview,
  // and the API reference is pub.dev's dartdoc, which has a search of its own.
  themes: [
    [
      '@easyops-cn/docusaurus-search-local',
      {
        // A hash in the index's file name (`true` would put it in a query
        // string, so the file's name would not change). The plugin hashes its
        // version and the raw `docs/**/*.md(x)` files only: a change to an
        // imported Dart source, the sidebar, these options or Docusaurus keeps
        // the name, so a reader's cache can serve the old index for as long as
        // GitHub Pages' `max-age` (ten minutes) allows.
        hashed: 'filename',
        docsRouteBasePath: '/docs',
        indexDocs: true,
        indexBlog: false,
        indexPages: false,
        language: ['en'],
        // Off: it appends `?_highlight=` to every result, a second URL for
        // each page that a crawler could find and the sitemap does not list.
        highlightSearchTermsOnTargetPage: false,
        explicitSearchResultPath: true,
        searchResultLimits: 8,
        searchResultContextMaxLength: 60,
      },
    ],
  ],

  // No page lives at `/docs` itself; a reader who trims a docs URL back to
  // it lands on the overview rather than a 404.
  plugins: [
    // `.dart` files importable as strings: the examples pages show the
    // compiled source itself (`src/components/DartSource`).
    dartSource,
    // Every doc page as Markdown at its URL plus `.md`, and `llms.txt` /
    // `llms-full.txt` over all of them, written into the build.
    [
      llmsTxt,
      {
        summary: `TanStack Query for Dart and Flutter, ported test for test. ${aiNotice} A community port, not affiliated with or endorsed by TanStack.`,
        details: `query_kit is a port of TanStack Query's \`query-core\` to Dart (the package \`query_kit\`, pure Dart) with a Flutter binding on top (\`query_kit_flutter\`), both on pub.dev. It caches server state per query key, deduplicates and retries fetches, refetches stale data on focus, on reconnect or on an interval, and covers mutations, optimistic updates and infinite queries. Its behaviour follows TanStack Query's, proven by porting upstream's test suite; where it differs is listed on the "Differences from TanStack Query" page below.

Install with \`flutter pub add query_kit_flutter\` in a Flutter app, or \`dart pub add query_kit\` in pure Dart. Every page below is Markdown at its own URL with \`.md\` appended, and all of them together are ${siteUrl}${baseUrl}llms-full.txt. Source: https://github.com/dualmeta-gmbh/query_kit`,
        optional: ['Project'],
      } satisfies LlmsTxtOptions,
    ],
    // A share image per doc page and one for the landing page, written into
    // the build; `static/img/og-image.png` stays the fallback for the rest.
    [
      ogImages,
      {
        landing: { kicker: 'TanStack Query for Dart and Flutter', title: 'Server data. Cached. Kept fresh.' },
      } satisfies OgImagesOptions,
    ],
    [
      '@docusaurus/plugin-client-redirects',
      { redirects: [{ from: '/docs', to: '/docs/overview' }] },
    ],
  ],

  themeConfig: {
    // The fallback share image, for pages without their own: the landing page
    // and every doc page get one from `plugins/og-images.ts`. Titles,
    // descriptions, canonical URLs and og:locale are specific to each page.
    image: 'img/og-image.png',
    metadata: [
      { property: 'og:type', content: 'website' },
      { property: 'og:site_name', content: 'query_kit' },
      { property: 'og:image:type', content: 'image/png' },
      { property: 'og:image:width', content: '1200' },
      { property: 'og:image:height', content: '630' },
      {
        property: 'og:image:alt',
        content: 'query_kit — TanStack Query for Dart and Flutter. Server data, cached and kept fresh.',
      },
      {
        name: 'twitter:image:alt',
        content: 'query_kit — TanStack Query for Dart and Flutter. Server data, cached and kept fresh.',
      },
      { name: 'theme-color', content: '#0468c8' },
      { name: 'robots', content: 'index, follow, max-image-preview:large' },
    ],
    colorMode: { respectPrefersColorScheme: true },
    // Dismissible: a reader who has read it once can close it, and
    // Docusaurus keeps that in localStorage under this `id` (change the id
    // to show a reworded notice to everyone again). The same disclosure stays
    // in the landing page's hero and in the footer, so closing the bar hides
    // nothing for good. Its colours are in `custom.css`, because
    // `backgroundColor` here lands as an inline style that no stylesheet —
    // and so no dark-mode rule — can override.
    announcementBar: {
      id: 'unaffiliated-and-ai-coded',
      content: nosnippet(
        `${aiNotice} It is a community port of TanStack Query, <b>not affiliated with or endorsed by TanStack</b>. <a href="${baseUrl}docs/project/credits">What that means</a>.`,
      ),
      isCloseable: true,
    },
    navbar: {
      title: 'query_kit',
      logo: { alt: '', src: 'img/logo.svg', width: 26, height: 26 },
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { to: '/docs/coming-from-react-query', position: 'left', label: 'From React Query' },
        { to: '/docs/examples', position: 'left', label: 'Examples' },
        { to: '/docs/project/fidelity', position: 'left', label: 'Fidelity' },
        { to: '/docs/project/credits', position: 'left', label: 'Credits' },
        {
          href: 'https://github.com/dualmeta-gmbh/query_kit',
          position: 'right',
          className: 'header-github-link',
          'aria-label': 'GitHub repository',
        },
      ],
    },
    footer: {
      style: 'light',
      links: [
        {
          title: 'Docs',
          items: [
            { label: 'Installation', to: '/docs/installation' },
            { label: 'Quick start', to: '/docs/quick-start' },
            { label: 'Four ways to read a query', to: '/docs/guides/reading-queries-in-widgets' },
            { label: 'Feature matrix', to: '/docs/reference/feature-matrix' },
          ],
        },
        {
          title: 'Project',
          items: [
            { label: 'Credits, and what this is not', to: '/docs/project/credits' },
            { label: 'How fidelity is proven', to: '/docs/project/fidelity' },
            { label: 'How the examples are built', to: '/docs/project/examples' },
            { label: 'Contributing', href: 'https://github.com/dualmeta-gmbh/query_kit/blob/main/CONTRIBUTING.md' },
            { label: 'Porting notes', href: 'https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md' },
          ],
        },
        {
          // Built by `plugins/llms-txt.ts`; `pathname://` because they are
          // files of the build, not pages the router knows.
          title: 'For AI agents',
          items: [
            { label: 'llms.txt', href: 'pathname:///llms.txt' },
            { label: 'llms-full.txt', href: 'pathname:///llms-full.txt' },
          ],
        },
        {
          title: 'Elsewhere',
          items: [
            { label: 'GitHub', href: 'https://github.com/dualmeta-gmbh/query_kit' },
            { label: 'TanStack Query', href: 'https://tanstack.com/query' },
          ],
        },
      ],
      copyright: nosnippet(
        `${aiNotice} A port of TanStack Query, published with thanks under its MIT licence. Not affiliated with, endorsed by, or connected to Tanner Linsley, the TanStack team or the TanStack organisation.`,
      ),
    },
    prism: {
      // Geist-style colours (`src/prismThemes.ts`). One theme for both
      // modes: it names CSS variables, and `custom.css` sets them per mode,
      // so a dark page's code is dark before hydration too.
      theme: geist,
      darkTheme: geist,
      additionalLanguages: ['dart', 'bash', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
}

export default config
