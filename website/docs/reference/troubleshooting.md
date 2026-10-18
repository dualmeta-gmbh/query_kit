---
title: Troubleshooting
description: Symptom first — what you see, why it happens, and what to do instead.
---

# Troubleshooting

Symptom first. Most of these are TanStack Query behaviour that query_kit keeps
on purpose, so the mechanism is worth knowing even once the fix is in.

## My polling never resumes after I paused it in a callback

**Symptom.** A `RefetchInterval.dynamic` (or an `Enabled.when`) reads state
from *outside the cache* — "is a write in flight", a connection flag, a
notifier — and returns "off" while it is set. The flag clears; polling stays
off.

**Mechanism.** Those callbacks are evaluated when **the query** has an event
— a fetch settling, data written — or when the observer is **handed its
options**, which every rebuild of the reading widget does. Nothing tells the
observer that your flag changed. If the widget does not rebuild when the flag
flips, the last answer — off — stands, and with polling off no query event
will come along to ask again. With a mutation it is sharper still:
`onSettled` runs while the mutation still counts as pending, so a callback
asked *then* still says "writing".

**Fix.** Make the flag rebuild the widget that reads the query — a
`ValueListenableBuilder`, a `ListenableBuilder`, a `MutationStateController`
for "a write is in flight", `setState`. The rebuild hands the observer its
options again and both callbacks are asked again. Outside widgets,
`observer.setOptions(options)` with the very same options does the same.

Better still, put outside state into the options as a **value**; then there
is no callback to go stale:

```dart snippet="reference/troubleshooting.md#pause-polling"
QueryObserverOptions<List<Task>> polledTasks({required bool writing}) =>
    QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      // A value, not a callback: the widget rebuilds when `writing` flips,
      // hands over new options, and the observer sees that they changed.
      refetchInterval: writing
          ? RefetchInterval.off
          : const RefetchInterval.every(Duration(seconds: 1)),
    );
```

Keep the callbacks for what they can see: the query's own state — "stop
polling once the job reports `done`".

The rebuild is enough in every call style: `context.query`, `watchQuery`,
the builders and a controller's `setOptions` all hand the options over again,
and the observer compares against what it last committed — so an invalidation
or a write that lands between the flip and the rebuild does not hide it. A
`StaleTime.dynamic` over outside state is re-evaluated the same way, and a
shortened stale time takes effect on the next rebuild. What stays true:
*something* has to rebuild when the outside state flips.

TanStack Query differs here. It compares the old and the new `enabled` *at
the same instant*, so there even a rebuild does not help an `enabled`
callback over outside state: both sides see the same world. And one
consequence runs the other way: a predicate over the query itself whose
answer changes between two rebuilds refetches on the next rebuild if the data
is stale, which TanStack Query does not.

## I removed a device's queries and it is being fetched again

**Symptom.** `removeQueries` under a prefix, on disconnect. A moment later the
entries are back and requests go out to a device that is gone.

**Mechanism.** An observer owns a **key**, not an entry. While a widget that
reads the key is still mounted, its next options update, poll tick or an
optimistic rollback builds the entry again and fetches. TanStack Query does
exactly this.

**Fix.** Remove the readers before the entries: take the device's screens out
of the tree (or give their queries `Enabled.no`) and *then* cancel and remove.

```dart snippet="reference/troubleshooting.md#disconnect"
void disconnect(QueryClient client, QueryKey deviceKey) {
  final filters = QueryFilters(queryKey: deviceKey);
  client.cancelQueries(filters: filters).ignore();
  client.removeQueries(filters: filters);
}
```

If the order cannot be guaranteed, make the transport refuse: an API object
that is closed and throws an error your `retry` policy does not retry costs
one failed fetch instead of a request on the wire.

## The first of two writes lost its state and its callbacks

**Symptom.** Two `mutate` calls on one `MutationController`. The first one's
`isPending`, its result, and the `onSuccess`/`onError` passed *to that call*
never show up.

**Mechanism.** A mutation controller observes its **latest** run. A second
`mutate` moves it on, and per-call callbacks only fire for the run the
controller is still watching — also when the controller was disposed in
between. Callbacks on the **options** always run; they belong to the
mutation, not to who watches it. `useMutation` is the same.

