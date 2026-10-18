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

## What keeps the shared world honest

- A test creates the tasks it acts on, under a `uniqueName`, and never reads
  a name it did not make. The two exceptions are named where they happen: the
  seed's one unsynced task (`synced` is the backend's own field, so no write
  can produce one) and a seeded task whose progress and estimate differ from a
  new task's, whose expectation is read from the backend rather than typed in.
- The sweep that clears a spec's leftovers recognises its own by a name
  suffix of ten or more base-36 characters, and the "New task" button's tasks
  by their fixed name. The first version took seven characters and would have
  removed the seed's "Archive last quarter".
- Every delete-touching test uses the "delete until gone" idiom, so the parity
  counter is reasoned about rather than assumed; the sweep moves it too.
- A test that needs a state the backend cannot be put in without damaging every
  later test fakes the backend's answer in the browser (`route.fulfill`) and
  says so in a comment: a project with nothing in it, a refused reminder write.
- No test asserts on a clock. A request is held and released, and "no request"
  is asserted from a settled state the screen itself proves (the reload button
  is a button again), never after a sleep.

## Consequences

- The suite stays serial. A test added to it must be correct against whatever
  the previous one left on the backend, which is why each starts by creating
  what it needs.
- Two checkouts can serve their builds side by side (`APP_PORT`), but not run
  the suite at the same time: both talk to the backend on 5174, which the web
  build has baked in (`--dart-define=BACKEND=…` would move it, and the specs'
  `BACKEND` constant with it). That was left alone until a second concurrent
  run is a real need.
- If the demo ever does grow scenarios — because a feature needs a failure the
  global counter cannot script — this record is the cost list: the three
  existing tests, the contract test's second dimension, and a `?scenario=`
  boot path in an app that has none.
