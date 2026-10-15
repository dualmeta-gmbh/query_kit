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
| `useQuery.test.tsx`, lines 1–3600 | `use_query_part1_test.dart` | 74 / 78 | done (AP3) |
| `useQuery.test.tsx`, lines 3601–7096 | `use_query_part2_test.dart` | 63 / 77 | done (AP3) |
| `useInfiniteQuery.test.tsx` | `use_infinite_query_test.dart` | 28 / 28 | done (AP4) |
| `useMutation.test.tsx` | `use_mutation_test.dart` | 55 / 61 | done (AP5) |
| `mutationOptions.test.tsx` | `mutation_options_test.dart` | 12 / 14 | done (AP5) |
| `useQueries.test.tsx` | `use_queries_test.dart` | 17 / 24 | done (AP6) |
| `useIsFetching.test.tsx` | `use_is_fetching_test.dart` | 5 / 5 | done (AP7) |
| `useMutationState.test.tsx` | `use_mutation_state_test.dart` | 5 / 5 | done (AP7) |
| `QueryClientProvider.test.tsx` | `query_client_provider_test.dart` | 4 / 4 | done (AP7) |
| `usePrefetchQuery.test.tsx` | `use_prefetch_query_test.dart` | 4 / 6 | done (AP8) |
| `usePrefetchInfiniteQuery.test.tsx` | `use_prefetch_infinite_query_test.dart` | 2 / 3 | done (AP8) |

Every suite is accounted for in full: each case is ported, adapted or
omitted with its reason in the file's section below.

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
- `docs_fences_test.dart` and `doc_twins/` — the docs' samples. Every Dart
  fence of the site's hooks guide and of the README names a region in
  `doc_twins/`, and the fence test holds the two equal, as
  `site_fences_test.dart` does for the rest of the site. It also checks that
  every exported hook appears in a compiled fence of the guide.
  `doc_twins/guide_test.dart` runs the guide's testing sample and both sides
  of the `unawaited(client.query(…))` trap. The fence test reads `website/`,
  so it is skipped in the browser and kept out of the archive by
  `.pubignore`; the twins ship and run. Negative control: one token changed
  in a guide fence, and separately in a README fence, turns it red with "has
  drifted". It refuses a fence or an attribute it cannot read, as below.

### The docs' second review

