import type { LoadedContent as DocsContent } from '@docusaurus/plugin-content-docs'
import type { LoadContext, Plugin } from '@docusaurus/types'
import { Resvg } from '@resvg/resvg-js'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import satori from 'satori'
import { ogImagePath } from '../src/og-image-path'

/**
 * A share image per page, written into the build by `postBuild`: every doc
 * page gets `img/og/<its path>.png` (`/docs/quick-start` →
 * `/img/og/docs/quick-start.png`), and the landing page `img/og/index.png`.
 * `src/theme/DocItem/Metadata` and the landing page point `og:image` at them;
 * every other page keeps the site's `static/img/og-image.png`.
 *
 * The image is typographic: the logo and the site's address on top, the page's
 * sidebar section as a kicker and its title as the headline at the bottom, on
 * the site's dark ground with a faint grid. Rendered with Satori (what Vercel's
 * `@vercel/og` runs on, without a server) and resvg, in Geist, the site's own
 * face — Satori reads WOFF, not the WOFF2 the browser gets.
 */

type Doc = DocsContent['loadedVersions'][number]['docs'][number]
type SidebarItem = DocsContent['loadedVersions'][number]['sidebars'][string][number]

/** One image: the small line above the headline, and the headline. */
export type OgCard = { kicker: string; title: string }

export type OgImagesOptions = {
  /** The landing page's card. */
  landing: OgCard
}

const size = { width: 1200, height: 630 }

// The site's dark mode (src/css/custom.css) and the logo's three blues.
const palette = {
  ground: '#0a0b0f',
  grid: 'rgb(255 255 255 / 0.045)',
  glows: [
    'radial-gradient(ellipse 900px 520px at 12% 0%, rgb(11 107 203 / 0.34), transparent 75%)',
    'radial-gradient(ellipse 700px 600px at 100% 85%, rgb(86 184 255 / 0.14), transparent 80%)',
  ],
  ink: '#ececf1',
  muted: '#9aa1ad',
  kicker: '#56b8ff',
  entries: ['#a8cdf4', '#4b9bea', '#0b6bcb'],
}

// A minimal element factory: Satori takes React-shaped objects, and this file
// is a build plugin, not a component, so it does without JSX.
type Node = { type: string; props: Record<string, unknown> }
const h = (type: string, props: Record<string, unknown>, ...children: unknown[]): Node => ({
  type,
  props: { ...props, children: children.length === 1 ? children[0] : children },
})

// The logo (static/img/logo.svg) at any size: three cached entries.
const logo = (scale: number): Node =>
  h(
    'div',
    { style: { display: 'flex', position: 'relative', width: 32 * scale, height: 32 * scale } },
    ...palette.entries.map((fill, index) =>
      h('div', {
        style: {
          position: 'absolute',
          left: (4 + 2 * index) * scale,
          top: (4.5 + 7 * index) * scale,
          width: 20 * scale,
          height: 8 * scale,
          borderRadius: 2.5 * scale,
          backgroundColor: fill,
        },
      }),
    ),
  )

/** Steps a long headline down so it fits in three lines. */
const titleSize = (title: string): number => (title.length > 60 ? 68 : title.length > 34 ? 80 : 96)

