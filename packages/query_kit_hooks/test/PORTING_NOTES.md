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
  the hook's controller **delivered** (the harness's `Recorder`, below), and
  only the count of builds changes.
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
  `states.push(state)` records. `delivered` is every result the hook's
  controller delivered that differed from the one on screen. It is recorded
  by a `buildWhen` that always says yes, which is what no `buildWhen` does,
  so recording changes no build. A delivery reads the observer's current
  result once per notification flush, so two results raised inside one
  `notifyManager.batch` arrive as the last of them. React renders such a
  batch once too, so neither list holds a state that lives only inside one
  batch.
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
| `useQuery.test.tsx`, lines 3601–7096 | `use_query_part2_test.dart` | 63 / 77 | done (AP3) |
| `useInfiniteQuery.test.tsx` | `use_infinite_query_test.dart` | 2 / 28 | spike selection; AP4 |
| `useMutation.test.tsx` | `use_mutation_test.dart` | 3 / 61 | spike selection; AP5 |
| `useQueries.test.tsx` | `use_queries_test.dart` | 17 / 24 | done (AP6) |
| `useIsFetching.test.tsx` | `use_is_fetching_test.dart` | 1 / 5 | spike selection; AP7 |
| `useMutationState.test.tsx` | `use_mutation_state_test.dart` | 1 / 5 | spike selection; AP7 |
| `usePrefetchQuery.test.tsx` | `use_prefetch_query_test.dart` | 4 / 6 | done (AP8) |
| `usePrefetchInfiniteQuery.test.tsx` | `use_prefetch_infinite_query_test.dart` | 2 / 3 | done (AP8) |

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

