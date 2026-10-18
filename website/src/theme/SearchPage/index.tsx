import { PageMetadata } from '@docusaurus/theme-common'
import OriginalSearchPage from '@theme-original/SearchPage'
import type { ReactNode } from 'react'

// The local-search plugin's results page. It marks itself `noindex` with a
// `property="robots"` tag, which no crawler reads, so the page would be
// indexed (#74); this says it the way Docusaurus does for the 404 page, with
// `name="robots"`, which replaces the site-wide `index, follow`.
export default function SearchPage(): ReactNode {
  return (
    <>
      <OriginalSearchPage />
      <PageMetadata>
        <meta name="robots" content="noindex, follow" />
      </PageMetadata>
    </>
  )
}
