# Porting notes — query_kit_hooks

What this file is: the audit trail behind the hooks package's claim —
*React Query's hooks, proven by React Query's own hook tests*. Every upstream
case in a ported suite is accounted for here as **ported**, **adapted** (with
why), or **omitted** (with which category it falls in). A gap that is not
listed is a bug in this file. The core's notes
(`packages/query_kit/test/PORTING_NOTES.md`) are the model, and their rules
hold here unchanged.

- **Upstream revision:** `50680b98c` (`main`, 2026-09-08), the core's pin.
- **The plan:** `docs/plans/hooks-package.md` (map #92). Its decisions are
  cited as D1–D18; ADR-0004 holds the two that last.
- **The inventory:** `docs/research/react-query-hook-tests-inventory.md`
  classified every upstream case by reading, before anything was ported. A
  verdict there is a hypothesis; where a port proved one wrong, the suite's
  section says so.
- One Dart file per upstream file, upstream test names kept verbatim, each
  case's upstream line in the comment above it, and upstream's `describe`
  nesting kept as `group`s. A failing ported case means the hook is wrong
  until shown otherwise. **One exception to the file rule:**
  `useQuery.test.tsx` is 7096 lines, so it is two Dart files, split at line
  3600 as the inventory is.
- **The counting rule is the core's:** one upstream case is one `it`
  declaration.

## What may change an assertion

Three decisions of the plan, and nothing else (D16). Every changed assertion
has a row below that names which one.

- **D8, the frame.** React renders after every timer in a fake-timer test;
  Flutter builds once per frame for every notification before it. The
  harness's `advance(ms)` steps one frame per millisecond, which makes the
  two agree almost everywhere. Where a build count or a sequence of builds
  still differs, the case keeps upstream's sequence as an assertion on what
  the observer **delivered** (the harness's `Recorder`, below), and only the
  count of builds changes.
- **D10, `CombinedResult`.** `useCombinedQueries` returns a
  `CombinedResult`, which stays pending until every source has data.
- **D14, out of scope.** Suspense, error boundaries and `throwOnError`,
  hydration and `isRestoring`, `subscribed`, `skipToken`, `retryOnMount` as a
  callback, a raw `combine`, mutation callback context. A case built on one
  of these is omitted, and a case that only touches one keeps the rest.

Spelling is not an adaptation. Upstream's `toEqual` over a whole result is a
matcher per field; `error: null` is `errorOrNull`; a timestamp of `0` is
`null` (`DateTime?`); `retry: 1` is `RetryPolicy.times(1)`;
`notifyOnChangeProps: 'all'` is dropped, because notifying on every change is
what every call style does. A case changed only in spelling is **ported**.

## The harness

`test/harness.dart`, shared by every file:

- **`hookTest`** — `testWidgets` with a `QueryClient` per case and the
  teardown of ADR-0002.
- **`HookBuilder`** — `flutter_hooks`' own, as upstream's
  `function Page() { … }` (D16). The spike's hand-written probe is gone.
- **`Recorder<T>`** — upstream's `states`, and beside it what a frame can
  hide (D8, Astra H-02). `builds` is one entry per build, which is what
  `states.push(state)` records. `delivered` is every result the observer
  handed the hook that differed from the one on screen. It is recorded by a
  `buildWhen` that always says yes, which is what no `buildWhen` does, so
  recording changes no build.
- **`advance(tester, ms)`** — upstream's `vi.advanceTimersByTimeAsync(ms)`
  (D8). It builds one frame before any time passes, for what microtasks
  already raised, as React's `act` renders before the first timer. Then it
  builds one frame per millisecond. **`click`** is a tap and its frame.
  **`focusWindow`** is a focus event and its frame.
- **`afterFrame(fn)`** — upstream's `setState` inside a `useEffect`.
  `flutter_hooks` runs an effect inside `build`, where a state change to the
  element being built is dropped, so it lands after the frame.
- **`timersCreatedBy(body)`** — upstream's `vi.spyOn(window, 'setTimeout')`,
  a zone `createTimer` spy.
- `queryKey()`, `sleep(ms)`, `prefetch(client, options)`,
  `observersOf(client, key)`, `Blink`.

## Status

| Upstream suite | Dart file | Cases | State |
|---|---|---|---|
| `useQuery.test.tsx`, lines 1–3600 | `use_query_part1_test.dart` | 72 / 78 | done (AP3) |
| `useQuery.test.tsx`, lines 3601–7096 | `use_query_part2_test.dart` | 61 / 77 | done (AP3) |
| `useInfiniteQuery.test.tsx` | `use_infinite_query_test.dart` | 2 / 28 | spike selection; AP4 |
| `useMutation.test.tsx` | `use_mutation_test.dart` | 3 / 61 | spike selection; AP5 |
| `useQueries.test.tsx` | `use_queries_test.dart` | 3 / 24 | spike selection; AP6 |
| `useIsFetching.test.tsx` | `use_is_fetching_test.dart` | 1 / 5 | spike selection; AP7 |
| `useMutationState.test.tsx` | `use_mutation_state_test.dart` | 1 / 5 | spike selection; AP7 |

`useQuery.test.tsx` is accounted for in full. The other rows are still the
spike's selection (AP0, `docs/research/hooks-spike.md`); each later ticket
accounts for its suite in full.

### The package's own files

They count in no column above.

- `hook_specifics_test.dart` — what upstream's suites cannot say: Flutter's
  element lifecycle (unmount, a `GlobalKey` move), the client a hook resolves,
  and `flutter_hooks`' rules. D13's consequences are pinned here: a throw
  inside a hook, between hooks and after the last, each with a fetch in
  flight in every hook whose query function consumed its signal, so what is
  cancelled is what was disposed.
- `review_reproductions_test.dart` — one case per finding of the plan's
  review round (Astra, Fable) that was reproduced as a test, H-01, H-03,
  H-04 and P2-1 among them; the plan's last section is their record.

## `useQuery.test.tsx`

**155 upstream cases: 122 ported, 11 adapted, 22 omitted (AP3, #96).** Every
case not listed below is **ported**: upstream's scenario and assertions, in
Dart spelling. Upstream's nested `describe`s are `group`s:
`notifyOnChangeProps` › `function` in part 1, and the three `networkMode`
groups in part 2. No case carries a skip, and the port found no defect in the
hooks, the binding or the core.

### Adapted (11)

| Line | Case | What changed, and why |
|---|---|---|
| 507 | should not get into an infinite loop when removing a query with gcTime 0 and rerendering | `notifyOnChangeProps: ['isPending', 'isSuccess', 'data']` is a `buildWhen` over the same three fields (#15, plan gap table). No assertion changed |
| 738 | should track properties and only re-render when a tracked property changes | Tracked props, reading only `data`, become a `buildWhen` on `dataOrNull` (#15, gap table). No assertion changed |
| 2016 | notifyOnChangeProps › should not re-render when it should only re-render only data change and the selected data did not change | `notifyOnChangeProps: ['data']` is a `buildWhen` on `dataOrNull` (#15, gap table). No assertion changed |
| 2055 | notifyOnChangeProps › should not re-render when it should only re-render on data changes and the data did not change | As 2016 |
| 2109 | notifyOnChangeProps › function › should not re-render when it should only re-render on data changes and the data did not change | The function form is the same `buildWhen` predicate. No assertion changed |
| 2159 | notifyOnChangeProps › function › should not re-render when change props are not actively being tracked | The callback that answers from a ref is a `useCallback` `buildWhen` that answers from a `useRef` flag. Builds 2, 2, 4 as upstream; `delivered` holds all five observer transitions in upstream's order |
| 4189 | should accept an empty string as query key | **Strengthened, not under D8/D10/D14.** Upstream's `getByText('')` matches an element with no text before and after the fetch, so it checks nothing. The port asserts what the sibling case 4204 asserts for its key: the data's JSON, `[""]`. The inventory prescribed this |
| 4291 | should use placeholder data even for disabled queries | **D8, a build count of 3 becomes 2.** The effect's `setCount(1)` lands after the first frame (`afterFrame`), and the synchronous query function's data lands before the next frame, so upstream's `states[1]` (placeholder, count 1) and `states[2]` (data, count 1) are one build. `delivered` is `[data]`: the observer's own sequence, placeholder then data, is upstream's. The lost render was a `setCount` render, not a delivery, so no list of deliveries can hold it in either framework. A delay in the query function would keep three builds, but it would change the case |
| 4912 | should hash query keys that contain bigints given a supported query hash function | D14: there is no `queryKeyHashFn`, because keys compare by `==`. `getQueryCache().get(queryKeyHashFn(key))` becomes `queryCache.find` with an equal key built anew (`BigInt.from(1)`). The asserted value, `'test'`, is unchanged |
| 6495 | should respect skipToken and refetch when skipToken is taken away | D14: `queryFn: enabled ? fn : skipToken` becomes a fixed `queryFn` with `enabled: enabled ? Enabled.yes : Enabled.no`, the spelling the core documents for `skipToken`. The assertions are unchanged |
| 7004 | should not call retryOnMount callback when the query has data | D14 and the gap table: `expect(retryOnMount).not.toHaveBeenCalled()` is omitted, because the core's `retryOnMount` is a `bool?`, and `retryOnMount: false` stands in. The rest, a remount with data refetching to three `queryFn` calls, is ported under upstream's name |

A constant `retryOnMount: () => false` is spelled `retryOnMount: false`
(4935, 4996, 5056, 6068, 6495). Only 6973 and 7004 inspect or count the
callback's calls.

### Omitted (22)

| Lines | Category | Why |
|---|---|---|
| 2751, 2785, 2814, 2841, 2873, 6805, 6851, 6923 | `throwOnError` and error boundaries (D14) | #15: errors are data in the result. 2785 also throws a falsy value, which Dart cannot do. 6805's and 6923's leftover, `retryOnMount: true` refetching an errored query on remount, is not ported on its own |
| 5921, 5966, 6002, 6031 | `subscribed` (D14) | Binding backlog HB-1, for all call styles at once |
| 6539 | `skipToken` (D14) | With `Enabled.yes` and no `queryFn`, the core fails with `MissingQueryFunctionError` instead of staying `pending`/`idle`. `Enabled.no` serves the purpose, as 6495 shows |
| 6786 | missing-`queryFn` warning (D14) | The core fails the fetch with `MissingQueryFunctionError`; asserting that would be a different test |
| 6973 | `retryOnMount` as a callback (D14) | The core option is `bool?` |
| 7054 | `isRestoring` (D14) | No persister and no `IsRestoringProvider` (#15) |
| 6669, 6721 | hydration (D14) | No `dehydrate`/`hydrate` |
| 4885 | no `queryKeyHashFn` | `QueryKey` compares by `==` and `hashCode`, so there is no hash function to count |
| 2344, 6358 | React rendering | 2344 guards React's same-state bail-out under `useSyncExternalStore`. 6358 needs ref callbacks, which Flutter does not have |
| 6475 | TypeScript | A dynamic argument check that Dart's static types make impossible |

### What the port measured

- **The frame (D8).** One build count changed: 4291's. A second merge, in 159, came from `advance` itself. Its first 1 ms step ran a microtask's delivery (failure 1) and a 1 ms retry's failure in one frame, and React renders the microtask's state before the first timer. `advance` now builds a frame before any time passes. With that, 159 keeps upstream's three builds, and no other count in the package changed (160 of 160 before and after). Every other render-count assertion in the file held as upstream wrote it, including 4100's six states in 51 ms, 4688's key flips, 5186's `[paused, fetching, idle]` and 6378's seven states.
- **The inventory was too cautious.** It marked 43 cases A, and 38 of them are plain ports here: every one except 507, 4189, 4291, 4912 and 6495.
  - By its own legend, every count assertion is A. The stepped `advance` holds every count it feared for.
  - `afterFrame` and `Object` typing under one key are driver mappings, not changed assertions.
  - Its risks for 4447 (`select` twice) and 6378 (an extra state) did not happen.
  - Every P verdict passed as written.
- **Two inventory notes were wrong.**
  - 3968/3991: "Dart has no `setTimeout` spy." It has one: a zone `createTimer` spy around the unmount (`timersCreatedBy`) sees the 10-minute gc timer last. So both keep upstream's own assertion, not a behavioural stand-in.
  - 5546: "reading `ctx.signal` is why the paused fetch is cancelled." Upstream's `removeObserver` (`query.ts:532–537`) cancels a paused pending fetch with a revert whether or not the signal was read. The case passes without the read, which stays only to mirror upstream's destructuring.
- **The suite has teeth.** Three faults were put into `controller_hook.dart` and the two files run against each:
  - With the rebuild rule ignored (every delivery rebuilds), 18 of 133 go red.
  - With `setOptions` skipped on later builds, 26 go red.
  - With the controller left undisposed, none go red. When a hook's listener goes, the binding's `ControllerLifetime` already unsubscribes the observer. `hook_specifics_test.dart` catches that fault.
