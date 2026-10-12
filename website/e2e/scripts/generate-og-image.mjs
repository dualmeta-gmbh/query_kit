import { chromium } from '@playwright/test'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

// Social crawlers need a raster image. Keep its editable SVG alongside it;
// image generation is explicit and never adds a browser dependency to builds.
const source = new URL('../../static/img/og-image.svg', import.meta.url)
const destination = new URL('../../static/img/og-image.png', import.meta.url)
const browser = await chromium.launch()
try {
  const page = await browser.newPage({
    viewport: { width: 1200, height: 630 },
    deviceScaleFactor: 1,
  })
  await page.setContent(`<style>html,body{margin:0}svg{display:block}</style>${await readFile(source, 'utf8')}`)
  await page.evaluate(() => document.fonts.ready)
  await page.screenshot({ path: fileURLToPath(destination) })
  console.log(`Generated ${fileURLToPath(destination)} (1200 × 630)`)
} finally {
  await browser.close()
}