export const card = ({ kicker, title }: OgCard, host: string): Node =>
  h(
    'div',
    {
      style: {
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'space-between',
        width: size.width,
        height: size.height,
        boxSizing: 'border-box',
        padding: '64px 72px',
        fontFamily: 'Geist',
        backgroundColor: palette.ground,
        backgroundImage: [
          ...palette.glows,
          `linear-gradient(to right, ${palette.grid} 1px, transparent 1px)`,
          `linear-gradient(to bottom, ${palette.grid} 1px, transparent 1px)`,
        ].join(', '),
        backgroundSize: [...palette.glows.map(() => '100% 100%'), '40px 40px', '40px 40px'].join(', '),
      },
    },
    h(
      'div',
      { style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' } },
      h(
        'div',
        { style: { display: 'flex', alignItems: 'center', gap: 14 } },
        logo(1.75),
        h('div', { style: { color: palette.ink, fontSize: 40, fontWeight: 700, letterSpacing: '-0.03em' } }, 'query_kit'),
      ),
      h('div', { style: { color: palette.muted, fontSize: 24, fontWeight: 500 } }, host),
    ),
    h(
      'div',
      { style: { display: 'flex', flexDirection: 'column', width: '100%' } },
      h(
        'div',
        { style: { display: 'flex', alignItems: 'center', gap: 14, color: palette.kicker, fontSize: 32, fontWeight: 600 } },
        h('div', { style: { width: 30, height: 12, borderRadius: 4, backgroundColor: palette.entries[1] } }),
        kicker,
      ),
      h(
        'div',
        {
          style: {
            display: 'flex',
            marginTop: 18,
            width: '100%',
            color: palette.ink,
            fontSize: titleSize(title),
            fontWeight: 800,
            letterSpacing: '-0.04em',
            lineHeight: 1.04,
          },
        },
        title,
      ),
    ),
  )

// The top-level sidebar category each doc sits under: its kicker.
function sections(items: SidebarItem[]): Map<string, string> {
  const byDoc = new Map<string, string>()
  const visit = (item: SidebarItem, section: string) => {
    if (item.type === 'doc' || item.type === 'ref') byDoc.set(item.id, section)
    if (item.type === 'category') {
      if (item.link?.type === 'doc') byDoc.set(item.link.id, section)
      for (const child of item.items) visit(child, section)
    }
  }
  for (const item of items) visit(item, item.type === 'category' ? item.label : 'Documentation')
  return byDoc
}

// `options` is `unknown` because that is what a plugin entry in the config
// is typed to pass; the config checks its object with `satisfies`.
export default function ogImagesPlugin(context: LoadContext, rawOptions: unknown): Plugin {
  const options = rawOptions as OgImagesOptions
  const { siteConfig } = context
  const host = new URL(siteConfig.url).host
  let docs: Doc[] = []
  let sidebar: SidebarItem[] = []

  return {
    name: 'og-images',

    async allContentLoaded({ allContent }) {
      const content = allContent['docusaurus-plugin-content-docs']?.default as DocsContent | undefined
      const version = content?.loadedVersions[0]
      if (version === undefined) throw new Error('og-images: no docs were loaded')
      docs = version.docs
      sidebar = version.sidebars.docs ?? Object.values(version.sidebars)[0] ?? []
    },

    async postBuild({ outDir }) {
      const require = createRequire(import.meta.url)
      const font = (weight: number) =>
        readFile(require.resolve(`@fontsource/geist-sans/files/geist-sans-latin-${weight}-normal.woff`))
      const fonts = await Promise.all(
        ([500, 600, 700, 800] as const).map(async (weight) => ({
          name: 'Geist',
          data: await font(weight),
          weight,
          style: 'normal' as const,
        })),
      )
      const render = async (cardContent: OgCard, path: string) => {
        const svg = await satori(card(cardContent, host) as never, { ...size, fonts })
        const png = new Resvg(svg, { fitTo: { mode: 'width', value: size.width } }).render().asPng()
        const target = join(outDir, path)
        await mkdir(dirname(target), { recursive: true })
        await writeFile(target, png)
      }

      const sectionOf = sections(sidebar)
      await render(options.landing, ogImagePath(siteConfig.baseUrl, siteConfig.baseUrl))
      for (const doc of docs) {
        if (doc.unlisted || doc.frontMatter.image) continue
        await render(
          { kicker: sectionOf.get(doc.id) ?? 'Documentation', title: doc.title },
          ogImagePath(doc.permalink, siteConfig.baseUrl),
        )
      }
    },
  }
}
