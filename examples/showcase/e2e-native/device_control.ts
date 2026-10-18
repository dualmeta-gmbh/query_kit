// What a test running on a simulator cannot do to itself: send its own app to
// the background, cut its own network, turn its own screen. This process runs
// on the host beside the backend and does it on the test's request, over
// plain HTTP on loopback (an Android emulator reaches the host's loopback as
// 10.0.2.2, an iOS simulator shares it).
//
//   GET  /platform                       → { platform, device, appId, loginWindow, ci }  `loginWindow`:
//                                          macOS only, true when the session is at the login
//                                          window (seen on every look for 5 s), so no app can come to the front; `ci`:
//                                          running under GitHub Actions
//   POST /background?ms=                 → { left, back }  background the app, wait, bring it
//                                          back; `left` once it was sent away, `back` as its return
//                                          was asked for: ISO times, as the backend logs them
//   POST /background?ms=&after=          → { ok }  the same trip, `after` ms from answering — for a
//                                          trip the app cannot ask for at the time (airplane mode)
//   POST /network/:mode                  → { mode } up | refuse | blackhole (the proxy below)
//   POST /airplane/on?ms=                → { ok }  Android only: airplane mode on a moment after
//                                          answering, and off again after `ms` — the app cannot ask
//                                          for it to end, its line to this host goes with the radio
//   POST /rotate/:orientation            → { ok }  portrait | landscape, Android only
//   GET  /aborts                         → string[]  requests the app hung up on, as
//                                          `METHOD /path`, oldest first
//   DELETE /aborts                       → { cleared }
//
// The network proxy listens on PROXY_PORT and forwards to the backend on
// BACKEND_PORT. The app under test talks to the proxy, so "the network" is
// something a test can switch: `refuse` closes every new connection at once
// (what an unreachable host looks like), `blackhole` accepts and never
// answers (what a dead link looks like until a timeout fires), and both drop
// the connections already open. `up` forwards again.
//
// The proxy also sees what the app gives up on: a connection the app closes
// while a request on it is still unanswered is a cancel that reached the
// transport — what a browser reports as `requestfailed`, measured here on the
// wire instead.
//
// Configured by the environment, which run.sh sets:
//   PLATFORM  ios | android | macos | linux | web
//   DEVICE    the simulator's udid or the emulator's adb serial (not for web
//             or a desktop: the device is this machine)
//   APP_ID    the bundle id / application id under test

import { execFile } from 'node:child_process'
import { createServer as createHttpServer } from 'node:http'
import { createConnection, createServer as createTcpServer, type Socket } from 'node:net'
import { promisify } from 'node:util'

const run = promisify(execFile)

const platform = process.env.PLATFORM
const device = process.env.DEVICE
const appId = process.env.APP_ID ?? 'io.dualmeta.querykit.showcase'
const controlPort = Number(process.env.CONTROL_PORT ?? 5176)
const proxyPort = Number(process.env.PROXY_PORT ?? 5177)
const backendPort = Number(process.env.BACKEND_PORT ?? 5175)

if (
  !(
    platform === 'web' ||
    platform === 'macos' ||
    platform === 'linux' ||
    ((platform === 'ios' || platform === 'android') && device)
  )
) {
  console.error('device_control: set PLATFORM=ios|android|macos|linux|web, and DEVICE=<udid|serial> for a device')
  process.exit(2)
}

// In a browser there is no device: only the network proxy applies. Nor is
// there on Linux, which runs under a virtual display with no window manager
// to move another window in front.
const deviceOnly = (what: string) => {
  if (platform === 'web') throw new Error(`${what} needs a device, not a browser`)
  if (platform === 'linux') throw new Error(`${what} needs a window manager, which the Linux run has none of`)
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
const adb = (...args: string[]) => run('adb', ['-s', device!, ...args])
const simctl = (...args: string[]) => run('xcrun', ['simctl', ...args])

// --- macOS: which window is in front ------------------------------------------
//
// A desktop app only goes `inactive` when it had the focus to lose, and
// flutter_tools' own attempt to bring a freshly built app forward fails on
// the runner ("Failed to foreground app; open returned 1", #109): the window
// stays behind, Finder coming forward changes nothing, and the trip away
// tests nothing. So the app is made frontmost, and proven so, before it
// leaves; every step and its exit status goes to this process's log.

// One command, its outcome logged. `true` when it exited 0.
async function attempt(label: string, command: string, args: string[]) {
  try {
    const { stdout } = await run(command, args)
    console.log(`device_control: ${label}: ok ${stdout.trim()}`)
    return true
  } catch (error) {
    const { code, stderr } = error as { code?: unknown; stderr?: string }
    console.log(`device_control: ${label}: exit ${String(code)} ${(stderr ?? '').trim()}`)
    return false
  }
}

// The bundle id of the window in front, as Launch Services has it.
async function frontmost() {
  const { stdout: front } = await run('lsappinfo', ['front'])
  const { stdout } = await run('lsappinfo', ['info', '-only', 'bundleid', front.trim()])
  return /"([^"]*)"\s*$/.exec(stdout.trim())?.[1] ?? stdout.trim()
}

