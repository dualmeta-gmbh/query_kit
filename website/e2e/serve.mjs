// The built site, served the way GitHub Pages serves it: a page at its clean
// URL (`/docs/quick-start` → `quick-start.html`), a directory at its trailing
// slash (`/demo/showcase/` → its `index.html`), no redirect between the two,
// and the query string left alone. `docusaurus serve` is not that at the
// root: with `trailingSlash: false` it redirects `/demo/showcase/?embed=1` to
// `/demo/showcase`, dropping the query a framed demo boots from.
import { createServer } from 'node:http'
import { fileURLToPath } from 'node:url'
import handler from 'serve-handler'

const port = Number(process.argv[2] ?? 3100)
const root = fileURLToPath(new URL('../build', import.meta.url))

createServer((request, response) => handler(request, response, { public: root, cleanUrls: true, directoryListing: false })).listen(
  port,
  () => console.log(`serving ${root} at http://localhost:${port}/`),
)
