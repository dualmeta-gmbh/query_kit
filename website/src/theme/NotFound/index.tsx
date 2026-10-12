import { PageMetadata } from '@docusaurus/theme-common'
import OriginalNotFound from '@theme-original/NotFound'
import type { ReactNode } from 'react'

export default function NotFound(): ReactNode {
  return (
    <>
      <OriginalNotFound />
      <PageMetadata description="The requested query_kit documentation page could not be found.">
        <meta name="robots" content="noindex, follow" />
      </PageMetadata>
    </>
  )
}