**155 upstream cases: 122 ported, 13 adapted, 20 omitted (AP3, #96).** Every
case not listed below is **ported**: upstream's scenario and assertions, in
Dart spelling. Upstream's nested `describe`s are `group`s:
`notifyOnChangeProps` › `function` in part 1, and the three `networkMode`
groups in part 2. No case carries a skip, and the port found no defect in the
hooks, the binding or the core.

### Adapted (13)

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
| 6805 | should retry on mount when throwOnError returns false | D14: `throwOnError: () => false` is dropped, because errors are data in the result, which is what `false` asks for. The constant `retryOnMount: () => true` is `true`. The assertions are unchanged. Omitted at first; the second review (S-2) showed its remainder ports |
| 6923 | should handle throwOnError function based on actual error state | D14: `throwOnError: (error) => error.message.includes('404')` is dropped. For this case's 500 it answers `false`, so the case is 6805's again with a `bool` `retryOnMount`. The assertions are unchanged. Omitted at first, as 6805 |
| 7004 | should not call retryOnMount callback when the query has data | D14 and the gap table: `expect(retryOnMount).not.toHaveBeenCalled()` is omitted, because the core's `retryOnMount` is a `bool?`, and `retryOnMount: false` stands in. The rest, a remount with data refetching to three `queryFn` calls, is ported under upstream's name |

A constant `retryOnMount: () => false` is spelled `retryOnMount: false`
(4935, 4996, 5056, 6068, 6495). Only 6973 and 7004 inspect or count the
callback's calls.

### Omitted (20)

| Lines | Category | Why |
|---|---|---|
| 2751, 2785, 2814, 2841, 2873, 6851 | `throwOnError` and error boundaries (D14) | #15: errors are data in the result. 2785 also throws a falsy value, which Dart cannot do. 6851 asserts that a throwing `throwOnError` stops the remount's retry, which needs the boundary |
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

### Second review

GPT-6.1-Sol (reasoning effort xhigh) read the two AP3 commits against upstream, the plan and the notes above, with the snapshot to run in. It compared all 133 cases with upstream and found no assertion changed among the 122 ported. Three findings, each reproduced before anything changed:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | `delivered` is not "every result the observer handed the hook". The controller reads the observer's current result once per notification flush, so two results raised in one `notifyManager.batch` arrive as the last of them | Yes: the observer saw `[1, 2]`, `delivered` held `[2]` | A wording defect, not a hole. React renders such a batch once too, so no case relied on the stronger claim. The harness and this file say what `delivered` is. `advance`'s "every timer gets its own frame" was too strong in the same way: timers due in the same millisecond share one |
| S-2 (P2) | 6805 and 6923 were omitted whole, though only their `throwOnError` is out of scope | Yes: the remount refetches the errored query, two calls | Both ported as adapted (D14). The useQuery count is now 122 ported, 13 adapted, 20 omitted |
| S-3 (P3) | `controller_hook.dart` carried the plan's decision ids in `///`, and the jargon scan did not know them | Yes | Moved to `//` |

Sol's sparring agreed with the recorder, the split, the omissions other than S-2 and the constant-callback spelling. It held that `advance`'s leading frame maps the driver for 159 but proves no general equivalence of frame cadence, which is all the notes claim.

## `useQueries.test.tsx`

**24 upstream cases: 4 ported, 13 adapted, 7 omitted (AP6, #99).** Upstream's `combine` option is `useCombinedQueries` (D10): a `CombinedResult` that stays pending until every source has data, a combiner over the values, and `keys:` where upstream wraps the combiner in `useCallback`. Pages that pass their own client run without a provider, as upstream's `render(<Page />)` does, which takes both hooks down the provider-less delivery path. No case carries a skip, and the port found no defect in the hooks, the binding or the core.

### Adapted (13)

| Line | Case | What changed, and why |
|---|---|---|
| 94 | should track results | **D8, a build count of 3 becomes 4.** `useQueries` takes no `buildWhen`, as `QueriesBuilder` takes none, so upstream's tracked properties have no stand-in, and the refetch's fetching state gets a build of its own. That extra build is asserted as what it is (fetching, data 1); upstream's `results[2]` is `results[3]` |
| 337 | should combine queries | D10: the `combine` becomes `useCombinedQueries`, the combiner returning a record `(combined, res)`. No assertion changed |
| 381 | should not return new instances when called without queries | D10: `useCombinedQueries` over an empty list. The effect is keyed on the `CombinedResult`, which compares by value where upstream keys on the identity of a structurally shared object. No assertion changed |
| 434 | should not have infinite render loops with empty queries (#6645) | **Strengthened, by D8's frame.** React's `render` flushes a render loop before it returns; a Flutter loop shows only in later frames. So the count of 1 is asserted again after `advance(0)`, and upstream's assertion stays where it was |
| 454 | should only call combine with query results | D10: the combiner gets values, so `values[0]` and `values[1]` stand in for upstream's destructured results. No assertion changed |
| 490 | should track property access through combine function | **D10, partial (gap table).** Upstream's first three renders (empty, partial, complete) are two here, pending then complete, so `results.length` 3 becomes 2 and its three `toStrictEqual` become `CombinedPending` and the data. The tracked properties are a `buildWhen` on `dataOrNull`. From there on everything is upstream's: `[4, 5, 6]` contains the count (measured 4), the last result holds the new data, and a same-data refetch adds no build |
| 589 | should synchronously track properties of all observer even if a property (isLoading) is only accessed on one observer (#7000) | D14, a raw `combine`: upstream's reads `isLoading` on the raw results, which a `CombinedResult` does not carry. Its body runs in build over `useQueries`. Through `useCombinedQueries`, source 2's failure would make the result an error, and "loaded" would show for that reason instead of the tracked `isLoading`. No assertion changed |
| 630 | should not have stale closures with combine (#6648) | D10: the combiner's capture `count` goes into `keys: [count]`, where React re-runs an inline combine on every render. No assertion changed |
| 674 | should optimize combine if it is a stable reference | **D10: combiner call counts 3/3/4/7 become 1/1/1/3.** The combiner skips pending sources, a same-value refetch adds no call (upstream's invariant), a rebuild adds none (`keys: const []`; upstream's extra call on rerender does not happen), and each source that resolves with a new value adds one |
| 753 | should re-run combine if the functional reference changes | **D10: counts 3 → 4 become 1 → 2.** `useCallback(fn, [state])` is `keys: [state]` |
| 871 | should re-render once combine returns a different reference | D10: upstream's combiner returns `'pending'` while a source is pending; here that is `CombinedPending`, and the combiner runs once every source has data. No assertion changed (2 renders) |
| 926 | should track properties correctly with combine | D10: `'pending'` from the combiner is `CombinedPending`. No assertion changed |
| 993 | should not re-run stable combine on unrelated re-render | **D10: counts 3/3/3 become 1/1/1.** The combiner skips pending sources; upstream's invariant, no call for an unrelated rebuild, holds |

The ported four: 25 keeps upstream's three builds over the stepped `advance(201)`; 309 passes `client:` with no provider; 1070 keeps its list in `useState`; 1142's identity `combine` is plain `useQueries`, so dropping it is spelling, and the length is asserted on every build.

### Omitted (7)

| Lines | Category | Why |
|---|---|---|
| 66 | `subscribed` (D14) | Binding backlog HB-1 |
| 142, 208, 276 | `throwOnError` and error boundaries (D14) | Errors are data in the result. 276 also throws a falsy error, which Dart cannot do |
| 817 | a raw `combine` (D14, #82) | The combiner returns `'foo'` on the first render. A `CombinedResult` is pending first, so the case would need two builds where upstream asserts one |
| 1195, 1251 | `isRestoring` (D14) | No persister |

### What the port measured

- **The inventory was too cautious again.** 25 and 1070, marked A, are plain ports. Its predicted counts for 674 (1/1/1/2) are wrong: the second refetch brings new values for both sources, at 10 and 20 ms, which is two combiner runs, so 1/1/1/3.
- **The acceptance criteria** live in `hook_specifics_test.dart`, group "AP6": a source change that leaves the combination equal adds no build (and one the combiner reads adds exactly one); a change only in what `retry` acts on adds one build, both as H-01 in `review_reproductions_test.dart` and as a repaired refetch error behind equal data; and that change does not ask `buildWhen`.
- **The suite has teeth.** Four faults put into `use_queries.dart`, over the port, the AP6 group and `review_reproductions_test.dart` (37 tests): the combined gate on the value alone turns 3 red, no `setQueries` on later builds 2, the combiner's `keys` ignored 2, the gate ignored 3. Under the last, no plain-`useQueries` case goes red: `QueriesController`'s own `NotifyGate` already drops a notification that carries nothing.

### Second review

GPT-6.1-Sol (xhigh) compared all 17 Dart cases with upstream, found no unsupported weakening, and agreed with the accounting. Three findings, each reproduced:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | A `buildWhen` that declines a value change made together with a change in what `retry` acts on keeps the stale `retry`, which then refetched a repaired query. The porting agent had found the same and left it as the specified rule | Yes: fetches (3, 2) where (3, 1) is right | The rule's, not the hook's: `RebuildRule` asks `buildWhen` whenever the value moved, so a predicate that never sees the half beside the value could still veto it. The AP4 review found the same for an infinite query's paging flags, and the binding's own builders share it. Worked in its own commit, in the binding |
| S-2 (P2) | A combiner that throws on delivered data threw in the listener, where `notifyListeners` reported it and built nothing: the widget stayed pending, the hook subscribed | Yes | `ControllerHookState` builds when reading the value throws, so the build throws it again where Flutter reports a build's errors and D13 disposes the hook, as upstream's render would throw. A case in the AP6 group |
| S-3 (P2) | This file had no AP6 section | — | This section; the porting agent's notes were outside the repository by design |

Sol's sparring agreed with 589, the provider-less pages, `keys:` for `useCallback`, 490's partial port and the extra H-01 angles. It disagreed on 94: a list-level `buildWhen` could compare data without knowing which query moved, so the build count is a missing capability rather than the frame. Kept: `QueriesBuilder` takes no `buildWhen` either, and a list predicate would be new API in both packages; it is a candidate for the binding's backlog. On 434 it asked that the strengthening cite the decision whose gap it closes, which the row above now does.

## `usePrefetchQuery.test.tsx` and `usePrefetchInfiniteQuery.test.tsx`

**9 upstream cases (6 and 3): 6 adapted, 3 omitted (AP8, #101).** Every upstream case reads through `useSuspenseQuery` or `useSuspenseInfiniteQuery` inside a `React.Suspense`. The port translates that one way for all of them: the reader is `useQuery` or `useInfiniteQuery` over a file-private `suspense(options)`, which puts on the options what upstream's suspense hooks put there — `ensureSuspenseTimers` raises `staleTime` to at least 1000 ms, `ensurePreventErrorBoundaryRetry` sets `retryOnMount: false`. The reader's pending branch is the suspense fallback, its error branch the boundary's. The prefetch hook gets upstream's options as written, without the floor: with the floor on its options too, `client.query` would skip fresh data with no lookup in the hook, and 66 and 88 would pass with the lookup removed. No case carries a skip, and the port found no defect.

### Adapted (6)

| File:line | Case | What changed, and why |
|---|---|---|
| usePrefetchQuery:31 | should prefetch query if query state does not exist | D14 (Suspense): the reader over `suspense(…)`, its pending branch the `Loading...` fallback. No assertion changed |
| usePrefetchQuery:66 | should not prefetch query if query state exists | D14 (Suspense), as 31. **Strengthened, as 4189:** upstream's `queryByText('fetching: true')` matches nothing in either framework, because nothing renders that text. It stays as written, and `client.isFetching() == 0` beside it says what it meant |
| usePrefetchQuery:101 | should let errors fall through and not refetch failed queries | D14 (Suspense, error boundary): the reader's error branch renders the boundary's `Oops!`, and `retryOnMount: false` keeps it from refetching, as it keeps `useSuspenseQuery`. No assertion changed |
| usePrefetchQuery:240 | should not create a suspense waterfall if prefetch is fired | D14 (Suspense): each reader builds a counted fallback instead of its children while pending, which is the waterfall one boundary makes. No assertion changed. The inventory and the plan had it N; it ports, and goes red with the hook inert |
| usePrefetchInfiniteQuery:29 | should prefetch an infinite query if query state does not exist | D14 (Suspense): the reader over `suspense(…)`. No assertion changed |
| usePrefetchInfiniteQuery:88 | should not display fallback if the query cache is already populated | D14 (Suspense), as 29. No assertion changed. The inventory had it N; it is 66's infinite twin and goes red with the lookup removed |

### Omitted (3)

| File:line | Category | Why |
|---|---|---|
| usePrefetchQuery:146, usePrefetchInfiniteQuery:146 | Suspense (D14) | The loop needs a boundary that throws the prefetching component's render away on every suspension. A Flutter element keeps its state, so a port would be 31 with one more wrapper and nothing new to fail. What the case guards, that the hook decides from the cache and not from component state, is held by `review_reproductions_test.dart` (P2-1) and the AP8 group's pending case |
| usePrefetchQuery:180 | `QueryErrorResetBoundary` (D14) | The case is the boundary's reset. The prefetching `App` does not render again after it, so the hook takes no part; its part, not refetching the failed entry, is 101 |

### What the port measured

- **The inventory's suggestion, a plain reader with call counts, fails four of six** (66, 101, 240, 88): a plain reader refetches stale data and retries a failed entry on mount. The suspense hooks' option rewrites are part of the scenario.
- **The inventory's mechanism, a fetch when `getQueryState(key) == null`, is the plan review's P2-1 bug**, which D11 corrects: `getQueryState` with the reader's type throws for an entry cached under another. Both hooks share one untyped `queryCache.find(exact)` lookup.
- **A trap for the documentation, not a defect.** `unawaited(client.query(options))` infers `void` for the query's data type from `unawaited`'s parameter, so the entry is typed `void` and the first typed reader throws `QueryDataTypeError`. The `unawaited_futures` lint suggests exactly that wrapper. `.ignore()` or an explicit type argument avoids it.
- **The AP8 group** in `hook_specifics_test.dart` (8 cases, each running both hooks on keys of their own) holds the acceptance criteria: a build with the entry present does not throw; a failed or pending entry is not fetched again; and no "setState during build" — the `useIsFetching` beside the prefetch is delivered after the frame with a provider and in the microtask flush without one, both checked against the scheduler phase. With a synchronous scheduler the same tree does throw that assertion, so the cases can fail.
- **The suite has teeth.** Seven faults in `use_prefetch.dart`, over the 15 prefetch cases (the 14 above and the P2-1 reproduction): no lookup turns 7 red, a typed `getQueryState` lookup 7, skipping only entries with data 3, no fetch 10, a prefix lookup 1, the future not ignored 1, an observing `useQuery` instead 6. Every case goes red under at least one.

### Second review

GPT-6.1-Sol (xhigh) ran the suite (174 green), reproduced the notes' controls (no lookup 7, no fetch 10, plain readers 4) and added three probes of its own, all green: differently typed cached entries, client and key switches, a fetch outliving its hook. It agreed with every decision: the suspense stand-in, the prefetch's own options, 240 and 88 adapted, plain functions with no state. One finding:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | 66 adds `client.isFetching() == 0`, an assertion upstream does not have, outside D8, D10 and D14 | It is there | Kept, as 4189's strengthening: upstream's own assertion there matches nothing in either framework, which is the case this file allows a strengthening for. The row above says so |
