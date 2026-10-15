# query_kit_hooks example

A small app of posts, todos and projects, built on `query_kit_hooks`. It
calls every hook the package exports, each where an app would call it:

| Hook | Where | What it does there |
|---|---|---|
| `useQuery` | Posts tab, post screen | the list of posts; one post |
| `useSelectQuery` | post screen, Todos tab | the posts' ids, to know which comes next; how many todos are open, rebuilt only when that number moves |
| `useQueries` | Posts tab | the posts opened last, each its own query, from the cache |
| `useCombinedQueries` | post screen | the next two posts as one answer (one near the end, none after the last), with one retry |
| `useInfiniteQuery` | Projects tab | projects, a page at a time |
| `usePrefetchQuery` | post screen | a post's comments, asked for beside the post instead of after it |
| `usePrefetchInfiniteQuery` | the shell | the first page of projects, before its tab is opened |
| `useMutation` | Todos tab | ticking a todo, optimistic, and only that todo taken back if the backend refuses; adding one. Writes on different todos overlap: each cancels the list's reads in flight and then puts the backend's answer for its todo into it, the last one to settle refetches it, and no other refetch of the list starts while a write is in flight |
| `useQueryClient` | Todos tab | the tick's write to the cache, its rollback, the backend's answers put into the list, and the reads of the list a write cancels before its answer goes in |
| `useIsFetching` | the shell | how many queries are fetching, app-wide |
| `useIsMutating` | the shell | how many todo writes are in flight |
| `useMutationState` | the shell | the todo writes that failed, and the last reason |
| `useTypedMutationState` | Todos tab | the text of every todo still being added, shown as a pending row; the todos with a tick in flight, whose boxes take no other |

`lib/src/queries.dart` holds every key, query and mutation in one place; the
widgets in `posts.dart`, `todos.dart` and `projects.dart` say which hook reads
what.

## Run it

The package archive holds no platform folders, so create the ones you want
once, then run:

```bash
flutter create . --platforms=web,android,ios
flutter run
```

Without a server the app talks to `lib/src/in_memory_backend.dart`: the same
requests, answered in the app's own process, 300 ms each, so the loading
states are there to see.

## Test it

```bash
flutter test
```

`test/widget_test.dart` walks every tab against the in-memory backend on a
fake clock. `test/backend_contract_test.dart` checks that the in-memory
backend answers as the real one does.

## In the repository

The repository runs the app against the showcase's express server
(`examples/showcase/server`), on port 5178:

```bash
(cd ../../../examples/showcase/server && npm install && PORT=5178 npm run dev)
flutter run -d chrome --dart-define=BACKEND=http://localhost:5178/api
HOOKS_EXAMPLE_SERVER=http://localhost:5178/api flutter test test/backend_contract_test.dart
```

Two end-to-end suites prove every hook against that server, and neither is
in the package archive:

- `e2e/`, Playwright in Chromium, Firefox and WebKit against the web build.
  Each test has a backend scenario of its own and holds a request in the
  browser where it needs the backend not to have answered yet.

  ```bash
  cd e2e && npm ci && npx playwright install chromium && npm run build && npm test
  ```

- `integration_test/`, on a device: an iOS simulator, an Android emulator,
  macOS, Linux or Chrome. Real frames, the real backend through the host's
  network proxy, and a real trip to the background and back.
  `e2e-native/run.sh` starts the backend and the showcase's device control
  on ports of this suite's own (5178, 5179, 5180).

  ```bash
  e2e-native/run.sh ios
  ```

`test/repository_test.dart` keeps both suites complete: every hook the
package exports is called in `lib/`, has a `test.describe` in `e2e/tests/`
and a `group` in `integration_test/`, and `assets/seed.json` is the server's
seed, byte for byte.