// Polls for `bundleId` to be in front, for up to `ms`.
async function waitFront(bundleId: string, ms: number) {
  for (let waited = 0; ; waited += 250) {
    try {
      if ((await frontmost()) === bundleId) return true
    } catch (error) {
      console.log(`device_control: lsappinfo: ${String(error)}`)
    }
    if (waited >= ms) return false
    await sleep(250)
  }
}

// Puts the app under test in front: by id, then by AppleScript, which may ask
// for an automation permission. Each is logged with its exit status. Throws
// when the app is not in front after both, with what is: a case that leaves
// the app proves nothing if the app was never there to leave (#109).
async function bringToFront() {
  if (await waitFront(appId, 0)) return
  const steps: [string, string, string[]][] = [
    ['open -b', 'open', ['-b', appId]],
    ['osascript activate', 'osascript', ['-e', `tell application id "${appId}" to activate`]],
  ]
  for (const [label, command, args] of steps) {
    await attempt(label, command, args)
    if (await waitFront(appId, 4000)) return
  }
  await who()
  throw new Error(`could not bring ${appId} to the front; ${await frontmost().catch(() => '?')} is there`)
}

// What Launch Services and the session look like, for the log.
async function who() {
  await attempt('front is', 'sh', ['-c', 'lsappinfo info -only name,bundleid "$(lsappinfo front)"'])
  await attempt('console', 'stat', ['-f', '%Su', '/dev/console'])
}

// A macOS session that sits at the login window (a CI runner whose screen is
// locked, say) has no app in front and lets none come: the cases that leave
// the app cannot be run there, and the tests skip them. The front app changes
// in the first minute of a session, so one look is not enough: it is the
// login window only if every look, 500 ms apart for up to 5 s, says so (any
// other app in front ends it at once). Asked when the suite starts, with the
// app up, and settled for the run (#109).
let loginWindowAnswer: Promise<boolean> | undefined
function atLoginWindow() {
  if (platform !== 'macos') return Promise.resolve(false)
  loginWindowAnswer ??= (async () => {
    for (let looked = 0; looked <= 5000; looked += 500) {
      if ((await frontmost().catch(() => '')) !== 'com.apple.loginwindow') return false
      if (looked < 5000) await sleep(500)
    }
    console.log('device_control: the macOS session is at the login window; no app can come to the front')
    return true
  })()
  return loginWindowAnswer
}

// --- the app's lifecycle ----------------------------------------------------

async function background(ms: number) {
  // Taken before the return is asked for: the command that brings the app
  // back returns only once it is in front, and by then it may have fetched.
  let left: string
  let back: string
  if (platform === 'ios') {
    // Opening another app is the one way simctl has to move ours off screen;
    // launching ours again brings the running process back, not a new one.
    await simctl('launch', device!, 'com.apple.Preferences')
    left = new Date().toISOString()
    await sleep(ms)
    back = new Date().toISOString()
    await simctl('launch', device!, appId)
  } else if (platform === 'macos') {
    // Another app to the front: the window loses focus, which on a desktop
    // is what `inactive` means — if it had the focus. So the app is first
    // put in front, and proven to be (#109).
    await bringToFront()
    // Finder is in front once it is asked for, if it can be.
    if (!(await attempt('open -a Finder', 'open', ['-a', 'Finder']))) {
      await attempt('Finder activate', 'osascript', ['-e', 'tell application "Finder" to activate'])
    }
    left = new Date().toISOString()
    console.log(`device_control: away; in front: ${await frontmost().catch(() => '?')}`)
    await sleep(ms)
    back = new Date().toISOString()
    // `open -b` on a running app activates it; `bringToFront` falls back
    // when it does not, and proves the window is there.
    await bringToFront()
  } else {
    await adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    left = new Date().toISOString()
    await sleep(ms)
    back = new Date().toISOString()
    // The launcher intent, as a tap on the icon sends it: with the activity's
    // `singleTop` launch mode it resumes the running task.
    await adb('shell', 'monkey', '-p', appId, '-c', 'android.intent.category.LAUNCHER', '1')
  }
  return { left, back }
}

// --- Android-only device state ----------------------------------------------

async function airplane(on: boolean) {
  await adb('shell', 'cmd', 'connectivity', 'airplane-mode', on ? 'enable' : 'disable')
}

async function rotate(orientation: 'portrait' | 'landscape') {
  await adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
  await adb('shell', 'settings', 'put', 'system', 'user_rotation', orientation === 'portrait' ? '0' : '1')
}

// --- the network, as a proxy ------------------------------------------------

type Mode = 'up' | 'refuse' | 'blackhole'
let mode: Mode = 'up'
const open = new Set<Socket>()
// Closed by this process rather than by the app: not a cancel.
const closedHere = new WeakSet<Socket>()
let aborts: string[] = []

function dropAll() {
  for (const socket of open) {
    closedHere.add(socket)
    socket.destroy()
  }
  open.clear()
}