**Fix.** Side effects that must happen go in the options' callbacks. Feedback
for one particular write comes from awaiting `mutateAsync`. To show every
write in flight, not just the last, read the cache with a
`MutationStateController`.

## `QueryDataTypeError` for a list that "is" the right type

**Symptom.** A key holds a `List<Device>`; something reads it as
`List<Object>`, or as a subtype's list, and gets a `QueryDataTypeError`
rather than data.

**Mechanism.** One key, one exact data type. The cache checks the type it is
asked for against what it holds instead of casting blindly, and a
`List<Sub>` is not accepted where the entry was created as `List<Base>` (or
the reverse) — see [type safety in
Dart](../dart-type-safety.md#one-key-one-exact-type).

**Fix.** Give each type its own key, or store a wrapper type that says what
the entry is. `updateQueriesData` over a prefix that spans entries of
different types throws `QueryDataTypeError`, before writing anything, when a
matched entry holds data that is not the updater's `T?`, or when the updater
returns a value some matched entry cannot hold. Beyond that the write is
lenient, as `setQueryData`'s is. Filter narrowly.

## `QueryDataTypeError` after a list of queries of two types

**Symptom.** A `QueriesBuilder`, `QueriesController` or `useQueries` over a
`String` query and an `int` query works. Later a read of one of those keys
as its own type, a `getQueryData<String>` or a `QueryBuilder<String>`, throws
`QueryDataTypeError: … holds Object but was used as String`. Or the list
itself throws `… holds String but was used as Object`, because a typed
reader created the entry first.

**Mechanism.** A Dart `List` has one element type. For options of two data
types Dart infers their common supertype, `Object`, and the collection
creates the entries it does not find as `Object` entries. One key, one exact
type: from then on the entry is an `Object` entry.

**Fix.** Keep a list to one data type. For queries of different types, read
each one on its own and combine the results with `(a, b).combine(…)`.

## A mutation that awaits another mutation never finishes

**Symptom.** Inside a mutation with a `MutationScope`, `await
other.mutateAsync(...)` — and `other` has the **same scope**. Both hang.

**Mechanism.** A scope runs its mutations one at a time. The inner one queues
behind the outer one, which is waiting for the inner one. By design, as in
TanStack Query, and there is no warning.

**Fix.** Give the inner mutation no scope (or a different one), or do the
inner work as a plain call inside the outer mutation function.

## My offline-tolerant app still pauses its writes

**Symptom.** `networkMode: NetworkMode.always` is set in the client's query
defaults — the app talks to a device on the local network — but mutations
still pause when the platform reports offline.

**Mechanism.** Queries and mutations have **separate** client defaults, as in
TanStack Query. Each resolves option → its own client default → `online`.

**Fix.** Set `networkMode` in the mutation defaults as well.

## My "gave up" message disappears after an optimistic write

**Symptom.** Polling stops after five failures and the screen says so. An
optimistic write (`setQueryData`, a patch in `onMutate`) lands, the result
turns into a success — and the "gave up" message is gone, while polling
stays stopped.

**Mechanism.** A manual write turns an error into a success but is not a
fetch, so it does not reset `consecutiveErrorCount`, and a
`RefetchInterval.dynamic` keyed on the count stays off. Only a *fetched*
success resets it.

**Fix.** Key the "gave up" UI on `result.consecutiveErrorCount` — every
`QueryResult` carries it — not on the result being a `QueryError`.

## My optimistic rollback restored the wrong list

**Symptom.** Two writes in one `MutationScope`. The second one fails, its
`onError` restores the snapshot its `onMutate` took — and the first write's
change vanishes from the screen, although it succeeded.

**Mechanism.** A scope serialises the mutation **function** only. `onMutate`
runs when the mutation is submitted, so the second snapshot was taken while
the first write was still in flight. The scope is held until the running
mutation's `onSettled` future completes — `client.isMutating()` still counts
it inside its own `onSettled` — and a queued run reports `isPaused`.

**Fix.** Roll back the row this mutation changed, not a whole-list snapshot.
See [mutation scopes](../guides/mutation-scopes.md).

## `client.query` right after my write returned the old data

**Symptom.** `await client.query(options)` straight after a write comes back
with data from before it.

**Mechanism.** `client.query` joins a fetch already in flight for the key —
one that may have started before your write — rather than starting another,
and a cancelled fetch that reverts resolves it with the reverted data.
TanStack Query's `fetchQuery` does the same.

**Fix.** `await client.refetchQueries(filters: QueryFilters(queryKey: key))`,
whose `cancelRefetch` defaults to `true`, then read the cache.

## A `retry` I passed once is still in force

**Symptom.** One `client.query` passed `retry: RetryPolicy.never`; later
refetches of that query — an invalidation, a focus refetch — do not retry
either.

**Mechanism.** The options a call hands in become the query's options, as an
observer's do: the cache entry is shared and refetches with what it was last
given, as with TanStack Query's `fetchQuery`. Only the no-retry default of a
call that configured nothing is limited to that one fetch.

**Fix.** Leave `retry` out of the imperative call when it should not stick,
or set the policy where the query is observed, which hands it in again.

## "context.query was called with the context an item builder was given"

**Symptom.** A debug build throws this `FlutterError` from `context.query`
(or `context.selectQuery`, `context.infiniteQuery`, `context.mutation`)
inside a `ListView.builder`'s `itemBuilder` — or a `GridView.builder`'s, a
`PageView.builder`'s, a `SliverList`'s, a `ListWheelScrollView.useDelegate`'s
or a two-dimensional scroll view's.

**Mechanism.** The `context` an item builder is given belongs to the list,
not the row. The list builds its rows piecemeal, as they scroll in, and a
read through its context cannot say which row it belongs to: released per
frame, a row still on screen loses its subscription when others scroll in;
kept, every row ever built stays subscribed until the list is rebuilt.
Neither is right, so a debug build refuses the read. A release build keeps
them: no row on screen loses its subscription, and the rows scrolled away
stay subscribed until the list is rebuilt by its parent or unmounts.

**Fix.** Give each row a widget of its own and read in its `build` —
`itemBuilder: (_, i) => TaskTile(ids[i])` with the `context.query` inside
`TaskTile.build` — so each row's reads come and go with it.

## A list item's query is never released

**Symptom.** `watchQuery` in a `QueryMixin` `State`, or `context.query`
through the *outer* `context` — or through an enclosing `LayoutBuilder`'s
`context` — inside an `itemBuilder`. Items scroll away or the list shrinks,
and their queries stay observed.

**Mechanism.** A read made through the reader's context in a nested builder
callback — an `itemBuilder`, a `ValueListenableBuilder`, a `LayoutBuilder`
given the outer `context` — is **added** to the enclosing widget's reads; it
does not release what that widget's own `build` read. A key such a callback
stops reading is released only on that widget's next own build that reads,
or when it goes. For an `itemBuilder` reading through a `LayoutBuilder`'s
*own* `context`, a scroll is no builder run: what it stops reading goes at
the `LayoutBuilder`'s next builder run — new constraints, a notification
from one of its reads, its parent rebuilding it — or when it unmounts. The
trade is deliberate: releasing per run would drop the subscriptions of data
still on screen.

**Fix.** The same: a row widget — a `TaskTile(id)` — that reads its own
query, so its reads come and go with it.

## A `LayoutBuilder` keeps a query picked from an inherited value

**Symptom.** A `LayoutBuilder` (or `OrientationBuilder`) picks its key from
an `InheritedWidget` — a selected tab, a locale, a theme flag — and reads it
through its own `context`. The selection moves, the new key is read, and the
old one stays observed.

**Mechanism.** A `LayoutBuilder`'s builder runs during layout, and a nested
builder handed its `context` looks exactly like it, so a read through it
starts over only when the run is provably the builder's: new constraints (a
resize releases the wide layout's key), a notification from one of its own
reads (a key taken from another query), or a new widget from its parent.
A rebuild caused by an `InheritedWidget` it depends on arrives through
`didChangeDependencies`, which no read can see, so those reads are additive:
the old key goes at the next of the three, or when the `LayoutBuilder`
unmounts. Nothing its builder reads loses its subscription this way.

**Fix.** A key that depends on anything the builder reads belongs in a widget
of its own below the `LayoutBuilder` — `c.maxWidth > 600 ? const WideTasks()
: const NarrowTasks()`, each reading in its own `build` — whose own build is
always provable, and the key goes with the widget.

## A dialog's data stops updating

**Symptom.** A `showDialog` or bottom-sheet builder calls `context.query`
(or `watchQuery`) with the page's `context`. The dialog shows the value it
opened with; later changes do not reach it, or it shows a stale value after
the page rebuilt.

**Mechanism.** A read belongs to the element whose `context` it went through,
and rebuilds that element: the page, not the dialog, which lives in another
subtree. And the page's next own build that reads does not read the
dialog's key, so it is released after that frame while the dialog still
shows it.

**Fix.** Give the dialog a reader of its own: read through the `context` the
dialog builder is given, or in a widget of its own inside the dialog.

## A nested builder kept in a field stops updating

**Symptom.** A `State` keeps a `ValueListenableBuilder` (or an
`AnimatedBuilder`, a `Builder`) in a field so it is not rebuilt, and its
callback reads with `watchQuery` or through the outer `context`. It shows its
data, but a change to that query shows only when its own listenable ticks;
and after the `State` rebuilds for anything else — a `setState`, a change to
a query its `build` reads — its `refetchInterval` stops too, and an entry
nobody else reads is collected after its `gcTime`.

**Mechanism.** The callback's read is the `State`'s, and additive: a change
to the query rebuilds the `State`, and Flutter does not re-run a nested
builder handed the same widget instance, so its text moves only when its own
listenable runs it. The `State`'s own build that reads keeps only what it
reads, and in that frame nobody reads the nested builder's key, so it is
released while the builder still shows it — until the next tick reads it
again. A nested builder the `build` creates anew is re-run, reads again, and
keeps its key.

**Fix.** Give the nested part a widget of its own that reads in its own
`build`; it can then be kept in a field, or be `const`, and its reads live
and go with it.

## After a cache write in a nested builder the outer widget shows old data

**Symptom.** A nested builder — a `ValueListenableBuilder`, a `StatefulBuilder`
or a `LayoutBuilder` — writes the cache while it builds (a `setQueryData`, a
`mutate`) and then reads the same query through the *outer* `context` (or the
mixin's `watchQuery`). The nested part shows the new data; the outer widget,
which read it in its own `build`, goes on showing the old.

**Mechanism.** The nested read happens before the write's notification
reaches the outer widget, and it moves the baseline the outer widget compares
the notification against. When the nested read has no `buildWhen`, the binding
remembers that the outer widget has not shown the change, and it rebuilds once
more. The outer widget's own `buildWhen` makes no difference. When the nested
read has a `buildWhen` — even one that always returns true — that memory is
not kept: the predicate has to be handed the value it saw last, and handing it
an older one would break its contract. The outer widget stays on the old data
until the next real change.

**Fix.** Give the nested part its own reader: read through the `context` the
nested builder is handed, or move it into a widget of its own that reads in its
`build`. Its baseline is then its own. And write the cache from a callback, an
`onPressed` or a `Future`'s completion, not from `build`: a write on every
build, even of identical data, is a change the outer widget has not shown, so
it rebuilds on every frame.

## "QueryClientProvider could not listen to its onlineStatus"

**Symptom.** `OnlineStatus.stream(changes, …)` with a single-subscription
stream works — until the provider remounts, or a second provider is given the
same stream, or switches away from it and back. Then a `FlutterError` says
the stream has already been listened to.

**Mechanism.** A single-subscription stream can be listened to once. It works
only while exactly one provider listens to it, once.

**Fix.** `OnlineStatus.stream(changes.asBroadcastStream(), initial: …)`, built
once outside `build`. Taking `onlineStatus` away, or disposing the provider,
puts the client back online once no other provider has a status for it; a
replacement provider on the same client keeps its own verdict.

## Two keys that "are" the same do not match

**Symptom.** A key holding a record of a list — `['tasks', (ids: [1, 2],)]` —
never matches the key built from the same values again, and every read
fetches anew.

**Mechanism.** A record compares its fields with their own `==`, and a
`List`'s `==` is identity, so the key is new every time. Lists and maps as key
*parts* are compared deeply; inside a record they are not. `DateTime` parts
compare by instant — UTC and local of one moment are one key — but a `DateTime` used as a map *key* inside a part
still compares with its own `==`.

**Fix.** Put the list in the key directly, or use a value class with deep
`==` and `hashCode`.