GPT-6.1-Sol (xhigh) reviewed AP9: the hooks guide, the README, the new
`## Hooks` rows of the differences page, and the fence test. It ran the suite
(327 green), the fence tests of both places and the site build. Three
findings, each reproduced:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | The guide's "When a build throws" table said a query with a `gcTime` of zero is gone after the throw. Collection needs a query nobody observes and that is not fetching. A fetch that did not use `context.signal` runs on past the disposal, so the entry stays past its zero `gcTime`, and the new hook joins that fetch | Yes, with Sol's probe: no observer, the entry still fetching after the timer, one fetch in all | The row now says that only an idle query is collected, and that the end of a fetch that runs on starts the `gcTime` again (`Query`'s settle path schedules collection when nobody observes) |
| S-2 (P2) | Both fence tests read only a fence opened at the margin with three backticks and `dart`, and only an attribute in double quotes. A `~~~dart` fence of invalid Dart with an unknown `twin=`, or a `twin='…'` in single quotes, left every check green, though the site renders both as Dart | Yes, with Sol's script: both green | Both tests refuse what they cannot read rather than skip it: "no fence or attribute is spelled in a way this check cannot read". This one refuses a `twin=` or `snippet=` without double quotes on any site page, and a fence of tildes, of four or more backticks, or with a space before its info string in the guide or the README. `site_fences_test.dart` refuses the same on every page and README it reads, an indented `dart` fence too, and now reads `.mdx` pages as well. Negative controls, each red: a tilde fence, an unknown twin in double and in single quotes, a four-backtick fence and a space before `dart` in the guide, and the guide missing, here; a tilde fence and an indented one, in the site's test |
| S-3 (P2) | The differences page said a React component renders after every timer. At the pin it renders through `useSyncExternalStore` when the observer notifies, and the observer notifies only for a tracked property that changed | Yes, with Sol's Node probe against the pinned source: a completed timer and a refetch that returned the same data, one render in all | The row now says what differs: React renders each notified change on its own, a `notifyManager` batch as one; Flutter builds once per frame for every notification before it. The filtering is the row above it |

Sol's sparring agreed with all ten decisions of the docs agent's notes, the
package-local twins, the `.pubignore` entry, `.ignore()` in the installation
page and one optional hooks column in the React mapping among them. On the
fence test it agreed with the two attributes but not with their claimed
completeness, which is S-2. It found no page that ranks the add-on above or
below the four call styles.

## `useQuery.test.tsx`

**155 upstream cases: 122 ported, 15 adapted, 18 omitted (AP3, #96; two adapted since, by the deep-dive review).** Every
case not listed below is **ported**: upstream's scenario and assertions, in
Dart spelling. Upstream's nested `describe`s are `group`s:
`notifyOnChangeProps` › `function` in part 1, and the three `networkMode`
groups in part 2. No case carries a skip, and the port found no defect in the
hooks, the binding or the core.

### Adapted (15)

| Line | Case | What changed, and why |
|---|---|---|
| 507 | should not get into an infinite loop when removing a query with gcTime 0 and rerendering | `notifyOnChangeProps: ['isPending', 'isSuccess', 'data']` is a `buildWhen` over the same three fields (#15, plan gap table). No assertion changed |
| 738 | should track properties and only re-render when a tracked property changes | Tracked props, reading only `data`, become a `buildWhen` on `dataOrNull` (#15, gap table). No assertion changed |
| 2016 | notifyOnChangeProps › should not re-render when it should only re-render only data change and the selected data did not change | `notifyOnChangeProps: ['data']` is a `buildWhen` on `dataOrNull` (#15, gap table). No assertion changed |
| 2055 | notifyOnChangeProps › should not re-render when it should only re-render on data changes and the data did not change | As 2016 |
| 2109 | notifyOnChangeProps › function › should not re-render when it should only re-render on data changes and the data did not change | The function form is the same `buildWhen` predicate. No assertion changed |
| 2159 | notifyOnChangeProps › function › should not re-render when change props are not actively being tracked | The callback that answers from a ref is a `useCallback` `buildWhen` that answers from a `useRef` flag. Builds 2, 2, 4 as upstream; `delivered` holds all five observer transitions in upstream's order |
| 2814 | should update with data if we observe no properties and throwOnError | D14: `throwOnError: true` is dropped. The query succeeds, so upstream's boundary never runs, and the case's point is left: a build that reads nothing of the result still gets the data. The assertions are unchanged. Omitted at first; the deep-dive review (A-2) showed its remainder ports |
| 2841 | should set status to error instead of throwing when error should not be thrown | D14: the `throwOnError` predicate is dropped. It answers `false` for this case's error, so the boundary never runs: 6923's mapping. The assertions are unchanged. Omitted at first, as 2814 |
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

### Omitted (18)

| Lines | Category | Why |
|---|---|---|
| 2751, 2785, 2873, 6851 | `throwOnError` and error boundaries (D14) | #15: errors are data in the result. 2785 also throws a falsy value, which Dart cannot do. 6851 asserts that a throwing `throwOnError` stops the remount's retry, which needs the boundary |
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
| S-1 (P2) | A `buildWhen` that declines a value change made together with a change in what `retry` acts on keeps the stale `retry`, which then refetched a repaired query. The porting agent had found the same and left it as the specified rule | Yes: fetches (3, 2) where (3, 1) is right | The rule's, not the hook's: `RebuildRule` asked `buildWhen` whenever the value moved, so a predicate that never sees the half beside the value could still veto it. The AP4 review found the same for an infinite query's paging flags, and the binding's own infinite readers shared it. Fixed in the binding: `RebuildRule` takes what is `beside` the value, and a move there rebuilds unasked. `useCombinedQueries` passes which sources are in error and their refetch targets. Held by "a declined value does not hold back what is beside it" in `hook_specifics_test.dart`, (3, 2) without the fix |
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

## `useMutation.test.tsx` and `mutationOptions.test.tsx`

**75 upstream cases (61 and 14): 61 ported, 6 adapted, 8 omitted (AP5, #98).** `useMutation` returns the `MutationController`, so `mutate`, `mutateAsync`, `reset` and the result are its members. `mutationOptions()` is a TypeScript identity, so its file's cases pass a `MutationOptions` value straight to `useIsMutating`, `useMutationState` or `client.isMutating`. The port forced no change to the hook, only its dartdoc: what a build, an unmount and a throw before the call do. No case carries a skip, and the port found no defect in the hooks, the binding or the core.

Three driver mappings run through both files, none of them an adaptation:

- **The online spy.** Upstream's `vi.spyOn(onlineManager, 'isOnline')` is a file-private `OnlineManager` whose `isOnline()` answers a mocked value with no event (1063, 1117, 1176, 1231). So nothing resumes until the case's own `resumePaused()`: one resume, as upstream. `setOnline(false/true)` would emit an event and a mounted client would resume by itself.
- **Clicks with no time between share a frame.** React renders a notification only when the notify manager's `setTimeout(0)` runs, so two synchronous `fireEvent.click`s render nothing between them. Every tap goes in first, then one `pump()`. That applies to useMutation 428, 529, 1301, 1578 and 1650, and to mutationOptions 128, 180, 297, 335, 444 and 486. It is load-bearing in three: with a pump per click, 128 and 297 see 1 mutating where upstream sees 2, and 335 sees 1 where upstream sees 0.
- **`process.on('unhandledRejection')` is a zone around the tap** that starts the mutation (1796, 1841). It takes the callback's own rejection and nothing else; upstream asserts nothing on it, nor does the port.

### Adapted (6)

| File:line | Case | What changed, and why |
|---|---|---|
| useMutation:1117 | should call onMutate even if paused | D14: `onMutate` is told the variables only, so upstream's assertion on its second argument, the mutation callback context, is dropped |
| useMutation:1176 | should optimistically go to paused state if offline | **Strengthened, by D8's frame.** Upstream's two build assertions hold as written. A frame could merge an intermediate `pending, false` into build 1, which upstream's assertion exists to rule out, so the controller's first delivery after the tap (`rec.delivered.first`) is asserted as `pending, true` too |
| useMutation:1650 | should call mutate callbacks only for the last observer | D14: the callbacks' fourth argument, the mutation callback context, is dropped from the four `toHaveBeenCalledWith`. Data, variables, `onMutateResult` and error are asserted |
| useMutation:1761 | should go to error state if onSuccess callback errors | D14: `onError`'s fourth argument is dropped, as 1650 |
| useMutation:1841 | should go to error state if onSettled callback errors | D14: `onError`'s fourth argument is dropped, as 1650. The zone is 1796's |
| useMutation:2479 | should pass a non-undefined onMutateResult alongside context to onSuccess | D14: the three `context.client`, `context.meta` and `context.mutationKey` assertions are dropped. Data, variables and `onMutateResult` are asserted |

The rest are ported. In the spelling: 999 keys its effect on `mutate`, as upstream; 1494 and 1535 get their own client through `createClient:`; 1893 runs without a provider, with `client:` on the hook; 2267's updater `setQueryData` is `updateQueryData`, and its rollback writes only a snapshot that exists (upstream's `undefined` write does nothing); `Promise.all` is `Future.wait(eagerError: true)` (2339, 2378) and `Promise.allSettled` a file-private `_allSettled` (2426); upstream's two-argument `mutationFn` is `mutationFnWithContext` (2507); `useMutationState`'s default `select`, `(m) => m.state`, is written out, because the hook requires one (mutationOptions 375–486, plan D9); and `isMutating(mutationOpts)` is `isMutating(filters: MutationFilters(mutationKey: …))` (mutationOptions 234).

### Omitted (8)

| File:line | Category | Why |
|---|---|---|
| useMutation:1321, 1366 | `throwOnError` and error boundaries (D14) | Errors are data in the result |
| useMutation:1417, 1443 | `throwOnError` (D14) | There is no option to set to `false`; without it the case is 1469, which is ported |
| useMutation:2533, 2555 | Mutation callback context (D14) | Divergence #14/#83: the callbacks get no `MutationFunctionContext`. 2555 exists to avoid a closure over the client, so a rewrite over `useQueryClient()` would defeat it |
| mutationOptions:20, 29 | TypeScript | `mutationOptions()` returns its argument for type inference; a Dart options value is the thing itself |

### What the port measured

- **The inventory was too cautious.** It marked 17 useMutation cases A, and 11 of them are plain ports (999, 1063, 1231, 1301, 1578, 1796, 1893, 2339, 2378, 2426, 2507); so is mutationOptions 234. Every P verdict passed as written. Its two worries did not arise: 999 needs no split of `advance(21)`, because the stepped `advance` keeps all three builds; and 1578's unmount lands before the 10 ms, because `click` and `advance` each build a frame before any time passes.
- **The tear-offs are stable.** `controller.mutate` and `controller.mutateAsync` of one controller are `==`, so every effect upstream keys on them (136 and the like) runs once, as React's stable callbacks do.
- **No upstream case catches a hook that skips `setOptions` on later builds.** 2148 and 2205 click once, with the first build's options. The AP5 group in `hook_specifics_test.dart` holds it: a run in flight calls the latest build's callbacks, a new `mutationKey` starts over at idle, and new options add no build. It also holds D13's mutation rows each as a test of its own: after a throw before the hook the run goes on and its options' callbacks run, `mutate`'s per-call callbacks are dropped, the replacement starts idle while the old run is still pending, and a throw after the last hook disposes nothing. And unmounting does not cancel a running mutation: its cancel token is never cancelled, `mutateAsync` still completes.
- **The suite has teeth.** Three faults in `use_mutation.dart`, over the two files, the AP5 group and `review_reproductions_test.dart` (93 tests): `setOptions` skipped on later builds turns 2 red (both AP5 cases, no upstream one), cancelling the run on dispose 5 (1578, three AP5 cases and H-04), `buildWhen` not passed on 2 (1176 through its strengthened delivery, and the AP5 case).

### Second review

GPT-6.1-Sol (xhigh) ran the suite (233 green), compared all 75 upstream cases against the Dart ones, names, steps and assertions, and added three probes of its own, all green: a delivery queued after disposal, a client switch, and two mutations a frame apart. It reproduced the `setOptions` control. Two findings, each reproduced:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | The zone for 1796 and 1841 swallowed every error, where upstream's handler catches only unhandled rejections: a timer throwing inside the tap left both cases green | Yes: a throwing `Timer` beside the tap, green before | The zone takes only the callback's own error and hands anything else to the zone around the case, which fails it. With the same `Timer` both cases now go red |
| S-2 (P2) | This file still had the spike's `3 / 61` and no account of either suite | — | This section and the status rows; the porting agent's notes were outside the repository by design |

Sol's sparring agreed with the online spy, the shared frame, the written-out `select`, 1176's strengthening, the own clients, the effect keyed on `mutate`, the conditional rollback, the AP5 group, the D13 tests and the D14 exclusions. It disagreed only with the zone as it was built, which is S-1.

## `useIsFetching.test.tsx`, `useMutationState.test.tsx` and `QueryClientProvider.test.tsx`

**14 upstream cases (5, 5 and 4): all 14 ported (AP7, #100).** `useIsFetching` and `useIsMutating` subscribe to their cache directly and count with the latest build's filters (D12). `useMutationState` goes over `MutationStateController`, with `setOptions` on every build, and `useTypedMutationState` over `MutationStateController.typed`. `useQueryClient` is `QueryClientProvider.of` over `useContext()`. `useMutationState.test.tsx` has two top-level describes, `useIsMutating` and `useMutationState`; they are two groups, so the names stay unique and the file diffs against upstream. No case carries a skip, and the port found no defect in the binding or the core.

In the spelling:

- A component that re-renders with its parent, upstream's `IsFetching` or `IsMutating`, is a function returning a new `HookBuilder` (60, 80, 116).
- A `mutate` in a `useEffect` goes through `afterFrame`, the harness's mapping for state changes in an effect (80, 116, 154). It is load-bearing in 80 and 116: with a direct call they record `[1, 1, 0]` where upstream records `[0, 1, 0]`.
- `expect.not.arrayContaining([2])` is `isNot(contains(2))` (129). The build-based "never 2" keeps its strength: with an unfiltered count the case goes red.
- `useMutationState`'s default `select`, `(m) => m.state`, is written out (195), as in AP5.
- Pages with their own client run without a provider (154, 214).
- 52's second client is torn down in the body, the ADR-0002 shape.
- **147's message is the binding's.** `useQueryClient` is `QueryClientProvider.of`, so a missing provider throws the binding's `FlutterError`: "No QueryClientProvider found above this widget. Wrap your app (or the subtree that uses queries) in QueryClientProvider(client: …)." Upstream's "No QueryClient set, use QueryClientProvider to set one" says the same two things, what is missing and what to do. The whole message is asserted, so this is wording, not a weaker assertion. A second message from the hook for the same mistake would teach two things.

### Built on the way

No ported case forced a hook change. Two came from reading the spike, and two hooks are new:

- **Each count and each selection has a hook type of its own.** The spike had one `_CountHook` for both counts, with the cache passed in as closures. `flutter_hooks` keeps a state when the runtime type matches, so `cond ? useIsFetching() : useIsMutating()` across a hot reload kept the query cache's subscription and never rebuilt for mutations. A regular build silently subscribed to the wrong cache instead of throwing `flutter_hooks`' type-mismatch error.
- **The liveness check comes first.** A delivery reads `_disposed`, the generation and `context.mounted` before it reads the filters or calls `setState`. `dispose` never touches `context`.
- **New:** `useTypedMutationState` and `useQueryClient`.

`useQueryClient` takes no `client:`. With one it would be `client ?? useQueryClient()`, which a caller writes in one expression, and the parameter would be the hook's whole result. It is a plain function, not a `Hook`: nothing persists between builds, and `of` already makes the element depend on the provider, so a provider switch rebuilds it.

### What the port measured

- **The inventory was too cautious.** All nine A verdicts in `useIsFetching.test.tsx` and `useMutationState.test.tsx` are plain ports, with upstream's own `advance` steps and `afterFrame` for an effect's `mutate`. 18 needs no second pump, 60 no extra `pump(1ms)`, and 17 no split of `advance(41)`. 17's "build it over a `MutationStateController` filtered on pending" contradicts D12: the count subscribes to the cache directly. QueryClientProvider 147, the tenth A, is 147 above.
- **The AP7 group** in `hook_specifics_test.dart` holds the acceptance criteria and what upstream cannot say:
  - Filters and `select` new on every build cost no subscription and no build, for all four hooks. A cache calls its listeners in subscription order, so each hook has a twin that subscribed after it and is never rebuilt. A hook that subscribed again would be called after its twin, and one that added a subscription would be called more often.
  - Counts and selections follow the latest build.
  - A count delivery queued for the old client does nothing.
  - A hot reload from `useIsFetching` to `useIsMutating` counts mutations.
  - `useTypedMutationState` selects one type, build after build.
  - `useQueryClient` follows its provider.
  - "A delivery queued before disposal adds no build" is `review_reproductions_test.dart`'s H-03.
- **The suite has teeth.** Nine faults in `use_counts.dart`, over the whole package suite:

  | Fault | Red |
  |---|---|
  | The generation and disposed checks removed | 2 |
  | The count subscribes again on every build | 1 |
  | The first build's filters counted | 1 |
  | No comparison with the built count | 6 |
  | The selection's `setOptions` skipped | 1 |
  | The typed hook built untyped | 1 |
  | One shared count hook type | 1 |
  | Either count ignoring its filters | 4 each |

### Second review

GPT-6.1-Sol (xhigh) ran the suite (178 green), checked all 14 cases, names and line references, and added 12 probes of its own. They covered:

- client switches, unmount and a hot-reload replacement, each with a queued delivery;
- typed and untyped selections, equal and changed;
- the latest filters after a switch.

Four findings, each reproduced:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | A delivery queued before a filter switch reads the new filters: the predicate ran 3 times where 1 was expected for fetching, and 4 for mutating. Sol saw no extra build and no stale count | Yes, with Sol's probe | Kept. D12 counts with the latest build's filters, and the dartdoc says so. Upstream does the same: its subscription lives as long as the cache, and a batched `onStoreChange` queued before a render makes React call `getSnapshot`, the latest render's closure over the new filters. The cost is a predicate run, not a build. The generation guards a change of source, a client switch or disposal, and a filter switch keeps the source |
| S-2 (P2) | 147 asserted only the binding message's diagnosis. Upstream's assertion covers the instruction too, and dropping the binding's "Wrap your app…" left the case green | Yes: green with that sentence removed | The whole message is asserted, and the same fault now turns 147 red. Kept as ported: the wording is the binding's, and the content is upstream's |
| S-3 (P2) | The agent's notes said "9 of 10 A verdicts" for two suites that have nine A cases | — | This section says "all nine", and names the tenth |
| S-4 (P3) | Listener order catches a hook that subscribes again, but not one that keeps its subscription and adds another | Yes: Sol's fault, an extra subscription per build, left the test green | Each hook must now be asked exactly as often as its twin. Under the same fault the test is red (8 calls against 2) |

Sol's sparring agreed with:

- the plain `useQueryClient` (preferring an optional `client:` for upstream's sake, though D9 decides against it);
- the two groups;
- the typed select erased with a cast in `setOptions`, the observer keeping the type test;
- the guards for client switches, disposal and hook replacement;
- the comparison with the built count, which builds `[0, 0]` for a `0 → 1 → 0` before the next frame. D5 accepts that one extra build.

It disagreed with listener order as proof of a single subscription (S-4) and with 147 as written (S-2).

## `useInfiniteQuery.test.tsx`

**28 upstream cases: 27 ported, 1 adapted (AP4, #97).** `useInfiniteQuery` returns the `InfiniteQueryController`, as `context.infiniteQuery` does. The pages are in its `value`, and the paging flags beside it. So each case records a snapshot of the controller on every build, `snapshot(controller)`, where upstream records its result object: the flags such as `hasNextPage` and `isFetchingNextPage`, and `isRefetching` and `isRefetchError` from the controller's getters. `result.isRefetching` is true for a page fetch as well, and upstream's infinite result narrows it, as those getters do. Upstream's `toMatchObject` is a file-private `_expectMatch` over a map keyed by upstream's field names, which fails on a key it does not know. No case carries a skip, and the port found no defect in the hooks, the binding or the core. The hook needed no change, only its dartdoc.

In the spelling, none of it changing an assertion:

- `AbortSignal` is `QueryCancelToken`, and `aborted` is `isCancelled` (913, 988, 1733).
- The Promise in 1733 is a `Completer`.
- `useRef` and `useCallback` are the hooks of the same name (305, 1477).
- `Math.random` is `Random` (305).
- `JSON.stringify` is `jsonEncode` (868).
- 1207's render stream under real timers is the list of build snapshots under fake time.
- `isInitialLoading`, an alias upstream deprecates, has no Dart counterpart; `isLoading` itself is asserted (48).
- **A check straight after a click goes before the click's frame.** 487, 598, 692 and 778 assert `isFetching: false` after a click, before React renders the click's fetch. Each is a `tester.tap` without its frame, then `advance`.

### Adapted (1)

| Line | Case | What changed, and why |
|---|---|---|
| 1807 | should not fetch when queryFn is skipToken, and fetch once it is replaced | D14: `skipToken` is out of scope. `queryFn: postId ? fn : skipToken` is a fixed `pageFn` with `enabled` following `postId`, the spelling the core documents for `skipToken`. The assertions are unchanged |

### What the port measured

- **The inventory was too cautious.** It marked 22 cases A, and 21 of them are plain ports: snapshot spelling, `QueryCancelToken`, `Completer`, `useRef`, `useCallback` and `Random`. Its closing line said as much: ten A cases are snapshot-only. 48 keeps its 2 builds under `advance(11)`. 868 needs no extra pump, because `advance(0)` pumps once. 487's check before the frame holds for 598, 692 and 778 too. Correct as it stood:
  - 180: 6 builds, where the gate on the built state drops one equal delivery.
  - 1102 is weak: the page function never reads its signal, so the refetch runs on to page 4 after the unmount, as upstream's does.
  - 1612 needs a frame between the clicks.
  - 1733 drains its 1000 ms sleep.
- **What `buildWhen` sees.**
  - Options:
    - (A) the binding's `BuildWhen<QueryResult<TData>>`;
    - (B) a predicate over the result and the flags, a new public type;
    - (C) no `buildWhen`.
  - Answer: A, the type `InfiniteQueryBuilder` and `context.infiniteQuery` take. One predicate fits the hook and every call style, and the AP4 group passes the same one to three of them and gets the same builds.
  - The port cannot tell the three apart. Over the 28 cases, the agent counted the deliveries: 73 moved the result, 1 moved only the flags (868, a direction switch, unasserted), and 2 were equal and dropped. A prototype of B passed all 28 and could not take a predicate written for `InfiniteQueryBuilder`.
  - The agent's notes held that A never lets a predicate swallow a move of the flags. That is true only for a move of the flags alone, which rebuilds without asking. See the second review's S-1.
- **The AP4 group** in `hook_specifics_test.dart` holds two cases:
  - A move of the paging flags alone rebuilds, `buildWhen` unasked.
  - The hook, `InfiniteQueryBuilder` and `context.infiniteQuery` build alike over the same scenario and predicate.
- **The suite has teeth.** Two faults in `use_infinite_query.dart`, over the port and the hook specifics (41 cases):
  - With the controller's value as the observed state, so the rule cannot see the flags, 2 go red: both AP4 cases. No ported case asserts a move of the flags alone.
  - With `setInfiniteOptions` skipped after the first build, 2 go red: 180 (`placeholderData` across a key change) and 1807 (`enabled` following `postId`), the two cases whose options change between builds.

### Second review

GPT-6.1-Sol (xhigh) ran the suite (188 green) and compared all 28 cases, names, line references, values and counts. It found the 27/1 split justified and no `advance` replaced by one long pump. It reproduced the delivery counts (73, 1, 2).

It added six probes of its own, five of them green:

- a retained `fetchNextPage` after the unmount;
- a retained one across a key switch;
- a client switch;
- a key switch with a late completion;
- a delivery queued before a D13 disposal.

Two findings, each reproduced:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| S-1 (P2) | A predicate that declines a change of the result also holds back a change of the flags made with it. A refetch that keeps the selected data but drops the next page leaves "Load more" on screen while the controller says `hasNextPage == false`: builds stay 1, the predicate is asked twice | Yes, with Sol's probe | The rule's, not the hook's: `RebuildRule` asked `buildWhen` whenever the value moved, so a predicate that never sees the flags could veto them. It is AP6's S-1 for `retry`, and the binding's three infinite call styles shared it. Fixed in the binding: `RebuildRule` takes what is `beside` the value, the flags here, and a move there rebuilds unasked. Held by "a declined value does not hold back what is beside it" in `hook_specifics_test.dart`, "Load more" still on screen without the fix. In the AP4 group, the predicate of "a move of the paging flags alone" is now asked 0 times where it was 3: every delivery in that scenario moves a flag. The fix's own review measured its price, and the same group pins it: a page fetch that keeps the selected value is two builds, one as `isFetchingNextPage` goes up and one as it comes down, the predicate unasked; (1, 1, 2) for builds before, builds after and predicate calls without the fix |
| S-2 (P2) | This file still had the spike's `2 / 28` and no account of the suite | — | This section and the status row |

Sol's sparring:

- **E1, A over B.** It agreed with the parity with the binding but not with the safety argument, which is S-1.
- **The map `_expectMatch`.** It agreed.
- **The controller's `isRefetching`.** It agreed.
- **The controller's ownership.** It agreed, and asked that the hook say what a retained `fetchNextPage` does: after a key switch it acts on the new key, and after the unmount it still fetches into the cache, with no observer and no build. That is upstream's behaviour too, since an observer's `fetchNextPage` fetches whether anything listens or not. The hook's dartdoc says so now.

## The deep-dive review (AP11)

Christian brought the review round forward (2026-10-15), before AP10's
example app. Two models reviewed the whole package at `bc9e9f5`, each in its
own snapshot, with one brief and without the other's results:

- GPT-6-Astra via the Codex CLI, at xhigh;
- Fable 5.1.

The scope was everything in `lib/`, the binding surface `adapter.dart` will
publish, the tests as evidence (each reviewer put faults into `lib/`), and
the shipping files. The lenses, in order: lifecycle under `flutter_hooks`,
fidelity at the pin, the adapter as a `1.x` contract, rebuild decisions,
types, the tests as proof, and release readiness.

### First pass

Six findings, no P1, each reproduced before anything changed. The binding's
share is recorded in the core's PORTING_NOTES, "The hooks' deep-dive review".

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| A-1 (P2) | `RebuildRule.read()` recorded the observed state and `beside` before the value. A `value` that threw left a half-recorded build: a `LateInitializationError` after a failed first read, and `false` from `shouldRebuild` after a failed later one | Yes, with Astra's probe: both red | Fixed in the binding: all three are read before any is recorded. Two cases in the binding's `adapter_test.dart`, red without the fix |
| A-2 (P2) | 2814 and 2841 were omitted as `throwOnError` cases, but their assertions need no boundary, as 6805 and 6923 before them | Yes: both pass with upstream's assertions, and both go red with the hook's subscription removed | Ported as adapted (D14). `useQuery` is 122 ported, 15 adapted, 18 omitted |
| F-1 (P2) | A list of a `String` and an `int` query compiles as `Object`, and the collection creates its entries as `Object` entries. A typed reader of one of those keys then throws `QueryDataTypeError`; where a typed reader came first, the list's build throws | Yes, with Fable's probes, both orders | Documented on `useQueries`, `useCombinedQueries`, `QueriesBuilder` and `QueriesController`, in the hooks guide and on the troubleshooting page. Pinned by "a list of queries of two data types" in `hook_specifics_test.dart`. A debug check needs a member on the core's options, `Object` being a legal data type, so it is the binding's backlog item HB-4, for all four styles at once |
| F-2 (P3) | `adapter.dart` did not export `BuildWhen`, the type `shouldRebuild` takes | Yes: the export list | Exported |
| F-3 (P3) | `useInfiniteQuery` copied the controller's six paging flags as its `beside`. A hooks release resolves against any later binding of the same major, so a flag that binding added would be missing from the copy | Yes, by reading: the copy, and the barrel hiding `besideOf` | `RebuildRule.of(controller)`, the rule the binding's own readers use, built from the binding's own functions. `useQuery`, `useInfiniteQuery` and `useMutation` take it through `ControllerHookState.ruleOf`. With the binding's `besideOf` switched off, three hooks cases go red. Fable proposed exporting `observedStateOf` and `besideOf`; one constructor keeps the surface to the rule, as ADR-0004 decided, and an adapter needs to know neither name |
| F-4 (P3) | The top-type assertion offered only `QueryController.create<Task>` and `QueryBuilder<Task>` as remedies, for a hooks user who wrote neither | Yes: the message, printed | For a plain query it names the options' type argument first, `QueryObserverOptions<Task>(…)`. For options with a select it names the select's return type, with a cast where the select returns `dynamic` (V1-1, V2-1, V2-2) |

Plan decisions reopened: Astra none. Fable reopened D4 narrowly, for the
copy of the flags. F-3 answers it with one constructor rather than two more
exports.

What both checked and found sound: hot reload with a hook's type changed at
a position, a `GlobalKey` move with a `client:` alone, a client switch,
nested `HookBuilder`s on one key, deliveries queued before an unmount, all
39 adapted rows against upstream, inference at ordinary call sites, the
export list, `pubspec.yaml`, `.pubignore`, the dartdoc (no warnings) and a
publish dry-run. Faults that the suite caught: Fable's four, from 1 to 28
red each; Astra's, both new cases red without a subscription.

Not checked by either: the browser and the floor runs, the example app
(AP10, not yet built), and release-mode scheduling.

**Counts after the first pass:** hooks **332**, binding **320**.

### Second pass (verification of the fixes)

GPT-6.1-Sol (xhigh) read the fix commit `1f1a7d9` against both reviews,
upstream at the pin and the code before it. It found no runtime defect that
the fixes introduced:

- A-1, A-2, F-2 and F-3 are closed.
- F-1 is mitigated by documentation, its check deferred to HB-4.
- F-4 was incomplete.

Its negative controls agree with the first pass's: the old `read()` makes 2
cases fail, a missing subscription both new ones, and a switched-off
`besideOf` exactly 3. It found no import cycle: `query_controller.dart` does
not import `rebuild_rule.dart`. Both packages' dartdoc has no warnings.

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| V1-1 (P3) | F-4 left the select's case unserved. Typed raw options with a select that returns `dynamic` failed the same assertion, and the message advised typing the options, which does not help. The core's notes also said every hook takes `QueryObserverOptions` | Yes, with Sol's probe: `QueryController<String, dynamic>` and the plain advice | Where the cached type is named and only the selected one is a top type, the message names the select's return type: `withSelect<Selected>(…)`, `QuerySelectOptions<Raw, Selected>(…)`. Pinned in the binding's "the backstop names the cure" case. Both notes are narrowed |
| V1-2 (P3) | "Every typed reader" was too broad. A read as `Object`, the widened type, works; a read as `String` or `int` throws | Yes: `getQueryData<Object>` returns `'a'` | The guide, the three dartdoc paragraphs, the troubleshooting entry and HB-4 now say "a read as its own type" |

Sparring:

- **F-3:** Sol prefers `RebuildRule.of` to two exported helpers. It keeps
  the controller's details inside the binding and adds no ownership.
- **F-1:** Deferring the check is defensible, as an explicit mitigation.
  HB-4 should check the cached type and not the selected one, since
  different selects over one cached type are safe. The backlog row says so
  now.

Sol noted one older limit that is not the fixes': a value that throws only
inside `shouldRebuild`, after the hooks' own probe read succeeded, escapes
that probe's catch. It predates AP11 and needs a value that throws on one
read and not on the next.

**Counts after the second pass:** hooks **332**, binding **320**.

### Third pass (verification of the second pass's fixes)

GPT-6.1-Sol (xhigh) read `35cb27e` against the second pass's report. It
confirmed the following:

- The assertion's condition is right: a named `TData` passes and a top one
  fails. The message calls no user code, and the whole assertion is gone in
  release.
- `useQuery` and `useSelectQuery` reach the changed constructor. The
  collections bypass it, and the infinite controller and `.observing` keep
  their own messages.
- V1-2's wording and HB-4 hold everywhere.
- The second pass's notes state its report faithfully.

V1-1's fix keyed the message on the wrong thing.

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| V2-1 (P2) | V1-1 branched on whether the cached type is named, not on whether there is a select. Options with a select whose two types are both `dynamic` got the plain advice. Following it, by typing the fetch, only moved the failure to `QueryController<String, dynamic>`. Options widened where they are read, `QueryController<String, Object?>` over plain options, were told to type a select they do not have. The binding's test checked substrings of the message, never that the cure worked | Yes, with Sol's probe: `BOTH-TOP` printed the plain advice, and the widened plain options printed the select's | The message now branches on `options is QuerySelectOptions`. The binding's case covers both shapes. With the old condition, it fails on the both-`dynamic` select. Until the fourth pass (V3-1) it built two casts and `QueryController.create`, and no other cure |
| V2-2 (P3) | Under `strict-casts`, which this repository sets, `withSelect<int>((text) => jsonDecode(text))` does not compile, and neither does a `jsonDecode` tear-off. The advice named only the type argument | Yes. Sol's four forms give four analyzer errors, two of each: `return_of_invalid_type_from_closure` for the closures and `argument_type_not_assignable` for the tear-offs. A fixture with three of the forms gave three. The form with `as int` is clean | The select's advice now leads with the cast, `(raw) => jsonDecode(raw) as Selected`, in `QueryController` and `InfiniteQueryController` alike. Both cases check for it |

Sol's probe pinned the old branch. Run against the fix, it fails in
exactly the three cases that encoded it, and its two cure cases pass.

**Counts after the third pass:** hooks **332**, binding **320**.

### Fourth pass (verification of the third pass's fixes)

GPT-6.1-Sol (xhigh) read `3d225e0`, which includes the plan's new AP12
sweep. It found no defect in code. It confirmed the following:

- The sealed options hierarchy has exactly two finite shapes, and
  `withSelect`, `useQuery` and `useSelectQuery` keep them. So
  `options is QuerySelectOptions` is the right test.
- A typed select needs no cast, and the message makes the cast
  conditional.
- The message calls no user code.
- The regression case fails on the old condition and leaves no listener,
  cache entry or timer behind.
- AP12's other gaps, and the deploy by hand, are real.

It found three inaccurate records:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| V3-1 (P2) | The third pass's notes and the plan said the binding's case builds every cure the messages name. It built two casts and `QueryController.create`. It did not build `withSelect<Selected>`, `QuerySelectOptions<Raw, Selected>`, `QueryBuilder<Task>` or an infinite cure. It checked the infinite message only as text | Yes, by reading the case | The case now builds the cures of the select, plain and infinite messages and reads each one's data: the select's cast, over a named and over a `dynamic` cached type; `withSelect<int>`; `QuerySelectOptions<String, int>`; a typed `queryFn`; the options' type argument; `QueryController.create<String>`; `QueryBuilder<String>`, pumped; and the infinite cast and type arguments. The file is under the analyzer gate, so every cure compiles under `strict-casts` |
| V3-2 (P2) | AP12's sweep missed the release notices. The hooks guide says "not on pub.dev yet", and the hooks README and the root README say "In development". The planned search for `0.1.0-dev` and `^1.0.3` finds none of them. Two items were wrong: the root README has no test counts, and `installation.md` holds `^1.0.0`, not `-dev` | Yes: `hooks.md:22`, the hooks README line 9 and the root README line 23; `installation.md:32` | The sweep lists the three notices and searches for release-status wording too. The root README's item is its notice. `installation.md` gets the add-on into its package table with an install line |
| V3-3 (P3) | The third pass's V2-2 row said three analyzer errors, but the report had four | Yes: the row counted a fixture with three of the four forms | Corrected |

**Counts after the fourth pass:** hooks **332**, binding **320**.

### Fifth pass (verification of the fourth pass's fixes)

GPT-6.1-Sol (xhigh) read `9c51acb` and found no defect in code. It
confirmed four things:

- `reads` does not anchor the type it is handed. A cure with its `queryFn`
  removed infers `dynamic`, and the case throws.
- A read before the first listener sees `setQueryData`. When Sol made those
  reads stale, the case failed.
- Nothing leaks.
- The fourth pass's corrections hold.

It found three gaps in the records:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| V4-1 (P2) | The fourth pass said the case builds every cure the messages name. There are four messages, and the case never built `QueryController.observing`'s cure. No test in the suite refused that constructor. With `.observing` faulted to reject ordinary observers, the case stayed green | Yes, in the backstop case. Two lifetime cases elsewhere in the file already build `.observing` over a typed ordinary observer, and the fault fails them. No test checked its refusal, and none checked that cure where the message is checked. The fifth-pass record first said that no test called it at all; the sixth pass corrected this (V5-1) | The case now refuses an untyped observer and builds the cure: a `QueryObserver<String, String>`, read through a subscription, because `.observing`'s value before the first listener is the observer's last result. With the fault put back, it fails. The V3-1 row now names the three messages it built |
| V4-2 (P2) | AP12's sweep still missed one release-status line. `docs/releasing.md` says the hooks add-on "is not released yet", and none of the search's patterns matches it | Yes: `docs/releasing.md:4` | The sweep lists it, and its search includes "not released" |
| V4-3 (P3) | The V2-1 row said the case "built only two cures". It built three things: two casts and `QueryController.create` | Yes | The row says so |

The sweep's search was then run over the repository, as AP12 will run it.
It found three items the list did not have, and the list has them now:

- the hooks row of `CLAUDE.md`'s state table ("in development");
- `docs/releasing.md`'s hooks section, written in the future tense;
- the lockfiles' `^1.0.3`, which is noise, so the search now excludes the
  lockfiles.

**Counts after the fifth pass:** hooks **332**, binding **320**.

### Sixth pass (verification of the fifth pass's fixes)

GPT-6.1-Sol (xhigh) read `59021f3`. It found no defect in code and
confirmed the following:

- The new refusal infers `dynamic`, and the case fails without the
  assertion.
- The cure reads fresh data, and the case fails without the
  subscription.
- Cleanup releases every observer, subscription and timer.
- The `ignore` is needed and placed right.
- AP12's search finds the release notices.

It found two errors in the records:

| Id | Finding | Reproduced | Outcome |
|---|---|---|---|
| V5-1 (P2) | The V4-1 row said no test calls `QueryController.observing` with an ordinary observer. Two lifetime cases do, at lines 566 and 614 of `review_regressions_test.dart`. The fifth pass had found the gap in the backstop case only | Yes. A search for `QueryController.observing(` missed `QueryController<int, int>.observing(` | The V4-1 row is scoped to the backstop case and names the lifetime cases |
| V5-2 (P2) | The fifth pass's rewording of AP12's sweep dropped the general count update for `CLAUDE.md` and kept only the hooks row. The binding row still says 287 tests, and the suite has 320 | Yes: `CLAUDE.md:128` | The sweep has a separate item for every count in `CLAUDE.md`'s state table again, the binding row's included |

**Counts after the sixth pass:** hooks **332**, binding **320**.

### Seventh pass: nothing new

GPT-6.1-Sol (xhigh) read `4b05c1d` and found nothing new. It confirmed the
following:

- The V4-1 row and the sixth pass's record are faithful.
- Its fault controls give the same results: the lifetime cases and the
  new backstop fail on the fault, and the old backstop passes.
- AP12's restored count item is right, and `CLAUDE.md` still says 287
  for the binding.
- Run with its exclusions, AP12's search finds no actionable line that the
  list misses.

**The round ends here.**

- The first pass reviewed the whole package and found six things.
- The second and third passes found defects in the fixes, all in one
  assertion message.
- The fourth to sixth passes found nothing in code. They found gaps in
  the test and the records.

Every finding was reproduced before it was worked, and none was declined.
Hooks **332**, binding **320**. AP11 stays open until AP10. If AP10
changes `lib/`, a further pass reads that change.
