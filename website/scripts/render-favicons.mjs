// Renders the raster favicons from `static/img/favicon.svg`, the one source of
// the icon: `img/favicon-96x96.png` (Google's results take an icon only at a
// multiple of 48px), `img/apple-touch-icon.png` (Safari's home screen takes no
// SVG) and `favicon.ico` at the site's root, for clients that ask for that
// path and nothing else. The outputs are committed; run this again after
// editing the SVG:
//
//   node scripts/render-favicons.mjs
import { Resvg } from '@resvg/resvg-js'
import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const statics = fileURLToPath(new URL('../static/', import.meta.url))
const svg = await readFile(`${statics}img/favicon.svg`)

const png = (size) =>
  new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng()

/** An ICO holding one PNG image, which every browser since Vista reads. */
function ico(image, size) {
  const header = Buffer.alloc(22)
  header.writeUInt16LE(0, 0) // reserved
  header.writeUInt16LE(1, 2) // type: icon
  header.writeUInt16LE(1, 4) // one image
  header.writeUInt8(size, 6) // width
  header.writeUInt8(size, 7) // height
  header.writeUInt8(0, 8) // no palette
  header.writeUInt8(0, 9) // reserved
  header.writeUInt16LE(1, 10) // colour planes
  header.writeUInt16LE(32, 12) // bits per pixel
  header.writeUInt32LE(image.length, 14)
  header.writeUInt32LE(header.length, 18) // the image follows the header
  return Buffer.concat([header, image])
}

await writeFile(`${statics}img/favicon-96x96.png`, png(96))
await writeFile(`${statics}img/apple-touch-icon.png`, png(180))
await writeFile(`${statics}favicon.ico`, ico(png(48), 48))