// `GET /api/posts?delay=3000 HTTP/1.1` → `GET /api/posts`
const requestLine = (chunk: Buffer) => {
  const match = /^([A-Z]+) ([^ ?]+)/.exec(chunk.toString('latin1', 0, 512))
  return match ? `${match[1]} ${match[2]}` : null
}

createTcpServer((client) => {
  if (mode === 'refuse') {
    client.destroy()
    return
  }
  open.add(client)
  // The request on this connection that has not been answered yet. A
  // keep-alive connection carries one after the other.
  let unanswered: string | null = null
  client.on('data', (chunk: Buffer) => {
    unanswered = requestLine(chunk) ?? unanswered
  })
  client.on('close', () => {
    open.delete(client)
    if (unanswered !== null && !closedHere.has(client)) aborts.push(unanswered)
  })
  client.on('error', () => client.destroy())
  if (mode === 'blackhole') return
  const upstream = createConnection({ host: '127.0.0.1', port: backendPort })
  open.add(upstream)
  upstream.on('data', () => {
    unanswered = null
  })
  upstream.on('close', () => {
    open.delete(upstream)
    closedHere.add(client)
    client.destroy()
  })
  upstream.on('error', () => {
    closedHere.add(client)
    client.destroy()
  })
  client.on('close', () => upstream.destroy())
  client.pipe(upstream).pipe(client)
}).listen(proxyPort, '127.0.0.1')

// --- the control endpoint ---------------------------------------------------

// A refusal the caller can tell from a failure: 409 with this body.
class Conflict extends Error {
  body: object
  constructor(body: object) {
    super(JSON.stringify(body))
    this.body = body
  }
}

const routes: Record<string, (url: URL, parts: string[]) => Promise<unknown>> = {
  'GET platform': async () => ({ platform, device, appId, loginWindow: await atLoginWindow(), ci: process.env.GITHUB_ACTIONS === 'true' }),
  'POST background': async (url) => {
    deviceOnly('background')
    if (await atLoginWindow()) throw new Conflict({ loginWindow: true, message: 'the macOS session is at the login window; no app can come to the front' })
    const ms = Number(url.searchParams.get('ms') ?? 2000)
    const after = url.searchParams.get('after')
    if (after === null) return background(ms)
    setTimeout(() => background(ms).catch((error) => console.error('background failed', error)), Number(after))
    return { ok: true }
  },
  'POST network': async (_, [next]) => {
    if (next !== 'up' && next !== 'refuse' && next !== 'blackhole') throw new Error(`unknown mode ${next}`)
    mode = next
    if (next !== 'up') dropAll()
    return { mode }
  },
  'GET aborts': async () => aborts,
  'DELETE aborts': async () => {
    const cleared = aborts.length
    aborts = []
    return { cleared }
  },
  'POST airplane': async (url, [state]) => {
    if (platform !== 'android') throw new Error('airplane mode is Android only')
    if (state !== 'on') throw new Error('airplane mode ends by itself: POST /airplane/on?ms=')
    const ms = Number(url.searchParams.get('ms') ?? 10000)
    // After this answer is on its way, and back off from here.
    setTimeout(() => {
      airplane(true)
        .then(() => sleep(ms))
        .finally(() => airplane(false).catch((error) => console.error('airplane off failed', error)))
        .catch((error) => console.error('airplane on failed', error))
    }, 300)
    return { ok: true }
  },
  'POST rotate': async (_, [orientation]) => {
    if (platform !== 'android') throw new Error('rotation is Android only')
    if (orientation !== 'portrait' && orientation !== 'landscape') throw new Error(`unknown orientation ${orientation}`)
    await rotate(orientation)
    return { ok: true }
  },
}

createHttpServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://localhost')
  const [name, ...parts] = url.pathname.split('/').filter(Boolean)
  const handler = routes[`${request.method} ${name}`]
  response.setHeader('content-type', 'application/json')
  // The web run calls this from the app's origin.
  response.setHeader('access-control-allow-origin', '*')
  response.setHeader('access-control-allow-methods', 'GET, POST, DELETE, OPTIONS')
  response.setHeader('access-control-allow-headers', 'content-type')
  if (request.method === 'OPTIONS') {
    response.statusCode = 204
    response.end()
    return
  }
  if (!handler) {
    response.statusCode = 404
    response.end(JSON.stringify({ message: `no route ${request.method} ${url.pathname}` }))
    return
  }
  try {
    response.end(JSON.stringify(await handler(url, parts)))
  } catch (error) {
    console.log(`device_control: ${request.method} ${url.pathname} failed: ${String(error)}`)
    response.statusCode = error instanceof Conflict ? 409 : 500
    response.end(JSON.stringify(error instanceof Conflict ? error.body : { message: String(error) }))
  }
}).listen(controlPort, '127.0.0.1', () => {
  console.log(`device_control: ${platform} ${device}, control :${controlPort}, proxy :${proxyPort} → :${backendPort}`)
})
