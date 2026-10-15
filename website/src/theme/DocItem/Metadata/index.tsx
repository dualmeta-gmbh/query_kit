// Ejected from the theme's DocItem/Metadata (a few lines) to give every doc
// page its own share image (`plugins/og-images.ts`), titled for the page; a
// page whose front matter names an `image` keeps that one.
import Head from '@docusaurus/Head'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import { useDoc } from '@docusaurus/plugin-content-docs/client'
import { PageMetadata } from '@docusaurus/theme-common'
import { ogImagePath } from '@site/src/og-image-path'
import type { ReactNode } from 'react'

export default function DocItemMetadata(): ReactNode {
  const { metadata, frontMatter, assets } = useDoc()
  const { siteConfig } = useDocusaurusContext()
  const own = assets.image ?? frontMatter.image
  const alt = `${metadata.title} — query_kit, TanStack Query for Dart and Flutter`
  return (
    <>
      <PageMetadata
        title={metadata.title}
        description={metadata.description}
        keywords={frontMatter.keywords}
        image={own ?? `/${ogImagePath(metadata.permalink, siteConfig.baseUrl)}`}
      />
      <Head>
        <meta property="og:type" content="article" />
        {own === undefined && <meta property="og:image:alt" content={alt} />}
        {own === undefined && <meta name="twitter:image:alt" content={alt} />}
      </Head>
    </>
  )
}
