---
status: accepted
date: 2026-10-18
ticket: https://github.com/dualmeta-gmbh/query_kit/issues/80
---

# The task manager's backend stays single-world

The showcase's backend is a catalogue's: every end-to-end test names a
scenario in an `x-scenario` header and gets a world of its own, so the suite
runs in parallel and nothing one test does is visible to another. The task
manager's backend has one world per process, a process-global
`removeAttempts` that makes every second delete fail, and a Playwright suite
that runs one test at a time. Phase 9 of map #70 took that suite from 10
tests to 26, and the obvious question was whether the task manager should get
the showcase's scenarios first. It should not, and a later agent who reads
`workers: 1` next to the showcase's `fullyParallel: true` will ask it again.

(The ticket called this ADR-0003. That number was taken in the meantime by
[the core operation lifetimes](0003-core-operation-lifetimes.md), and 0004 and
0005 since.)

## Decision

The backend stays single-world: no `x-scenario`, no per-test state, one
worker. What was bought instead is an `APP_PORT` environment variable in
`e2e/playwright.config.ts`, the showcase's own escape hatch, so that two
checkouts can serve their own web build side by side.

## Why isolating would not pay

1. **The shared counter is the demo's scripted failure.** *"Every second
   delete fails, odd attempts first … deterministic, so the demo needs no
   magic names"* is what the README tells a reader to try. Per-scenario
   counters change the behaviour three existing tests are written against,
   among them the one whose comment reasons about "whatever the count stands
   at".
2. **It would change the demo to serve its own tests.** Scenarios mean porting
   `scenarios.ts` (106 lines), threading a header through `lib/src/api.dart`
   and adding a `?scenario=` boot path to the application. The task manager is
   one ordinary app, and that is the point of it. The showcase is a catalogue
   built to be tested; this is not.
3. **The contract test would grow a dimension.** The 15-case
   `backend_contract_test.dart` runs one list of cases against the fake and
   the real server. A scenario would have to be added to both sides, for no
   gain a user of the app can see.
4. **The wall clock barely moves.** Twenty-six tests at one worker against a
   backend that answers a list in 900 ms take a few minutes, and the `e2e` job
   already runs the two apps in parallel.

## An alternative weighed: a reset endpoint

The cheaper cousin of scenarios is a server-side reset: one process, one
world, but a `POST /api/__reset` (or a reset header) that puts the seed and the
delete counter back before each test, so the suite needs neither unique names
nor a sweep nor a tall viewport. The demo app would not change, since the
endpoint is the server's and no screen calls it. It was not chosen, for three
reasons, none of them decisive alone:

- It does not make the suite parallel, which was the showcase's gain from
  scenarios; a reset between tests only makes the serial order irrelevant.
- It makes the server a fixture. The server README tells a reader it is the
  backend the app talks to, and an unauthenticated route that rewrites its
  data is what the loopback-only default (SEC-2) exists to keep off a network.
  The showcase accepts that for a test server; this one is also what a reader
  runs by hand.
- Resetting the counter makes "whatever the count stands at" untestable: the
  existing delete test's point is that it holds from any parity, and a reset
  would hide a spec that only works from zero.

It is the first thing to build if the suite's discipline below starts to cost
more than it saves: a spec that cannot be written without it, or a leftover
that keeps breaking another.

## What keeps the shared world honest

- A test creates the tasks it acts on, under a `uniqueName`, and does not read
  one it did not make. The exceptions are not few, and they rely on the seed
  in `server/db.ts`: the unsynced "Archive last quarter" (`synced` is the
  backend's own field, so no write can produce one); "Write the release notes"
  as a task whose progress and estimate are not a new task's, with the
  expectation read from the backend; the same task as the row that must
  disappear once a search has narrowed the list; and every project in the
  dropdown (Admin, Website, Errands) having a task, which is also why an empty
  project cannot be had without faking the answer. Changing the seed means
  reading these specs.
- The sweep that clears a spec's leftovers recognises its own by a name
  suffix of ten or more base-36 characters, and the "New task" button's tasks
  by their fixed name. The first version took seven characters and would have
  removed the seed's "Archive last quarter".
- The delete counter is reasoned about, not assumed: the one test that
  exercises the scripted failure uses the "delete until gone" idiom, and the
  sweep (which deletes through the API, twice per task) tolerates any parity.
  No other spec deletes through the app.
- A test that needs a state the backend cannot be put in without damaging every
  later test fakes the backend's answer in the browser (`route.fulfill`,
  `route.abort`) and says so in a comment: a project with nothing in it, a
  refused reminder write.
- No test asserts on a clock. A request is held and released, and "no request"
  is asserted from a settled state the screen itself proves (the reload button
  is pressable again), never after a sleep. (Three older specs in
  `tasks.spec.ts` still wait a fixed time before counting; none is new.)

## Consequences

- The suite stays serial. A test added to it must be correct against whatever
  the previous one left on the backend, which is why each starts by creating
  what it needs.
- Two checkouts can serve their builds side by side (`APP_PORT`), but not run
  the suite at the same time: both talk to the backend on 5174, which the web
  build has baked in (`--dart-define=BACKEND=…` would move it, and the specs'
  `BACKEND` constant with it). That was left alone until a second concurrent
  run is a real need.
- What a locked control looks like in the semantics tree differs between
  Flutter versions, so the specs read locks through `flt-tappable` and always
  beside its presence on the unlocked node (see PORTING_NOTES, Phase 9).
- If the demo ever does grow scenarios — because a feature needs a failure the
  global counter cannot script — this record is the cost list: the three
  existing tests, the contract test's second dimension, and a `?scenario=`
  boot path in an app that has none.
