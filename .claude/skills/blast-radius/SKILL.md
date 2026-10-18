---
name: blast-radius
description: Before changing lib/ of query_kit or query_kit_flutter, or fixing a review finding, find what the change breaks elsewhere (microtasks, zones, frames, the other call styles, upstream at the pin) and prove the one fact it is safe because of by running real code. Use for "blast radius of X", "what could this break", any fix in the core or binding, or a small diff you do not trust.
---

# Blast radius

Find what a change breaks somewhere else before it lands, and prove it with running code, not a writeup. Listing callers is not the job; `grep` does that. The job is the breakage grep does not show.

Why this is reached before every fix here: most rounds of fixes in this repository introduced defects the next fresh pass found (six, three, one; then V-C-1 to V-C-7 and V-B-1 to V-B-5 after the release review; `docs/plans/post-release-backlog.md`, "Why the review stopped where it did"; PORTING_NOTES, the "Second pass" sections). The pattern was the same each time: a fix proven on the case its finding named and broken on the case next to it (`packages/query_kit_flutter/test/reader_shapes_test.dart`, header). This skill asks for the neighbours' proof before the fix lands.

The standing constraints (the pin and how to verify it, ported tests unchanged, the public surface and its three classes, decisions already made) are in `codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md); every change here is classified against them.

## Do not trust your own writeup

A writeup that sounds right reads as convincing whether or not it is true. Find the one or two facts the change's safety depends on and prove them.

### How sure are you

For each fact, get it as far down this ladder as is cheap, and say where it stopped:

1. You said so. Worthless alone.
2. You pointed at the line: a real `file:line` here, or the twin in `query/packages/query-core/src/*.ts` at the pin.
3. You showed the bad case cannot happen: walked the failure step by step and it does not reach.
4. You ran it: a `testFakeAsync` case (`packages/query_kit/test/test_utils.dart`; `testFakeAsyncGuarded` when the fact is about an error reported to the zone) or a `queryWidgetTest` case (`packages/query_kit_flutter/test/harness.dart`) that calls the real code and fails loud if you are wrong. Red before the change, green after, both pasted.
5. You reproduced it where a user meets it: a showcase or task-manager widget test, or a Playwright run against the real server (`examples/*/README.md`).

Step 4 is the one that matters. Check the real thing, not a proxy: not "it compiles", not "the suite is green" before you ran the new case red. When the check fails, suspect the observation before the system.

A proof is scoped to the runtime it ran in. A VM test proves nothing about the compiled-JavaScript run (`dart test --platform chrome`) or about Flutter element behaviour; a browser flow proves nothing about microtask order. Name the runtime next to the rung, and when the fact lives in another runtime, run it there too.

Red before the change means against the old implementation, and red for the disputed behaviour: a compile error or a broken fixture is not red. Where the fix is already in your working tree, show it in an isolated copy (`git worktree add <tmpdir> <parent-sha>`, the new test copied in), never by editing the user's checkout back and forth.

## Steps

1. **Read the change.** The diff, the symbols it adds, changes and deletes, and what it now does differently, including what the diff does not spell out: a notification one microtask earlier, a field read at a different time, a seed run before or after options are committed (V-C-1 was exactly that). Classify it: internal, compatible addition or major (REPOSITORY.md, "The public surface since 1.0.0"). Note the base SHA and the SDK (`flutter --version`) the proofs run on.

2. **Find the one fact it is safe because of.** Most risky changes are safe because of one fact ("this branch only runs when the key changed"). Find it. Spend time here, not on a list of maybes.

3. **Look where grep stops.** In this repository that is:
   - **Microtasks and timers.** `Future.then` on a completed future still runs a microtask later; `Timer(Duration.zero)` is an event, after all microtasks; `fake_async` intercepts timers and microtasks but not `DateTime.now()`; `elapse` is not re-entrant, which is why tests `await time.advance(d)` (`docs/research/dart-flutter-runtime-facts.md`, §1 to §3). Direct observer subscriptions, cache listeners and `onQueryUpdate` deliver synchronously per dispatch; only what goes through a `batch` is deferred (`packages/query_kit/lib/src/notify_manager.dart`, the class doc). A change in when something is awaited or batched is a behaviour change a ported case may pin.
   - **Zones and dropped futures.** A rejected future nobody awaits reaches the zone one microtask later and fails the running test or the file's load test; `unawaited()` does not suppress it, `.ignore()` does (§4; `CLAUDE.md`, "Every internally-held future gets an explicit `.ignore()`"). Check the future's own result and what reached the zone separately.
   - **Frames and elements.** In a debug build, `markNeedsBuild` during a build passes only for the element being built and its descendants, and fails the assertion for anything else; a post-frame callback never requests a frame; a replacement provider's `initState` runs before the old one's `dispose` in the same frame (V-B-3); a `LayoutBuilder` re-runs its builder on a resize without its parent (V4-1); Flutter abandons an element whose `didUpdateWidget` threw without disposing it (V5-2) (§5; PORTING_NOTES, binding passes). A widget test ends with the five-step teardown and steps timers with `tester.pump(duration)`, never `pumpAndSettle` alone (`CLAUDE.md`, "Widget tests need one extra step").
   - **The four call styles.** Builder widget, controller, `State` mixin, `context` extension are equal and proven so; a change to one is checked in all four, and in `reader_shapes_test.dart`'s table (ten shapes × four frames, seeded and polling) if it touches release or rebuild.
   - **The browser.** Both suites also run compiled to JavaScript (`.github/workflows/ci.yml`); `vm-only` cases are tagged. A zero timer is `setTimeout(0)` there, and nested timers clamp to 4 ms past nesting level five (§2).
   - **Upstream at the pin.** Read the twin `.ts`. A move away from upstream either matches a divergence row or adds one; a ported assertion never changes to make a fix pass (REPOSITORY.md, "The upstream pin", "Ported tests stay as ported").
   - **The neighbours of the case.** The same-key path and the key-change path; the throw path (`InitialData.compute` throwing was L2-1, L3-3, V-C-1, V-C-5); the re-entrant path (a listener that calls back in); the detached or unlistened path (`controller.observer.mutateAsync`, V-B-5); the offline and paused path; `clear()` during the operation.
   - **Identity and equality.** Run ownership is checked by identity (`_fetchGeneration`, `_operation`, the scope; ADR-0003, AR-06), not by value equality of results; `==` of value types compares `runtimeType` (L2-4); structural sharing hands back the previous instance or a fixed-length copy, so sealed versus growable and instance identity are observable (PORTING_NOTES, I1).
   - **The public surface.** A new option field is nine places and a row in `value_semantics_test.dart`; a nullable or inferred option is read at every call style's call site; the barrels and their pins are in REPOSITORY.md.
   - **Coverage and the examples.** CI holds line coverage at 99.8 % core and 99.7 % binding (`ci.yml`, "coverage floors", through `tool/check_coverage.dart`); site samples have twins under `examples/doc_snippets/` checked by `site_fences_test.dart`.

4. **Be honest about each risk.** A real chance and a real cost. Keep the confirmed ones; list the checked-and-cleared ones apart. Cite a real `file:line`; a search that finds nothing is an answer; never invent a caller.

5. **Prove the one fact.** Write the test, run it, paste what happened. Three things make the proof worth more than the case it names:
   - **A control.** Run a neighbouring case that was valid before the change, unchanged, in the same run: it stays green, which shows the new test and the fix are not both measuring the same mistake.
   - **A bounded matrix.** Around the changed invariant, enumerate the few dimensions that vary (same key or new key; seeded or fetching; listened or detached; VM or browser) and run the small table, not the one cell the finding named. `reader_shapes_test.dart` is the shape to copy when the invariant is the binding's.
   - **Red against the old implementation**, in the isolated copy described above, then green in the working tree. Both pasted, with the assertion that failed read and quoted.

   The test is named after the finding ID when there is one (the convention of every `release_*_regressions_test.dart` and `review_regressions_test.dart` group) and lives where REPOSITORY.md's port-only rule puts it: a whole port-only file for a Dart-only subject, or a clearly named Dart-only case beside its ported neighbours. A historical regression test stays; it is never replaced by the new one.

6. **Then make the change, and run the gate.** Preconditions: the SDK CI uses (`flutter-version` in `ci.yml`, 3.38.8 today), dependencies already resolved at the root and once in `packages/query_kit_flutter/example` (`CLAUDE.md`). Tests, analysis, `pub` and builds write caches and dependency state; in a read-only task run them in an isolated copy or record them as not run. Each command runs from the repository root on its own, so the order does not matter and no `cd` leaks into the next:

   ```bash
   (cd packages/query_kit && dart test)
   (cd packages/query_kit_flutter && flutter test)
   (cd examples/task_manager && flutter test)
   (cd examples/showcase && flutter test)
   (cd examples/doc_snippets && flutter test)
   dart analyze --fatal-infos packages examples/task_manager examples/showcase examples/doc_snippets tool
   dart format --set-exit-if-changed --output=none packages examples/task_manager/lib examples/task_manager/test examples/showcase/lib examples/showcase/test examples/doc_snippets/lib examples/doc_snippets/test tool
   ```

   The analyzer and formatter lines are CI's (`ci.yml`, the "analyzer" and "formatter" steps); `CLAUDE.md`'s shorter formatter line omits the task manager. Pick suites by what the change can reach, not by the directory edited. A change in `lib/` of the core also runs `(cd packages/query_kit && dart test --platform chrome)`; one in the binding's `lib/` also runs `(cd packages/query_kit_flutter && flutter test --platform chrome --exclude-tags vm-only)`; one that touches the site or a sample runs `(cd website && npm ci && npm run build)` (CI also typechecks first). Passing this block is not CI acceptance (REPOSITORY.md, "Gates").

7. **Hand the diff to a fresh verifier.** For any change in `lib/`, spawn one read-only sub-agent with the diff, the pre-fix parent SHA and the upstream twin, and without your reasoning: its brief is "what did this fix introduce, against the parent and against upstream". The release review's second passes did this (the briefs PORTING_NOTES names as `verify-core.md` and `verify-binding.md`) and found the introduced defects of each round that way. For a wide change, two or three verifiers with the same brief; different readers find different defects. When delegation is not available, make the pass yourself from the same brief and label it self-review. Work the findings through this skill again, and rerun every affected proof after the last edit, the verifier-driven ones included.

8. **Record it.** A PORTING_NOTES row in the section for the current round: ID, what was wrong, reproduced by (the test name, or "by reading" with the reason no test can observe it), what changed, the base and final SHAs, and the counts after (`dart test` totals, measured). The row's claims must be checkable against the diff: "untouched" and "as it was" were both false in rows the second pass corrected.

## What to hand back

- **What it does**, including the part that is not obvious, and its public-surface class.
- **The one fact it is safe because of**, the ladder rung reached, the runtime it was reached in, and the proof. If unproven, write unproven.
- **Risks**: how it breaks, `file:line`, likelihood and cost, how to check; the proof pasted for the ones that matter.
- **Cleared**: what was checked and why it is fine, the control case included.
- **The verifier's findings** and what was done with each.
- **Gates**: which ran, which did not and why.
- **Before merge**: the cheapest test or reproduction that catches the real bug, including the one you wrote.

Written plainly (the `unslop` skill's rules), with real code cited.
